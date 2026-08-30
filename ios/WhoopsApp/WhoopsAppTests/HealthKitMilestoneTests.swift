import Foundation
import HealthKit
import SwiftData
import XCTest

@testable import WhoopsApp

final class HealthKitMilestoneTests: XCTestCase {
    private actor ConcurrentReader: HealthKitReading {
        nonisolated let isHealthDataAvailable = true
        nonisolated let firstQueryStarted = XCTestExpectation(description: "First query started")
        private var active = 0
        private let pausesFirstQuery: Bool
        private let failsFirstQuery: Bool
        private let ignoresCancellation: Bool
        private var firstQueryContinuation: CheckedContinuation<Void, Never>?
        private var onChange: (@Sendable (HealthMetric) async -> Void)?
        private(set) var queryCount = 0
        private(set) var maximumActive = 0
        private(set) var anchorsReceived: [HealthMetric: [Data?]] = [:]

        init(
            pausesFirstQuery: Bool = false, failsFirstQuery: Bool = false,
            ignoresCancellation: Bool = false
        ) {
            self.pausesFirstQuery = pausesFirstQuery
            self.failsFirstQuery = failsFirstQuery
            self.ignoresCancellation = ignoresCancellation
        }

        func requestReadAuthorization() async throws {}
        func startObserving(onChange: @escaping @Sendable (HealthMetric) async -> Void) async {
            self.onChange = onChange
        }

        func emitChange(for metric: HealthMetric) async { await onChange?(metric) }

        func releaseFirstQuery() {
            firstQueryContinuation?.resume()
            firstQueryContinuation = nil
        }

        func anchoredChanges(for metric: HealthMetric, anchorData: Data?) async throws
            -> HealthKitChangeBatch
        {
            active += 1
            queryCount += 1
            let isFirst = queryCount == 1
            maximumActive = max(maximumActive, active)
            anchorsReceived[metric, default: []].append(anchorData)
            defer { active -= 1 }
            if isFirst && pausesFirstQuery {
                await withCheckedContinuation { continuation in
                    firstQueryContinuation = continuation
                    firstQueryStarted.fulfill()
                }
            } else if isFirst {
                firstQueryStarted.fulfill()
            }
            // Make suspension explicit; cancellation-ignoring mode models an active HK query
            // whose callback still needs to settle before another query may start.
            if ignoresCancellation {
                try? await Task.sleep(for: .milliseconds(5))
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
            if isFirst && failsFirstQuery { throw AppError.invalidHealthKitResponse }
            let previous =
                anchorData.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init)
                ?? 0
            return HealthKitChangeBatch(
                samples: [], deletedSampleIDs: [],
                anchorData: Data(String(previous + 1).utf8), hasMore: false)
        }
    }

    private final class SuspendedObservationStore: HKHealthStore, @unchecked Sendable {
        let firstDeliverySuspended = XCTestExpectation(
            description: "Observer registration suspended")
        private let lock = NSLock()
        private var executedQueries = 0
        private var didSuspend = false
        private var pendingCompletion: (@Sendable (Bool, Error?) -> Void)?

        var queryCount: Int { lock.withLock { executedQueries } }

        override func execute(_ query: HKQuery) {
            lock.withLock { executedQueries += 1 }
        }

        override func enableBackgroundDelivery(
            for type: HKObjectType, frequency: HKUpdateFrequency,
            withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void
        ) {
            let suspended = lock.withLock {
                guard !didSuspend else { return false }
                didSuspend = true
                pendingCompletion = completion
                return true
            }
            if suspended { firstDeliverySuspended.fulfill() } else { completion(true, nil) }
        }

        func releaseFirstDelivery() {
            let completion = lock.withLock {
                let saved = pendingCompletion
                pendingCompletion = nil
                return saved
            }
            completion?(true, nil)
        }
    }

    @MainActor
    func testConcurrentImportsSerializeQueriesAndNeverReuseStaleAnchors() async throws {
        let reader = ConcurrentReader()
        let anchors = TestAnchorStore()
        let repository = LiveHealthKitRepository(
            client: reader, persistence: HealthKitPersistence(container: try makeContainer()),
            anchors: anchors)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = try await repository.synchronize() }
            }
            try await group.waitForAll()
        }

        let maximumActive = await reader.maximumActive
        let received = await reader.anchorsReceived[.heartRate]
        XCTAssertEqual(maximumActive, 1)
        XCTAssertEqual(received, [nil] + (1...7).map { Data(String($0).utf8) })
        XCTAssertEqual(anchors.anchorData(for: .heartRate), Data("8".utf8))
    }

    @MainActor
    func testObserverBurstAndManualRefreshUseTheSameImportQueue() async throws {
        let reader = ConcurrentReader()
        let anchors = TestAnchorStore()
        anchors.markAuthorizationRequested()
        let repository = LiveHealthKitRepository(
            client: reader, persistence: HealthKitPersistence(container: try makeContainer()),
            anchors: anchors)
        await repository.startObserving()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { _ = try await repository.synchronize() }
            for metric in HealthMetric.allCases {
                group.addTask { await reader.emitChange(for: metric) }
            }
            try await group.waitForAll()
        }
        let maximumActive = await reader.maximumActive
        XCTAssertEqual(maximumActive, 1)
        for metric in HealthMetric.allCases {
            XCTAssertEqual(anchors.anchorData(for: metric), Data("2".utf8))
        }
    }

    @MainActor
    func testFailedQueryReleasesPermitAndDoesNotAdvanceItsAnchor() async throws {
        let reader = ConcurrentReader(failsFirstQuery: true)
        let anchors = TestAnchorStore()
        let repository = LiveHealthKitRepository(
            client: reader, persistence: HealthKitPersistence(container: try makeContainer()),
            anchors: anchors)
        async let first = repository.synchronize()
        async let second = repository.synchronize()
        _ = try await (first, second)
        let maximumActive = await reader.maximumActive
        let received = await reader.anchorsReceived[.heartRate]
        XCTAssertEqual(maximumActive, 1)
        XCTAssertEqual(received, [nil, nil])
        XCTAssertEqual(anchors.anchorData(for: .heartRate), Data("1".utf8))
        XCTAssertEqual(anchors.anchorData(for: .restingHeartRate), Data("2".utf8))
    }

    @MainActor
    func testQueuedCancellationDoesNotWaitForTheActiveQueryOrBlockHistory() async throws {
        let reader = ConcurrentReader(pausesFirstQuery: true)
        let anchors = TestAnchorStore()
        let repository = LiveHealthKitRepository(
            client: reader, persistence: HealthKitPersistence(container: try makeContainer()),
            anchors: anchors)
        let first = Task { try await repository.synchronize() }
        await fulfillment(of: [reader.firstQueryStarted], timeout: 3)
        let cancelledFinished = expectation(description: "Queued caller cancelled promptly")
        let cancelled = Task {
            defer { cancelledFinished.fulfill() }
            do {
                _ = try await repository.synchronize()
                XCTFail("Cancelled queued sync must not run")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        // Give the new caller a chance to enqueue while the first query remains suspended.
        for _ in 0..<20 { await Task.yield() }
        cancelled.cancel()
        await fulfillment(of: [cancelledFinished], timeout: 3)
        let history = try await repository.history()
        let queryCount = await reader.queryCount
        XCTAssertEqual(history.recordCount, 0)
        XCTAssertEqual(queryCount, 1)
        XCTAssertNil(anchors.anchorData(for: .heartRate))
        await reader.releaseFirstQuery()
        _ = try await first.value
        await cancelled.value
        _ = try await repository.synchronize()
        XCTAssertEqual(anchors.anchorData(for: .heartRate), Data("2".utf8))
    }

    @MainActor
    func testActiveCancellationWaitsForQuerySettlementWithoutCommittingItsBatch() async throws {
        let reader = ConcurrentReader(pausesFirstQuery: true, ignoresCancellation: true)
        let anchors = TestAnchorStore()
        let repository = LiveHealthKitRepository(
            client: reader, persistence: HealthKitPersistence(container: try makeContainer()),
            anchors: anchors)
        let cancelled = Task { try await repository.synchronize() }
        await fulfillment(of: [reader.firstQueryStarted], timeout: 3)
        cancelled.cancel()
        await reader.releaseFirstQuery()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled active sync must not commit or query another metric")
        } catch { XCTAssertTrue(error is CancellationError) }
        let queryCount = await reader.queryCount
        XCTAssertEqual(queryCount, 1)
        XCTAssertNil(anchors.anchorData(for: .heartRate))
        _ = try await repository.synchronize()
        XCTAssertEqual(anchors.anchorData(for: .heartRate), Data("1".utf8))
    }

    @MainActor
    func testObserverStartupIsClaimedBeforeItsFirstSuspension() async {
        let store = SuspendedObservationStore()
        let client = HealthKitClient(healthStore: store)
        let first = Task { await client.startObserving { _ in } }
        await fulfillment(of: [store.firstDeliverySuspended], timeout: 3)

        await client.startObserving { _ in }
        let countWhileStarting = store.queryCount
        store.releaseFirstDelivery()
        await first.value
        XCTAssertEqual(countWhileStarting, 1)
        XCTAssertEqual(store.queryCount, HealthMetric.allCases.count)
    }

    @MainActor
    func testMetricInclusionNotificationIsDeliveredOnMainThread() async throws {
        let suite = "HealthKitMilestoneTests.notification.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = LiveHealthKitRepository(
            client: FakeReader(batches: [:]),
            persistence: HealthKitPersistence(container: try makeContainer()),
            anchors: TestAnchorStore(),
            metricInclusion: HealthMetricInclusionStore(defaults: defaults))
        let delivered = expectation(description: "Metric inclusion notification")
        let token = NotificationCenter.default.addObserver(
            forName: .healthMetricInclusionDidChange, object: nil, queue: nil
        ) { _ in
            XCTAssertTrue(Thread.isMainThread)
            delivered.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        await repository.setMetric(.hrvSDNN, included: false)
        await fulfillment(of: [delivered], timeout: 3)
    }

    private final class FakeReader: HealthKitReading, @unchecked Sendable {
        let isHealthDataAvailable = true
        private let lock = NSLock()
        private var batches: [HealthMetric: [HealthKitChangeBatch]]
        private(set) var anchorsReceived: [HealthMetric: [Data?]] = [:]

        init(batches: [HealthMetric: HealthKitChangeBatch]) {
            self.batches = batches.mapValues { [$0] }
        }

        init(pagedBatches: [HealthMetric: [HealthKitChangeBatch]]) {
            batches = pagedBatches
        }

        func requestReadAuthorization() async throws {}

        func anchoredChanges(
            for metric: HealthMetric,
            anchorData: Data?
        ) async throws -> HealthKitChangeBatch {
            lock.withLock {
                anchorsReceived[metric, default: []].append(anchorData)
                guard var pages = batches[metric], !pages.isEmpty else {
                    return HealthKitChangeBatch(
                        samples: [],
                        deletedSampleIDs: [],
                        anchorData: anchorData ?? Data(metric.rawValue.utf8),
                        hasMore: false
                    )
                }
                let next = pages.removeFirst()
                batches[metric] = pages
                return next
            }
        }

        func startObserving(
            onChange: @escaping @Sendable (HealthMetric) async -> Void
        ) async {}
    }

    private final class TestAnchorStore: HealthKitAnchorStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false
        private var anchors: [HealthMetric: Data] = [:]

        func authorizationWasRequested() -> Bool {
            lock.withLock { requested }
        }

        func markAuthorizationRequested() {
            lock.withLock { requested = true }
        }

        func anchorData(for metric: HealthMetric) -> Data? {
            lock.withLock { anchors[metric] }
        }

        func saveAnchorData(_ data: Data, for metric: HealthMetric) {
            lock.withLock { anchors[metric] = data }
        }
    }

    @MainActor
    func testPartialPermissionImportKeepsAvailableTypesAndAnchorsAllQueries() async throws {
        let sample = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            metric: .restingHeartRate,
            start: "2026-08-16T14:00:00Z",
            end: "2026-08-16T14:01:00Z",
            value: 54,
            localDay: "2026-08-16"
        )
        let reader = FakeReader(batches: [
            .restingHeartRate: HealthKitChangeBatch(
                samples: [sample],
                deletedSampleIDs: [],
                anchorData: Data("resting-anchor".utf8),
                hasMore: false
            )
        ])
        let anchors = TestAnchorStore()
        let persistence = HealthKitPersistence(container: try makeContainer())
        let repository = LiveHealthKitRepository(
            client: reader,
            persistence: persistence,
            anchors: anchors
        )

        try await repository.requestReadAuthorization()
        let history = try await repository.history()
        let authorizationState = await repository.authorizationState()

        XCTAssertEqual(authorizationState, .requested)
        XCTAssertEqual(history.recordCount, 1)
        XCTAssertEqual(history.days.first?.restingHeartRate, 54)
        XCTAssertNotNil(anchors.anchorData(for: .heartRate))
        XCTAssertNotNil(anchors.anchorData(for: .restingHeartRate))
    }

    @MainActor
    func testPagedImportCommitsEachBatchAndAdvancesItsAnchor() async throws {
        let firstAnchor = Data("page-one".utf8)
        let finalAnchor = Data("page-two".utf8)
        let reader = FakeReader(pagedBatches: [
            .heartRate: [
                HealthKitChangeBatch(
                    samples: [
                        snapshot(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                            metric: .heartRate,
                            start: "2026-08-16T14:00:00Z",
                            end: "2026-08-16T14:01:00Z",
                            value: 75,
                            localDay: "2026-08-16"
                        )
                    ],
                    deletedSampleIDs: [],
                    anchorData: firstAnchor,
                    hasMore: true
                ),
                HealthKitChangeBatch(
                    samples: [
                        snapshot(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                            metric: .heartRate,
                            start: "2026-08-16T14:02:00Z",
                            end: "2026-08-16T14:03:00Z",
                            value: 76,
                            localDay: "2026-08-16"
                        )
                    ],
                    deletedSampleIDs: [],
                    anchorData: finalAnchor,
                    hasMore: false
                ),
            ]
        ])
        let anchors = TestAnchorStore()
        let persistence = HealthKitPersistence(container: try makeContainer())
        let repository = LiveHealthKitRepository(
            client: reader,
            persistence: persistence,
            anchors: anchors
        )

        let summary = try await repository.synchronize()

        XCTAssertEqual(summary.recordCount, 2)
        XCTAssertEqual(try persistence.history().recordCount, 2)
        XCTAssertEqual(anchors.anchorData(for: .heartRate), finalAnchor)
        XCTAssertEqual(reader.anchorsReceived[.heartRate]?.count, 2)
        XCTAssertNil(reader.anchorsReceived[.heartRate]?[0])
        XCTAssertEqual(reader.anchorsReceived[.heartRate]?[1], firstAnchor)
    }

    @MainActor
    func testRepeatedBatchIsIdempotentAndDeletionRemovesTheSourceRecord() throws {
        let container = try makeContainer()
        let persistence = HealthKitPersistence(container: container)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let sample = snapshot(
            id: id,
            metric: .hrvSDNN,
            start: "2026-08-16T14:00:00Z",
            end: "2026-08-16T14:01:00Z",
            value: 48.5,
            localDay: "2026-08-16"
        )
        let batch = HealthKitChangeBatch(
            samples: [sample],
            deletedSampleIDs: [],
            anchorData: Data("one".utf8),
            hasMore: false
        )

        _ = try persistence.apply(batch, importedAt: .now)
        _ = try persistence.apply(batch, importedAt: .now)
        XCTAssertEqual(try persistence.history().recordCount, 1)

        _ = try persistence.apply(
            HealthKitChangeBatch(
                samples: [],
                deletedSampleIDs: [id],
                anchorData: Data("two".utf8),
                hasMore: false
            ),
            importedAt: .now
        )
        XCTAssertEqual(try persistence.history().recordCount, 0)
    }

    @MainActor
    func testTargetedHistorySkipsUnrequestedMetricsButKeepsStoreMetadata() throws {
        let persistence = HealthKitPersistence(container: try makeContainer())
        let hrv = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            metric: .hrvSDNN,
            start: "2026-08-16T14:00:00Z",
            end: "2026-08-16T14:01:00Z",
            value: 48,
            localDay: "2026-08-16"
        )
        let restingHeartRate = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            metric: .restingHeartRate,
            start: "2026-08-16T14:00:00Z",
            end: "2026-08-16T14:01:00Z",
            value: 54,
            localDay: "2026-08-16"
        )
        _ = try persistence.apply(
            HealthKitChangeBatch(
                samples: [hrv, restingHeartRate],
                deletedSampleIDs: [],
                anchorData: Data("targeted".utf8),
                hasMore: false
            ),
            importedAt: .now
        )

        let history = try persistence.history(metrics: [.hrvSDNN])

        XCTAssertEqual(history.recordCount, 2)
        XCTAssertEqual(history.days.first?.hrvSDNNMilliseconds, 48)
        XCTAssertNil(history.days.first?.restingHeartRate)
    }

    @MainActor
    func testExcludedMetricIsRetainedButRemovedFromEveryHistoryProjection() async throws {
        let suiteName = "HealthKitMilestoneTests.metric-inclusion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let inclusion = HealthMetricInclusionStore(defaults: defaults)
        inclusion.setMetric(.hrvSDNN, included: false)

        let persistence = HealthKitPersistence(container: try makeContainer())
        let hrv = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            metric: .hrvSDNN,
            start: "2026-08-16T14:00:00Z",
            end: "2026-08-16T14:01:00Z",
            value: 48,
            localDay: "2026-08-16"
        )
        let restingHeartRate = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            metric: .restingHeartRate,
            start: "2026-08-16T14:00:00Z",
            end: "2026-08-16T14:01:00Z",
            value: 54,
            localDay: "2026-08-16"
        )
        _ = try persistence.apply(
            HealthKitChangeBatch(
                samples: [hrv, restingHeartRate],
                deletedSampleIDs: [],
                anchorData: Data("selection".utf8),
                hasMore: false
            ),
            importedAt: .now
        )
        let repository = LiveHealthKitRepository(
            client: FakeReader(batches: [:]),
            persistence: persistence,
            anchors: TestAnchorStore(),
            metricInclusion: inclusion
        )

        let excludedHistory = try await repository.history()

        XCTAssertEqual(excludedHistory.recordCount, 2)
        XCTAssertEqual(excludedHistory.days.first?.restingHeartRate, 54)
        XCTAssertNil(excludedHistory.days.first?.hrvSDNNMilliseconds)
        let includedMetrics = await repository.includedMetrics()
        XCTAssertFalse(includedMetrics.contains(.hrvSDNN))

        await repository.setMetric(.hrvSDNN, included: true)
        let restoredHistory = try await repository.history(metrics: [.hrvSDNN])

        XCTAssertEqual(restoredHistory.recordCount, 2)
        XCTAssertEqual(restoredHistory.days.first?.hrvSDNNMilliseconds, 48)
    }

    @MainActor
    func testDuplicateWorkoutLinkPreservesBothSourceRecords() throws {
        let container = try makeContainer()
        let whoopContext = ModelContext(container)
        let start = Self.date("2026-08-16T17:00:00Z")
        let end = Self.date("2026-08-16T18:00:00Z")
        whoopContext.insert(
            WhoopSourceRecord(
                id: "workout:whoop-1",
                resourceType: WhoopResourceType.workout.rawValue,
                sourceIdentifier: "whoop-1",
                sourceUpdatedAt: end,
                startAt: start,
                endAt: end,
                rawPayload: Data(),
                lastImportedAt: .now
            )
        )
        try whoopContext.save()

        let healthSample = snapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            metric: .workout,
            start: "2026-08-16T17:03:00Z",
            end: "2026-08-16T18:02:00Z",
            value: 59,
            localDay: "2026-08-16"
        )
        let persistence = HealthKitPersistence(container: container)

        _ = try persistence.apply(
            HealthKitChangeBatch(
                samples: [healthSample],
                deletedSampleIDs: [],
                anchorData: Data("workout".utf8),
                hasMore: false
            ),
            importedAt: .now
        )
        let history = try persistence.history()

        XCTAssertEqual(history.recordCount, 1)
        XCTAssertEqual(history.linkedWorkoutCount, 1)
        XCTAssertEqual(try whoopContext.fetchCount(FetchDescriptor<WhoopSourceRecord>()), 1)
    }

    func testDayKeyUsesTheSamplesTimeZoneAcrossTravelAndDST() {
        let instant = Self.date("2026-03-08T07:30:00Z")

        XCTAssertEqual(
            HealthDayKey.day(
                containing: instant,
                timeZone: TimeZone(identifier: "America/Los_Angeles")!
            ),
            "2026-03-07"
        )
        XCTAssertEqual(
            HealthDayKey.day(
                containing: instant,
                timeZone: TimeZone(identifier: "Asia/Tokyo")!
            ),
            "2026-03-08"
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: WhoopSourceRecord.self,
            HealthKitSourceRecord.self,
            WorkoutSourceLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func snapshot(
        id: UUID,
        metric: HealthMetric,
        start: String,
        end: String,
        value: Double,
        localDay: String
    ) -> HealthSampleSnapshot {
        HealthSampleSnapshot(
            id: id,
            metric: metric,
            startAt: Self.date(start),
            endAt: Self.date(end),
            value: value,
            unit: metric == .hrvSDNN ? "ms" : nil,
            categoryValue: nil,
            workoutActivityType: metric == .workout ? 20 : nil,
            sourceName: "Test Watch",
            sourceBundleIdentifier: "com.example.test-watch",
            timeZoneIdentifier: "America/Los_Angeles",
            timeZoneOffsetSeconds: -25_200,
            localDay: localDay
        )
    }

    private static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
