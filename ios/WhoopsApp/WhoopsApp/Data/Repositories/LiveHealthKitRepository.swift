import Foundation

actor LiveHealthKitRepository: HealthKitRepository {
    private let client: any HealthKitReading
    private let persistence: HealthKitPersistence
    private let anchors: any HealthKitAnchorStoring
    private let metricInclusion: any HealthMetricInclusionStoring
    private var historyCache: [String: HealthKitHistorySnapshot] = [:]

    init(
        client: any HealthKitReading,
        persistence: HealthKitPersistence,
        anchors: any HealthKitAnchorStoring,
        metricInclusion: any HealthMetricInclusionStoring = HealthMetricInclusionStore()
    ) {
        self.client = client
        self.persistence = persistence
        self.anchors = anchors
        self.metricInclusion = metricInclusion
    }

    func authorizationState() -> HealthKitAuthorizationState {
        guard client.isHealthDataAvailable else { return .unavailable }
        return anchors.authorizationWasRequested() ? .requested : .notRequested
    }

    func requestReadAuthorization() async throws {
        try await client.requestReadAuthorization()
        anchors.markAuthorizationRequested()
        _ = try await synchronize()
    }

    func synchronize() async throws -> HealthKitSyncSummary {
        var recordCount = 0
        var deletedCount = 0
        var linkedWorkoutCount = 0
        var firstError: Error?
        var successfulMetricCount = 0
        let synchronizedAt = Date.now

        for metric in HealthMetric.allCases {
            do {
                let result = try await synchronize(metric: metric, at: synchronizedAt)
                recordCount += result.importedCount
                deletedCount += result.deletedCount
                linkedWorkoutCount = result.linkedWorkoutCount
                successfulMetricCount += 1
            } catch {
                firstError = firstError ?? error
            }
        }

        if successfulMetricCount == 0, let firstError { throw firstError }
        return HealthKitSyncSummary(
            syncedAt: synchronizedAt,
            recordCount: recordCount,
            deletedCount: deletedCount,
            linkedWorkoutCount: linkedWorkoutCount
        )
    }

    func history() async throws -> HealthKitHistorySnapshot {
        try await history(metrics: HealthMetric.summaryMetrics)
    }

    func history(metrics: [HealthMetric]) async throws -> HealthKitHistorySnapshot {
        let normalizedMetrics = Array(Set(metrics).intersection(metricInclusion.includedMetrics()))
            .sorted { $0.rawValue < $1.rawValue }
        let cacheKey = normalizedMetrics.map(\.rawValue).joined(separator: "|")
        if let cached = historyCache[cacheKey] { return cached }
        let snapshot = try persistence.history(metrics: normalizedMetrics)
        historyCache[cacheKey] = snapshot
        return snapshot
    }

    func includedMetrics() async -> Set<HealthMetric> {
        metricInclusion.includedMetrics()
    }

    func setMetric(_ metric: HealthMetric, included: Bool) async {
        metricInclusion.setMetric(metric, included: included)
        historyCache.removeAll()
        NotificationCenter.default.post(name: .healthMetricInclusionDidChange, object: metric)
    }

    func startObserving() async {
        guard authorizationState() == .requested else { return }
        await client.startObserving { [weak self] metric in
            guard let self else { return }
            _ = try? await self.synchronize(metric: metric, at: .now)
        }
    }

    private func synchronize(
        metric: HealthMetric,
        at importedAt: Date
    ) async throws -> HealthKitPersistenceResult {
        var anchorData = anchors.anchorData(for: metric)
        var importedCount = 0
        var deletedCount = 0
        var linkedWorkoutCount = 0

        while true {
            let batch = try await client.anchoredChanges(
                for: metric,
                anchorData: anchorData
            )
            guard !batch.hasMore || batch.anchorData != anchorData else {
                throw AppError.invalidHealthKitResponse
            }

            let result = try persistence.apply(
                batch,
                importedAt: importedAt,
                linkWorkouts: metric == .workout && !batch.hasMore
            )
            historyCache.removeAll()
            anchors.saveAnchorData(batch.anchorData, for: metric)
            importedCount += result.importedCount
            deletedCount += result.deletedCount
            linkedWorkoutCount = result.linkedWorkoutCount

            guard batch.hasMore else { break }
            anchorData = batch.anchorData
        }

        return HealthKitPersistenceResult(
            importedCount: importedCount,
            deletedCount: deletedCount,
            linkedWorkoutCount: linkedWorkoutCount
        )
    }
}
