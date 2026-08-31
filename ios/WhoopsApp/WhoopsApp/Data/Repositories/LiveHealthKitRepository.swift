import Foundation

actor LiveHealthKitRepository: HealthKitRepository {
    private let client: any HealthKitReading
    private let persistence: HealthKitPersistence
    private let anchors: any HealthKitAnchorStoring
    private let metricInclusion: any HealthMetricInclusionStoring
    private var historyCache: [String: HealthKitHistorySnapshot] = [:]
    private var isImporting = false
    private var importWaiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

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
            try Task.checkCancellation()
            do {
                let result = try await synchronize(metric: metric, at: synchronizedAt)
                recordCount += result.importedCount
                deletedCount += result.deletedCount
                linkedWorkoutCount = result.linkedWorkoutCount
                successfulMetricCount += 1
            } catch is CancellationError {
                throw CancellationError()
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
        await MainActor.run {
            NotificationCenter.default.post(name: .healthMetricInclusionDidChange, object: metric)
        }
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
        // Actor methods are reentrant at await. Hold a suspending FIFO permit across
        // query -> persistence -> anchor advancement, including every page, so manual
        // refreshes and observer callbacks cannot activate parallel queries or use stale anchors.
        try await acquireImportPermit()
        defer { releaseImportPermit() }
        try Task.checkCancellation()
        var anchorData = anchors.anchorData(for: metric)
        var importedCount = 0
        var deletedCount = 0
        var linkedWorkoutCount = 0

        while true {
            try Task.checkCancellation()
            let batch = try await client.anchoredChanges(
                for: metric,
                anchorData: anchorData
            )
            // Let an already-running HealthKit query settle before handing off the permit,
            // but do not commit its batch if the caller cancelled in the meantime.
            try Task.checkCancellation()
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

    private func acquireImportPermit() async throws {
        try Task.checkCancellation()
        guard isImporting else {
            isImporting = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    importWaiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelImportWaiter(id: id) }
        }
    }

    private func releaseImportPermit() {
        if importWaiters.isEmpty {
            isImporting = false
        } else {
            // The permit remains held while ownership passes to the next caller.
            importWaiters.removeFirst().continuation.resume()
        }
    }

    private func cancelImportWaiter(id: UUID) {
        guard let index = importWaiters.firstIndex(where: { $0.id == id }) else { return }
        importWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
