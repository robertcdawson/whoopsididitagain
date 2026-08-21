import Foundation

struct WhoopSyncSummary: Equatable, Sendable {
    let syncedAt: Date
    let recordCount: Int
    let mode: String
}

struct HealthKitSyncSummary: Equatable, Sendable {
    let syncedAt: Date
    let recordCount: Int
    let deletedCount: Int
    let linkedWorkoutCount: Int
}

struct InsightContext: Equatable, Sendable {
    let reasonCodes: [String]
    let confidence: String
}
