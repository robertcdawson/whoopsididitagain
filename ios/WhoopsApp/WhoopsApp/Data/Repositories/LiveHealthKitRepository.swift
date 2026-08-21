import Foundation

actor LiveHealthKitRepository: HealthKitRepository {
    private let client: any HealthKitReading
    private let persistence: HealthKitPersistence
    private let anchors: any HealthKitAnchorStoring

    init(
        client: any HealthKitReading,
        persistence: HealthKitPersistence,
        anchors: any HealthKitAnchorStoring
    ) {
        self.client = client
        self.persistence = persistence
        self.anchors = anchors
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
        try await persistence.history()
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
        let batch = try await client.anchoredChanges(
            for: metric,
            anchorData: anchors.anchorData(for: metric)
        )
        let result = try await persistence.apply(batch, importedAt: importedAt)
        anchors.saveAnchorData(batch.anchorData, for: metric)
        return result
    }
}
