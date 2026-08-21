import Foundation

actor BackendClient: BackendHealthChecking {
    private let baseURL: URL
    private let session: URLSession
    private let sessionStore: any SessionStoring
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init(
        baseURL: URL,
        sessionStore: any SessionStoring,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.sessionStore = sessionStore
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .backendISO8601
        self.decoder = decoder
    }

    func health() async throws -> BackendHealth {
        try await request(path: "api/v1/health", authorized: false)
    }

    func authorizationURL() async throws -> URL {
        struct Body: Encodable { let installationId: String }
        let response: AuthorizationStart = try await request(
            path: "api/v1/auth/whoop/start",
            method: "POST",
            body: Body(installationId: try sessionStore.installationId()),
            authorized: false
        )
        return response.authorizationUrl
    }

    func exchangeAuthorizationCode(_ code: String) async throws {
        struct Body: Encodable { let code: String }
        let appSession: AppSessionPair = try await request(
            path: "api/v1/auth/session/exchange",
            method: "POST",
            body: Body(code: code),
            authorized: false
        )
        try sessionStore.save(session: appSession)
    }

    func connectionStatus() async throws -> WhoopConnectionStatus {
        guard try sessionStore.session() != nil else {
            return WhoopConnectionStatus(connected: false, whoopUserId: nil, tokenExpiresAt: nil)
        }
        return try await request(path: "api/v1/whoop/status", authorized: true)
    }

    func synchronize() async throws -> WhoopSyncResponse {
        try await request(path: "api/v1/whoop/sync", authorized: true)
    }

    func disconnect() async throws {
        struct DisconnectResult: Decodable { let disconnected: Bool }
        let _: DisconnectResult = try await request(
            path: "api/v1/auth/whoop/disconnect",
            method: "POST",
            authorized: true
        )
        try sessionStore.deleteSession()
    }

    private func refreshSession() async throws -> AppSessionPair {
        struct Body: Encodable { let refreshToken: String }
        guard let current = try sessionStore.session() else {
            throw AppError.server(
                statusCode: 401,
                code: "missing_session",
                message: "Connect WHOOP first."
            )
        }
        let replacement: AppSessionPair = try await request(
            path: "api/v1/auth/session/refresh",
            method: "POST",
            body: Body(refreshToken: current.refreshToken),
            authorized: false
        )
        try sessionStore.save(session: replacement)
        return replacement
    }

    private func request<ResponseBody: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        authorized: Bool,
        retryingAfterRefresh: Bool = false
    ) async throws -> ResponseBody {
        try await request(
            path: path,
            method: method,
            encodedBody: nil,
            authorized: authorized,
            retryingAfterRefresh: retryingAfterRefresh
        )
    }

    private func request<ResponseBody: Decodable & Sendable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        authorized: Bool
    ) async throws -> ResponseBody {
        try await request(
            path: path,
            method: method,
            encodedBody: try encoder.encode(body),
            authorized: authorized,
            retryingAfterRefresh: false
        )
    }

    private func request<ResponseBody: Decodable & Sendable>(
        path: String,
        method: String,
        encodedBody: Data?,
        authorized: Bool,
        retryingAfterRefresh: Bool
    ) async throws -> ResponseBody {
        let endpoint = URL(string: path, relativeTo: baseURL)!
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = encodedBody
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-request-id")
        if encodedBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if authorized, let appSession = try sessionStore.session() {
            request.setValue(
                "Bearer \(appSession.accessToken)", forHTTPHeaderField: "authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        if authorized, httpResponse.statusCode == 401, !retryingAfterRefresh {
            _ = try await refreshSession()
            return try await self.request(
                path: path,
                method: method,
                encodedBody: encodedBody,
                authorized: true,
                retryingAfterRefresh: true
            )
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let apiError = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw AppError.server(
                statusCode: httpResponse.statusCode,
                code: apiError?.error.code,
                message: apiError?.error.message
            )
        }

        do {
            return try decoder.decode(APIEnvelope<ResponseBody>.self, from: data).data
        } catch {
            throw AppError.decoding(error.localizedDescription)
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    fileprivate static var backendISO8601: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: value) ?? wholeSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date"
            )
        }
    }
}
