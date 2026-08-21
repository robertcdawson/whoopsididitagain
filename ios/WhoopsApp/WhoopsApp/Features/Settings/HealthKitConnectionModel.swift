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
        do {
            history = try await repository.history()
        } catch {
            errorMessage = error.localizedDescription
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
            history = try await repository.history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
