import SwiftUI

@MainActor
final class HealthKitConnectionModel: ObservableObject {
    @Published private(set) var authorizationState: HealthKitAuthorizationState = .notRequested
    @Published private(set) var history = HealthKitHistorySnapshot(
        days: [],
        lastSyncAt: nil,
        recordCount: 0,
        linkedWorkoutCount: 0
    )
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var includedMetrics = Set(HealthMetric.allCases)

    private let repository: any HealthKitRepository

    init(repository: any HealthKitRepository) {
        self.repository = repository
    }

    var statusText: String {
        switch authorizationState {
        case .unavailable: "Unavailable"
        case .notRequested: "Not connected"
        case .requested: "Connected"
        }
    }

    func refresh() async {
        authorizationState = await repository.authorizationState()
        includedMetrics = await repository.includedMetrics()
        do {
            history = try await repository.history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isIncluded(_ metric: HealthMetric) -> Bool {
        includedMetrics.contains(metric)
    }

    func setMetric(_ metric: HealthMetric, included: Bool) {
        if included {
            includedMetrics.insert(metric)
        } else {
            includedMetrics.remove(metric)
        }
        Task {
            await repository.setMetric(metric, included: included)
            includedMetrics = await repository.includedMetrics()
            do {
                history = try await repository.history()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func requestAccess() async {
        await perform {
            try await repository.requestReadAuthorization()
            await repository.startObserving()
        }
    }

    func synchronize() async {
        await perform {
            _ = try await repository.synchronize()
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
            authorizationState = await repository.authorizationState()
            includedMetrics = await repository.includedMetrics()
            history = try await repository.history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
