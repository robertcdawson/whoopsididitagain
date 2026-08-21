import Foundation

struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload
    let meta: APIMetadata
}

struct APIMetadata: Decodable, Equatable, Sendable {
    let requestId: String
}

struct APIErrorEnvelope: Decodable, Equatable, Sendable {
    let error: APIErrorDetail
    let meta: APIMetadata
}

struct APIErrorDetail: Decodable, Equatable, Sendable {
    let code: String
    let message: String
    let retryable: Bool
}

struct BackendHealth: Decodable, Equatable, Sendable {
    let status: String
    let service: String
    let version: String
    let timestamp: Date
}
