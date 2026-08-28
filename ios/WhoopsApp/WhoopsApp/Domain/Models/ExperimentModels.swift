import Foundation

enum ExperimentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft
    case active
    case completed
    case archived

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ExperimentCondition: String, Codable, CaseIterable, Identifiable, Sendable {
    case intervention
    case comparison

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum ExperimentOutcomeTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case sameDay
    case followingDay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sameDay: "Same day"
        case .followingDay: "Following day"
        }
    }

    var explanation: String {
        switch self {
        case .sameDay:
            "Use the outcome recorded on the condition day."
        case .followingDay:
            "Use the outcome recorded on the next local calendar day."
        }
    }
}

enum ExperimentOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case whoopRecovery
    case whoopRestingHeartRate
    case whoopHRVRMSSD
    case sleepDuration
    case appleHRVSDNN
    case respiratoryRate
    case oxygenSaturation
    case trainingLoad
    case morningPainWithMovement

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whoopRecovery: "WHOOP Recovery"
        case .whoopRestingHeartRate: "WHOOP resting heart rate"
        case .whoopHRVRMSSD: "WHOOP HRV RMSSD"
        case .sleepDuration: "Sleep duration"
        case .appleHRVSDNN: "Apple HRV SDNN"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Oxygen saturation"
        case .trainingLoad: "Completed-workout session load"
        case .morningPainWithMovement: "Morning pain with movement"
        }
    }

    var unit: String {
        switch self {
        case .whoopRecovery, .oxygenSaturation: "%"
        case .whoopRestingHeartRate: "bpm"
        case .whoopHRVRMSSD, .appleHRVSDNN: "ms"
        case .sleepDuration: "min"
        case .respiratoryRate: "breaths/min"
        case .trainingLoad: "minutes × RPE"
        case .morningPainWithMovement: "/10"
        }
    }

    var trendMetricID: String? {
        switch self {
        case .whoopRecovery: "whoop-recovery"
        case .whoopRestingHeartRate: "whoop-resting-heart-rate"
        case .whoopHRVRMSSD: "whoop-hrv-rmssd"
        case .appleHRVSDNN: "apple-hrv-sdnn"
        case .respiratoryRate: "apple-respiratory-rate"
        case .oxygenSaturation: "apple-oxygen-saturation"
        case .sleepDuration, .trainingLoad, .morningPainWithMovement: nil
        }
    }

    var recommendedTiming: ExperimentOutcomeTiming {
        switch self {
        case .trainingLoad: .sameDay
        case .whoopRecovery, .whoopRestingHeartRate, .whoopHRVRMSSD, .sleepDuration,
            .appleHRVSDNN, .respiratoryRate, .oxygenSaturation, .morningPainWithMovement:
            .followingDay
        }
    }

    var dataSourceExplanation: String {
        switch self {
        case .whoopRecovery, .whoopRestingHeartRate:
            "This outcome requires a direct WHOOP connection and matching WHOOP history."
        case .whoopHRVRMSSD:
            "WHOOP HRV RMSSD requires a direct WHOOP connection. WHOOP does not export RMSSD to Apple Health; Apple Health HRV uses SDNN."
        case .sleepDuration:
            "Uses WHOOP sleep when available, with Apple Health sleep as the fallback."
        case .appleHRVSDNN, .respiratoryRate, .oxygenSaturation:
            "Uses the matching daily value from Apple Health."
        case .trainingLoad:
            "Uses completed workouts that have both duration and session RPE."
        case .morningPainWithMovement:
            "Uses the pain-with-movement value from the morning check-in."
        }
    }

    var missingOutcomeExplanation: String {
        switch self {
        case .whoopRecovery, .whoopRestingHeartRate, .whoopHRVRMSSD:
            dataSourceExplanation
        case .sleepDuration:
            "No WHOOP or Apple Health sleep value was found for the selected outcome day."
        case .appleHRVSDNN, .respiratoryRate, .oxygenSaturation:
            "No matching Apple Health value was found for the selected outcome day."
        case .trainingLoad:
            "No completed workout with duration and session RPE was found for the selected outcome day."
        case .morningPainWithMovement:
            "No morning check-in was found for the selected outcome day."
        }
    }
}

struct ExperimentDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var question: String
    var hypothesis: String
    var intervention: String
    var comparisonCondition: String
    var primaryOutcome: ExperimentOutcome
    var outcomeTiming: ExperimentOutcomeTiming
    var secondaryOutcomes: [ExperimentOutcome]
    var inclusionCriteria: [String]
    var exclusionCriteria: [String]
    var minimumObservations: Int
    var potentialConfounders: [String]
    var analysisMethod: String
    var startDate: Date
    var endDate: Date?
    var status: ExperimentStatus
    var analysisVersion: String
    var createdAt: Date
    var updatedAt: Date

    static func draft(now: Date = .now) -> ExperimentDefinition {
        ExperimentDefinition(
            id: UUID().uuidString,
            title: "",
            question: "",
            hypothesis: "",
            intervention: "",
            comparisonCondition: "",
            primaryOutcome: .sleepDuration,
            outcomeTiming: ExperimentOutcome.sleepDuration.recommendedTiming,
            secondaryOutcomes: [],
            inclusionCriteria: [],
            exclusionCriteria: [],
            minimumObservations: 7,
            potentialConfounders: [],
            analysisMethod: "Difference in arithmetic means",
            startDate: now,
            endDate: nil,
            status: .active,
            analysisVersion: DeterministicExperimentEngine.version,
            createdAt: now,
            updatedAt: now
        )
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !intervention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !comparisonCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && minimumObservations >= 2
            && endDate.map { $0 >= startDate } ?? true
    }

    func conditionLabel(for condition: ExperimentCondition) -> String {
        switch condition {
        case .intervention: intervention
        case .comparison: comparisonCondition
        }
    }
}

struct ExperimentObservation: Codable, Equatable, Identifiable, Sendable {
    var id: String
    let experimentID: String
    var day: String
    var condition: ExperimentCondition
    var included: Bool
    var exclusionReason: String
    var confounders: [String]
    var notes: String
    var updatedAt: Date

    static func new(
        experimentID: String,
        day: String,
        now: Date = .now
    ) -> ExperimentObservation {
        ExperimentObservation(
            id: stableID(experimentID: experimentID, day: day),
            experimentID: experimentID,
            day: day,
            condition: .intervention,
            included: true,
            exclusionReason: "",
            confounders: [],
            notes: "",
            updatedAt: now
        )
    }

    static func stableID(experimentID: String, day: String) -> String {
        "\(experimentID)|\(day)"
    }
}

struct ExperimentResolvedObservation: Equatable, Identifiable, Sendable {
    let observation: ExperimentObservation
    let outcomeDay: String
    let outcomeValue: Double?

    var id: String { observation.id }
}

enum ExperimentEvidenceStatus: String, Equatable, Sendable {
    case insufficientData = "Insufficient data"
    case exploratory = "Exploratory"
    case imbalanced = "More observations recommended"
}

struct ExperimentAnalysis: Equatable, Sendable {
    let version: String
    let outcome: ExperimentOutcome
    let observations: [ExperimentResolvedObservation]
    let interventionLoggedCount: Int
    let comparisonLoggedCount: Int
    let interventionCount: Int
    let comparisonCount: Int
    let missingOutcomeCount: Int
    let interventionMean: Double?
    let comparisonMean: Double?
    let observedDifference: Double?
    let evidenceStatus: ExperimentEvidenceStatus
    let summary: String
    let caveat: String
}

struct ExperimentAnalysisInput: Equatable, Sendable {
    let trends: TrendsSnapshot
    let checkIns: [MorningCheckIn]
}

enum ExperimentValidationError: LocalizedError {
    case invalidDefinition
    case invalidObservation

    var errorDescription: String? {
        switch self {
        case .invalidDefinition:
            "Complete the title, question, intervention, comparison, dates, and minimum observations."
        case .invalidObservation:
            "An excluded observation needs a reason."
        }
    }
}
