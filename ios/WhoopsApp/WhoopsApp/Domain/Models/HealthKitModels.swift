import Foundation

enum HealthMetric: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case heartRate
    case restingHeartRate
    case hrvSDNN
    case respiratoryRate
    case oxygenSaturation
    case sleepAnalysis
    case workout
    case activeEnergy
    case exerciseTime
    case walkingRunningDistance
    case cyclingDistance
    case vo2Max
    case bodyMass
    case sleepingWristTemperature

    var id: String { rawValue }

    static let summaryMetrics: [HealthMetric] = [
        .restingHeartRate,
        .hrvSDNN,
        .respiratoryRate,
        .oxygenSaturation,
        .sleepAnalysis,
        .activeEnergy,
        .exerciseTime,
        .workout,
    ]

    static let userSelectableMetrics: [HealthMetric] = summaryMetrics

    var displayName: String {
        switch self {
        case .heartRate: "Heart rate"
        case .restingHeartRate: "Resting heart rate"
        case .hrvSDNN: "Apple HRV (SDNN)"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Oxygen saturation"
        case .sleepAnalysis: "Sleep"
        case .workout: "Workout"
        case .activeEnergy: "Active energy"
        case .exerciseTime: "Exercise time"
        case .walkingRunningDistance: "Walking/running distance"
        case .cyclingDistance: "Cycling distance"
        case .vo2Max: "VO₂ max"
        case .bodyMass: "Body mass"
        case .sleepingWristTemperature: "Sleeping wrist temperature"
        }
    }

    var inclusionDescription: String {
        switch self {
        case .restingHeartRate: "Used for readiness and recovery trends."
        case .hrvSDNN: "Kept separate from WHOOP HRV RMSSD."
        case .respiratoryRate: "Used for readiness and recovery trends."
        case .oxygenSaturation: "Used for recovery trends."
        case .sleepAnalysis: "Used only when direct WHOOP sleep is unavailable."
        case .activeEnergy: "Available for daily activity summaries."
        case .exerciseTime: "Available for daily activity summaries."
        case .workout: "Used to link likely duplicate WHOOP workouts."
        case .heartRate, .walkingRunningDistance, .cyclingDistance, .vo2Max, .bodyMass,
            .sleepingWristTemperature:
            "Retained for future source-specific analysis."
        }
    }
}

extension Notification.Name {
    static let healthMetricInclusionDidChange = Notification.Name(
        "whoops.healthMetricInclusionDidChange"
    )
}

enum HealthKitAuthorizationState: String, Equatable, Sendable {
    case unavailable
    case notRequested
    case requested
}

struct HealthSampleSnapshot: Equatable, Sendable {
    let id: UUID
    let metric: HealthMetric
    let startAt: Date
    let endAt: Date
    let value: Double?
    let unit: String?
    let categoryValue: Int?
    let workoutActivityType: UInt?
    let sourceName: String
    let sourceBundleIdentifier: String
    let timeZoneIdentifier: String
    let timeZoneOffsetSeconds: Int
    let localDay: String
}

struct HealthKitChangeBatch: Equatable, Sendable {
    let samples: [HealthSampleSnapshot]
    let deletedSampleIDs: [UUID]
    let anchorData: Data
    let hasMore: Bool
}

struct HealthKitDailySummary: Identifiable, Equatable, Sendable {
    let id: String
    let day: String
    let restingHeartRate: Double?
    let hrvSDNNMilliseconds: Double?
    let respiratoryRate: Double?
    let oxygenSaturationPercent: Double?
    let sleepMinutes: Int?
    let activeEnergyKilocalories: Double?
    let exerciseMinutes: Double?
    let workoutCount: Int
    let sources: [String]
}

struct HealthKitHistorySnapshot: Equatable, Sendable {
    let days: [HealthKitDailySummary]
    let lastSyncAt: Date?
    let recordCount: Int
    let linkedWorkoutCount: Int
}
