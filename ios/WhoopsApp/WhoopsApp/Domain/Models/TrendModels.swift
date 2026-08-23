import Foundation

struct InjuryTimelineItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let bodyRegion: String
    let side: String
    let status: String
    let startedAt: Date
    let updatedAt: Date
}

struct TrendPoint: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let date: Date
    let value: Double
    let source: String
}

struct MetricTrendSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let unit: String
    let source: String
    let points: [TrendPoint]
    let latestValue: Double?
    let baselineMedian: Double?
    let changeFromBaseline: Double?
    let robustDeviation: Double?
    let observationCount: Int

    var hasEnoughData: Bool { observationCount >= 3 }
}

struct DailyTrainingLoad: Codable, Equatable, Identifiable, Sendable {
    let day: String
    let minutes: Double
    let sessionRPE: Int
    let load: Double

    var id: String { day }
}

struct StrengthVolumeSummary: Codable, Equatable, Identifiable, Sendable {
    let movement: String
    let unit: String
    let volume: Double
    let entryCount: Int

    var id: String { "\(movement.lowercased())|\(unit.lowercased())" }
}

struct PainByMovementSummary: Codable, Equatable, Identifiable, Sendable {
    let movement: String
    let observationCount: Int
    let averagePain: Double
    let maximumPain: Int
    let latestAt: Date

    var id: String { movement.lowercased() }
}

struct WeeklyReview: Codable, Equatable, Sendable {
    let version: String
    let periodStart: Date
    let periodEnd: Date
    let importantChange: String
    let plausibleExplanation: String
    let nextAction: String
    let caveat: String
    let currentWorkoutCount: Int
    let priorWorkoutCount: Int
    let physiologyObservationCount: Int
    let checkInCount: Int
}

struct TrendsInput: Equatable, Sendable {
    let generatedAt: Date
    let whoop: WhoopHistorySnapshot
    let healthKit: HealthKitHistorySnapshot
    let workouts: [CompletedWorkout]
    let plans: [WorkoutPlan]
    let checkIns: [MorningCheckIn]
    let assessments: [ReadinessAssessment]
    let restrictions: [RestrictionProfile]
    let injuries: [InjuryTimelineItem]
}

struct TrendsSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let recoveryMetrics: [MetricTrendSummary]
    let sleep: MetricTrendSummary
    let dailyTrainingLoads: [DailyTrainingLoad]
    let currentTrainingLoad: Double
    let priorTrainingLoad: Double
    let strengthVolumes: [StrengthVolumeSummary]
    let painByMovement: [PainByMovementSummary]
    let injuries: [InjuryTimelineItem]
    let weeklyReview: WeeklyReview
}

struct TrendsExportFiles: Equatable, Sendable {
    let jsonURL: URL
    let csvURL: URL
}
