import Foundation

actor LiveWhoopRepository: WhoopRepository {
    private let client: BackendClient
    private let persistence: WhoopPersistence

    init(client: BackendClient, persistence: WhoopPersistence) {
        self.client = client
        self.persistence = persistence
    }

    func authorizationURL() async throws -> URL {
        try await client.authorizationURL()
    }

    func completeAuthorization(callbackURL: URL) async throws {
        guard callbackURL.scheme == "whoops",
            callbackURL.host == "oauth",
            callbackURL.path == "/callback",
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else {
            throw AppError.invalidResponse
        }
        try await client.exchangeAuthorizationCode(code)
    }

    func connectionStatus() async throws -> WhoopConnectionStatus {
        try await client.connectionStatus()
    }

    func synchronize() async throws -> WhoopSyncSummary {
        let response = try await client.synchronize()
        let count = try await persistence.upsert(response)
        return WhoopSyncSummary(
            syncedAt: response.completedAt,
            recordCount: count,
            mode: response.mode.rawValue
        )
    }

    func history() async throws -> WhoopHistorySnapshot {
        try await persistence.history()
    }

    func disconnect(deleteLocalHistory: Bool) async throws {
        try await client.disconnect()
        if deleteLocalHistory {
            try await persistence.deleteAllWhoopRecords()
        }
    }
}
