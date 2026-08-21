import Foundation

enum AppError: Error, Equatable, Sendable {
    case invalidResponse
    case server(statusCode: Int, code: String?, message: String?)
    case decoding(String)
    case transport(String)
    case notImplemented
    case healthDataUnavailable
    case invalidHealthKitResponse
}

extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .server(_, _, let message):
            message ?? "The server could not complete the request."
        case .decoding(let message):
            "The response could not be read: \(message)"
        case .transport(let message):
            "The backend could not be reached: \(message)"
        case .notImplemented:
            "This capability is not available yet."
        case .healthDataUnavailable:
            "Apple Health data is not available on this device."
        case .invalidHealthKitResponse:
            "Apple Health returned an incomplete synchronization response."
        }
    }
}
