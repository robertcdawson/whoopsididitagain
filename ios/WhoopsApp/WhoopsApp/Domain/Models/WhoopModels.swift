import Foundation

struct WhoopConnectionStatus: Codable, Equatable, Sendable {
    let connected: Bool
    let whoopUserId: String?
    let tokenExpiresAt: Date?
}

struct AuthorizationStart: Decodable, Sendable {
    let authorizationUrl: URL
}

struct AppSessionPair: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresIn: Int
}

enum WhoopResourceType: String, Codable, CaseIterable, Sendable {
    case cycle
    case recovery
    case sleep
    case workout
}

struct WhoopSyncResponse: Decodable, Sendable {
    enum Mode: String, Decodable, Sendable {
        case initial
        case incremental
    }

    let mode: Mode
    let startedAt: Date
    let completedAt: Date
    let resources: [WhoopSyncResource]
}

struct WhoopSyncResource: Decodable, Sendable {
    let resourceType: WhoopResourceType
    let records: [JSONValue]
    let pageCount: Int
    let windowStart: Date
}

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

struct RecoveryHistoryItem: Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let recoveryScore: Int?
    let restingHeartRate: Int?
    let hrvRMSSD: Double?
}

struct SleepHistoryItem: Identifiable, Equatable, Sendable {
    let id: String
    let start: Date
    let end: Date?
    let isNap: Bool
    let sleepPerformance: Double?
    let sleepMinutes: Int?
}

struct WhoopHistorySnapshot: Equatable, Sendable {
    let recoveries: [RecoveryHistoryItem]
    let sleeps: [SleepHistoryItem]
    let lastSyncAt: Date?
}
