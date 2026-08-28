import Foundation
import SwiftData
import XCTest

@testable import WhoopsApp

final class HealthKitMilestoneTests: XCTestCase {
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
