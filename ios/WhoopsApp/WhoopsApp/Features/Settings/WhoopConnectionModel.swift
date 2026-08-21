import AuthenticationServices
import SwiftUI

@MainActor
final class WhoopConnectionModel: NSObject, ObservableObject,
    ASWebAuthenticationPresentationContextProviding
{
    @Published private(set) var status = WhoopConnectionStatus(
        connected: false,
        whoopUserId: nil,
        tokenExpiresAt: nil
    )
    @Published private(set) var isWorking = false
    @Published var deleteLocalHistoryOnDisconnect = false
    @Published var errorMessage: String?

    private let repository: any WhoopRepository
    private var authenticationSession: ASWebAuthenticationSession?

    init(repository: any WhoopRepository) {
        self.repository = repository
    }

    func refresh() async {
        do {
            status = try await repository.connectionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connect() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil

        do {
            let authorizationURL = try await repository.authorizationURL()
            let callbackURL = try await authenticate(at: authorizationURL)
            try await repository.completeAuthorization(callbackURL: callbackURL)
            status = try await repository.connectionStatus()
            _ = try await repository.synchronize()
        } catch ASWebAuthenticationSessionError.canceledLogin {
            // A user cancellation is an expected outcome, not an app error.
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    func disconnect() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            try await repository.disconnect(deleteLocalHistory: deleteLocalHistoryOnDisconnect)
            status = WhoopConnectionStatus(
                connected: false,
                whoopUserId: nil,
                tokenExpiresAt: nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme("whoops")
            ) { [weak self] callbackURL, error in
                self?.authenticationSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AppError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            guard session.start() else {
                authenticationSession = nil
                continuation.resume(throwing: AppError.transport("Unable to open WHOOP sign-in."))
                return
            }
        }
    }
}
