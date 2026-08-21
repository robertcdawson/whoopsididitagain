import Foundation

enum RestrictionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case monitor
    case limit
    case avoid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monitor: "Monitor"
        case .limit: "Limit"
        case .avoid: "Avoid"
        }
    }

    var isHard: Bool { self == .avoid }
}

struct RestrictionProfile: Identifiable, Equatable, Sendable {
    let id: String
    var injuryName: String
    var bodyRegion: String
    var side: String
    var movementTag: String
    var level: RestrictionLevel
    var painThreshold: Int
    var rationale: String
    var isActive: Bool
}

struct MorningCheckIn: Equatable, Sendable {
    let day: String
    var timestamp: Date
    var painAtRest: Int
    var painWithMovement: Int
    var stiffness: Bool
    var swelling: Bool
    var perceivedWeakness: Bool
    var energy: Int
    var motivation: Int
    var illnessSymptoms: Bool
    var notes: String

    static func empty(day: String, timestamp: Date = .now) -> MorningCheckIn {
        MorningCheckIn(
            day: day,
            timestamp: timestamp,
            painAtRest: 0,
            painWithMovement: 0,
            stiffness: false,
            swelling: false,
            perceivedWeakness: false,
            energy: 3,
            motivation: 3,
            illnessSymptoms: false,
            notes: ""
        )
    }
}

struct SleepScheduleSettings: Equatable, Sendable {
    var wakeHour: Int
    var wakeMinute: Int
    var targetSleepMinutes: Int
    var sleepLatencyMinutes: Int
    var windDownMinutes: Int

    static let standard = SleepScheduleSettings(
        wakeHour: 7,
        wakeMinute: 15,
        targetSleepMinutes: 8 * 60,
        sleepLatencyMinutes: 20,
        windDownMinutes: 45
    )
}

struct SleepDeadline: Equatable, Sendable {
    let wakeAt: Date
    let lightsOutAt: Date
    let windDownAt: Date
}

struct BaselineStatistic: Equatable, Sendable {
    let median: Double
    let medianAbsoluteDeviation: Double
    let observationCount: Int

    func robustDeviation(of value: Double) -> Double? {
        guard medianAbsoluteDeviation > 0 else {
            return value == median ? 0 : nil
        }
        return (value - median) / (1.4826 * medianAbsoluteDeviation)
    }
}

struct PhysiologyReadinessInput: Equatable, Sendable {
    let whoopRecovery: Int?
    let whoopHRVRMSSD: Double?
    let whoopHRVHistory: [Double]
    let appleHRVSDNN: Double?
    let appleHRVHistory: [Double]
    let restingHeartRate: Double?
    let restingHeartRateHistory: [Double]
    let sleepMinutes: Int?
}

struct ReadinessInput: Equatable, Sendable {
    let date: Date
    let day: String
    let physiology: PhysiologyReadinessInput
    let checkIn: MorningCheckIn?
    let activeRestrictions: [RestrictionProfile]
    let sleepSettings: SleepScheduleSettings
}

struct ReadinessReason: Codable, Equatable, Identifiable, Sendable {
    enum Direction: String, Codable, Sendable {
        case positive
        case caution
        case restriction
        case missing
    }

    let code: String
    let message: String
    let direction: Direction
    let priority: Int

    var id: String { code }
}

struct ReadinessAssessment: Equatable, Sendable {
    enum Recommendation: String, Codable, CaseIterable, Identifiable, Sendable {
        case proceed
        case proceedWithLimits
        case modify
        case recoveryFocused

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .proceed: "Proceed"
            case .proceedWithLimits: "Proceed with limits"
            case .modify: "Modify"
            case .recoveryFocused: "Recovery-focused day"
            }
        }

        var symbolName: String {
            switch self {
            case .proceed: "checkmark.circle.fill"
            case .proceedWithLimits: "gauge.with.dots.needle.50percent"
            case .modify: "slider.horizontal.3"
            case .recoveryFocused: "bed.double.fill"
            }
        }
    }

    enum Confidence: String, Codable, Sendable {
        case low
        case moderate
        case high

        var displayName: String { rawValue.capitalized }
    }

    let id: String
    let day: String
    let computedAt: Date
    let systemicScore: Int?
    let sleepScore: Int?
    let tissueScore: Int?
    let recommendation: Recommendation
    let confidence: Confidence
    let reasons: [ReadinessReason]
    let rulesetVersion: String
    var userOverride: Recommendation?
    var overrideNote: String?

    var effectiveRecommendation: Recommendation {
        userOverride ?? recommendation
    }

    var reasonCodes: [String] { reasons.map(\.code) }
}

enum RobustBaseline {
    static func calculate(_ values: [Double], maximumCount: Int = 28) -> BaselineStatistic? {
        let values = Array(values.suffix(maximumCount)).filter(\.isFinite).sorted()
        guard !values.isEmpty else { return nil }
        let medianValue = median(values)
        let deviations = values.map { abs($0 - medianValue) }.sorted()
        return BaselineStatistic(
            median: medianValue,
            medianAbsoluteDeviation: median(deviations),
            observationCount: values.count
        )
    }

    private static func median(_ sortedValues: [Double]) -> Double {
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}

enum SleepDeadlineCalculator {
    static func calculate(
        now: Date,
        settings: SleepScheduleSettings,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepDeadline {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = settings.wakeHour
        components.minute = settings.wakeMinute
        components.second = 0
        var wakeAt = calendar.date(from: components) ?? now
        if wakeAt <= now {
            wakeAt = calendar.date(byAdding: .day, value: 1, to: wakeAt) ?? wakeAt
        }
        let lightsOutAt =
            calendar.date(
                byAdding: .minute,
                value: -(settings.targetSleepMinutes + settings.sleepLatencyMinutes),
                to: wakeAt
            ) ?? wakeAt
        let windDownAt =
            calendar.date(
                byAdding: .minute,
                value: -settings.windDownMinutes,
                to: lightsOutAt
            ) ?? lightsOutAt
        return SleepDeadline(wakeAt: wakeAt, lightsOutAt: lightsOutAt, windDownAt: windDownAt)
    }
}
