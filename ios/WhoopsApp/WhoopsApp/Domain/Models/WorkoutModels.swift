import Foundation

enum WorkoutFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case forTime = "for_time"
    case amrap
    case emom
    case rounds
    case strength
    case intervals
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forTime: "For time"
        case .amrap: "AMRAP"
        case .emom: "EMOM"
        case .rounds: "Rounds"
        case .strength: "Strength"
        case .intervals: "Intervals"
        case .manual: "Manual"
        }
    }
}

enum WorkoutPlanStatus: String, Codable, Sendable {
    case draft
    case planned
    case completed
}

enum WorkoutSegmentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case rest
    case warmup
    case cooldown

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum MovementDemand: String, Codable, CaseIterable, Identifiable, Sendable {
    case elbowExtension = "elbow_extension"
    case ballisticElbowExtension = "ballistic_elbow_extension"
    case overhead
    case horizontalPress = "horizontal_press"
    case verticalPull = "vertical_pull"
    case kipping
    case gripIntensive = "grip_intensive"
    case spinalCompression = "spinal_compression"
    case spinalFlexionRisk = "spinal_flexion_risk"
    case kneeDominant = "knee_dominant"
    case hipDominant = "hip_dominant"
    case highImpact = "high_impact"
    case footImpact = "foot_impact"
    case eccentricDominant = "eccentric_dominant"
    case isometric
    case aerobic
    case anaerobic
    case skillDependent = "skill_dependent"

    var id: String { rawValue }
    var displayName: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

struct MovementCatalogItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let canonicalName: String
    let aliases: [String]
    let movementFamily: String
    let tags: Set<MovementDemand>
    let substitutionCandidates: [String]
}

struct WorkoutStimulus: Codable, Equatable, Sendable {
    var primary: String
    var secondary: [String]
    var estimatedDurationMinimumMinutes: Double?
    var estimatedDurationMaximumMinutes: Double?

    var hasValidDurationRange: Bool {
        guard
            [estimatedDurationMinimumMinutes, estimatedDurationMaximumMinutes]
                .compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 })
        else { return false }
        if let minimum = estimatedDurationMinimumMinutes,
            let maximum = estimatedDurationMaximumMinutes
        {
            return minimum <= maximum
        }
        return true
    }

    static let unknown = WorkoutStimulus(
        primary: "Needs review",
        secondary: [],
        estimatedDurationMinimumMinutes: nil,
        estimatedDurationMaximumMinutes: nil
    )
}

struct WorkoutAmbiguity: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let line: Int?
    let originalText: String
    let message: String
}

struct MovementPrescription: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var canonicalMovementID: String?
    var displayName: String
    var originalText: String
    var repetitions: Int?
    var distanceMeters: Int?
    var calories: Int?
    var loadValue: Double?
    var loadUnit: String?
    var percentageOfOneRepMax: Double?
    var durationSeconds: Double?
    var tempo: String?
    var notes: String

    func duplicated() -> MovementPrescription {
        var copy = self
        copy.id = UUID().uuidString.lowercased()
        return copy
    }

    var hasValidQuantities: Bool {
        [repetitions, distanceMeters, calories].compactMap { $0 }.allSatisfy { $0 > 0 }
            && [loadValue, durationSeconds].compactMap { $0 }.allSatisfy { $0.isFinite && $0 > 0 }
            && (percentageOfOneRepMax.map { $0.isFinite && $0 > 0 && $0 <= 100 } ?? true)
    }
}

struct WorkoutSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var sequence: Int
    var type: WorkoutSegmentType
    var rounds: Int?
    var durationSeconds: Double?
    var restSeconds: Double?
    var notes: String
    var movements: [MovementPrescription]

    var hasValidStructure: Bool {
        guard sequence > 0 else { return false }
        if type == .rest {
            return durationSeconds.map { $0.isFinite && $0 > 0 } == true
                && rounds == nil
                && restSeconds == nil
                && movements.isEmpty
        }
        let values = [durationSeconds, restSeconds].compactMap { $0 }
        return !movements.isEmpty && (rounds == nil || rounds! > 0)
            && values.allSatisfy { $0.isFinite && $0 > 0 }
    }
}

struct ParsedWorkout: Codable, Equatable, Sendable {
    var title: String
    let rawText: String
    var format: WorkoutFormat
    var timeCapSeconds: Double?
    var intendedStimulus: WorkoutStimulus
    var segments: [WorkoutSegment]
    var ambiguities: [WorkoutAmbiguity]
    var parserConfidence: Double
    let parserVersion: String
    let modelVersion: String?
    var reportedResult: WorkoutReportedResult? = nil

    func validated(catalog: MovementCatalog = .standard) throws -> ParsedWorkout {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkoutValidationError.emptyRawText
        }
        guard (0...1).contains(parserConfidence) else {
            throw WorkoutValidationError.invalidConfidence
        }
        guard timeCapSeconds.map({ $0.isFinite && $0 > 0 }) ?? true,
            reportedResult?.isValid ?? true
        else { throw WorkoutValidationError.invalidSegment }
        guard !segments.isEmpty else { throw WorkoutValidationError.missingSegments }
        let knownMovementIDs = Set(catalog.items.map(\.id))
        for segment in segments {
            guard segment.hasValidStructure else {
                throw WorkoutValidationError.invalidSegment
            }
            for movement in segment.movements {
                guard movement.hasValidQuantities else {
                    throw WorkoutValidationError.invalidMovement
                }
                guard !movement.displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw WorkoutValidationError.invalidMovement
                }
                if let canonicalID = movement.canonicalMovementID,
                    !knownMovementIDs.contains(canonicalID)
                {
                    throw WorkoutValidationError.unknownMovement(canonicalID)
                }
                let integers = [
                    movement.repetitions, movement.distanceMeters, movement.calories,
                ].compactMap { $0 }
                guard integers.allSatisfy({ $0 > 0 }) else {
                    throw WorkoutValidationError.invalidMovement
                }
                if let duration = movement.durationSeconds, !duration.isFinite || duration <= 0 {
                    throw WorkoutValidationError.invalidMovement
                }
                if let load = movement.loadValue, load <= 0 {
                    throw WorkoutValidationError.invalidMovement
                }
            }
        }
        return self
    }
}

struct WorkoutPlan: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var rawText: String
    var parsedAt: Date
    var scheduledAt: Date
    var status: WorkoutPlanStatus
    var format: WorkoutFormat
    var intendedStimulus: WorkoutStimulus
    var timeCapSeconds: Double?
    var parserVersion: String
    var modelVersion: String?
    var confidence: Double
    var ambiguities: [WorkoutAmbiguity]
    var segments: [WorkoutSegment]
    var reportedResult: WorkoutReportedResult?
    // User corrections belong to the reviewed plan, never to parser-generated prescriptions.
    var reportedRepetitionOverrides: [String: Int]

    init(
        id: String,
        title: String,
        rawText: String,
        parsedAt: Date,
        scheduledAt: Date,
        status: WorkoutPlanStatus,
        format: WorkoutFormat,
        intendedStimulus: WorkoutStimulus,
        timeCapSeconds: Double?,
        parserVersion: String,
        modelVersion: String?,
        confidence: Double,
        ambiguities: [WorkoutAmbiguity],
        segments: [WorkoutSegment],
        reportedResult: WorkoutReportedResult? = nil,
        reportedRepetitionOverrides: [String: Int] = [:]
    ) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.parsedAt = parsedAt
        self.scheduledAt = scheduledAt
        self.status = status
        self.format = format
        self.intendedStimulus = intendedStimulus
        self.timeCapSeconds = timeCapSeconds
        self.parserVersion = parserVersion
        self.modelVersion = modelVersion
        self.confidence = confidence
        self.ambiguities = ambiguities
        self.segments = segments
        self.reportedResult = reportedResult
        self.reportedRepetitionOverrides = reportedRepetitionOverrides
    }

    init(parsed: ParsedWorkout, id: String = UUID().uuidString.lowercased(), now: Date = .now) {
        self.id = id
        title = parsed.title
        rawText = parsed.rawText
        parsedAt = now
        scheduledAt = now
        status = .draft
        format = parsed.format
        intendedStimulus = parsed.intendedStimulus
        timeCapSeconds = parsed.timeCapSeconds
        parserVersion = parsed.parserVersion
        modelVersion = parsed.modelVersion
        confidence = parsed.parserConfidence
        ambiguities = parsed.ambiguities
        segments = parsed.segments
        reportedResult = parsed.reportedResult
        reportedRepetitionOverrides = [:]
    }

    var movements: [MovementPrescription] { segments.flatMap(\.movements) }
}

enum WorkoutConflictSeverity: String, Codable, Sendable {
    case caution
    case hard
}

struct WorkoutConflict: Equatable, Identifiable, Sendable {
    let id: String
    let movementID: String
    let restrictionID: String
    let severity: WorkoutConflictSeverity
    let explanation: String
    let preservedStimulus: String
    let compromise: String
    let substitutionCandidates: [MovementCatalogItem]
}

struct WorkoutEvaluation: Equatable, Sendable {
    let recommendation: ReadinessAssessment.Recommendation
    let conflicts: [WorkoutConflict]
    let reasonCodes: [String]
}

struct CompletedMovement: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var canonicalMovementID: String?
    var plannedPrescriptionID: String?
    var displayName: String
    var actualRepetitions: Int?
    var actualDistanceMeters: Int?
    var actualCalories: Int?
    var actualLoadValue: Double?
    var actualLoadUnit: String?
    var actualDurationSeconds: Double?
    var modification: String
    var painDuring: Int
    var notes: String

    func duplicated() -> CompletedMovement {
        var copy = self
        copy.id = UUID().uuidString.lowercased()
        return copy
    }

    var hasValidValues: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (0...10).contains(painDuring)
            && [actualRepetitions, actualDistanceMeters, actualCalories]
                .compactMap { $0 }.allSatisfy { $0 >= 0 }
            && [actualLoadValue, actualDurationSeconds]
                .compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

struct CompletedWorkout: Equatable, Identifiable, Sendable {
    let id: String
    let plannedWorkoutID: String?
    var title: String
    var startedAt: Date
    var endedAt: Date
    var sessionRPE: Int
    var postSessionPain: Int
    var notes: String
    var movements: [CompletedMovement]
    var reportedResult: WorkoutReportedResult? = nil
}

extension CompletedWorkout {
    var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }

    /// Moving a session preserves elapsed time, including fractional seconds and midnight crossings.
    mutating func reschedule(startingAt date: Date) {
        let duration = max(0, durationSeconds)
        startedAt = date
        endedAt = date.addingTimeInterval(duration)
    }

    mutating func setDuration(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        endedAt = startedAt.addingTimeInterval(seconds)
    }

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a workout title."
        }
        if !startedAt.timeIntervalSinceReferenceDate.isFinite
            || !endedAt.timeIntervalSinceReferenceDate.isFinite || !durationSeconds.isFinite
            || durationSeconds <= 0
        {
            return "The workout must end after it starts."
        }
        if !(1...10).contains(sessionRPE) || !(0...10).contains(postSessionPain) {
            return "Session RPE must be 1–10 and post-session pain must be 0–10."
        }
        if reportedResult?.isValid == false {
            return "Review the completed rounds and additional reps."
        }
        if Set(movements.map(\.id)).count != movements.count
            || !movements.allSatisfy(\.hasValidValues)
        {
            return "Each movement needs a name, nonnegative quantities, and pain from 0–10."
        }
        return nil
    }

    init(plan: WorkoutPlan, now: Date = .now) {
        let totals = plan.effectiveReportedRepetitionTotals
        let movements = plan.movements.map { movement in
            CompletedMovement(
                id: UUID().uuidString.lowercased(),
                canonicalMovementID: movement.canonicalMovementID,
                plannedPrescriptionID: movement.id,
                displayName: movement.displayName,
                actualRepetitions: totals[movement.id]
                    ?? (plan.hasReportedRepetitions ? nil : movement.repetitions),
                actualDistanceMeters: plan.hasReportedRepetitions ? nil : movement.distanceMeters,
                actualCalories: plan.hasReportedRepetitions ? nil : movement.calories,
                actualLoadValue: movement.loadValue,
                actualLoadUnit: movement.loadUnit,
                actualDurationSeconds: plan.hasReportedRepetitions ? nil : movement.durationSeconds,
                modification: "",
                painDuring: 0,
                notes: ""
            )
        }
        self.init(
            id: UUID().uuidString.lowercased(),
            plannedWorkoutID: plan.id,
            title: plan.title,
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now,
            sessionRPE: 5,
            postSessionPain: 0,
            notes: "",
            movements: movements,
            reportedResult: plan.reportedResult
        )
    }
}

struct WorkoutReportedResult: Codable, Equatable, Sendable {
    var completedRounds: Int
    var additionalRepetitions: Int

    var isValid: Bool {
        (0...100_000).contains(completedRounds) && (0...100_000).contains(additionalRepetitions)
    }

    var summary: String { "\(completedRounds) rounds + \(additionalRepetitions) reps" }

    static func parse(_ source: String) -> WorkoutReportedResult? {
        let lines = source.precomposedStringWithCompatibilityMapping.components(
            separatedBy: .newlines
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter {
            $0.range(of: #"(?i)^(score|result|completed)\s*:"#, options: .regularExpression) != nil
        }
        // Multiple scores may refer to different segments; never guess which one applies.
        guard lines.count == 1, let line = lines.first,
            let regex = try? NSRegularExpression(
                pattern:
                    #"(?i)^(?:score|result|completed)\s*:\s*(\d+)\s+rounds?(?:\s*(?:,|and|\+)\s*(\d+)\s+(?:reps?|repetitions?))?\s*\.?$"#
            ),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let roundsRange = Range(match.range(at: 1), in: line),
            let rounds = Int(line[roundsRange])
        else { return nil }
        var reps = 0
        if let range = Range(match.range(at: 2), in: line) {
            guard let value = Int(line[range]) else { return nil }
            reps = value
        }
        let result = WorkoutReportedResult(completedRounds: rounds, additionalRepetitions: reps)
        return result.isValid ? result : nil
    }
}

extension WorkoutPlan {
    var hasReportedRepetitions: Bool {
        reportedResult != nil || !reportedRepetitionOverrides.isEmpty
    }

    var hasValidReportedRepetitionOverrides: Bool {
        let movementIDs = Set(movements.map(\.id))
        return reportedRepetitionOverrides.allSatisfy {
            movementIDs.contains($0.key) && (0...100_000).contains($0.value)
        }
    }

    /// Corrected counts take precedence without changing the score or per-round prescription.
    var effectiveReportedRepetitionTotals: [String: Int] {
        var totals = reportedRepetitionTotals ?? [:]
        for movement in movements {
            if let correction = reportedRepetitionOverrides[movement.id],
                (0...100_000).contains(correction)
            {
                totals[movement.id] = correction
            }
        }
        return totals
    }

    mutating func discardOrphanedReportedRepetitionOverrides() {
        let movementIDs = Set(movements.map(\.id))
        reportedRepetitionOverrides = reportedRepetitionOverrides.filter {
            movementIDs.contains($0.key)
        }
    }

    func visibleNotes(_ notes: String) -> String {
        guard reportedResult != nil else { return notes }
        return notes.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("Reported result (not a prescription):") }
            .joined(separator: "\n")
    }

    /// Extra reps follow the written movement order; mixed-unit or multi-segment scores need review.
    var reportedRepetitionTotals: [String: Int]? {
        guard let result = reportedResult, result.isValid,
            format == .amrap || format == .rounds,
            segments.count == 1, let segment = segments.first, segment.type == .work,
            !segment.movements.isEmpty,
            segment.movements.allSatisfy({
                ($0.repetitions ?? 0) > 0 && $0.distanceMeters == nil && $0.calories == nil
                    && $0.durationSeconds == nil
            })
        else { return nil }
        let counts = segment.movements.compactMap(\.repetitions)
        guard counts.allSatisfy({ $0 <= 100_000 }) else { return nil }
        let perRound = counts.reduce(0, +)
        guard result.additionalRepetitions < perRound else { return nil }
        var remaining = result.additionalRepetitions
        var totals: [String: Int] = [:]
        for movement in segment.movements {
            let reps = movement.repetitions ?? 0
            let extra = min(remaining, reps)
            totals[movement.id] = result.completedRounds * reps + extra
            remaining -= extra
        }
        return totals
    }
}

enum WorkoutDurationInput {
    static func minutesText(seconds: Double, locale: Locale = .current) -> String {
        (seconds / 60).formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
    }

    static func summary(seconds: Double) -> String { "\(minutesText(seconds: seconds)) min" }

    static func accepts(_ text: String, locale: Locale = .current) -> Bool {
        let normalized = text.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        return normalized.range(of: #"^\d{0,4}(?:\.\d{0,2})?$"#, options: .regularExpression) != nil
    }

    static func seconds(_ text: String, locale: Locale = .current) -> Double? {
        guard accepts(text, locale: locale),
            let minutes = Double(
                text.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")),
            minutes.isFinite, (0...1_440).contains(minutes)
        else { return nil }
        return (minutes * 6_000).rounded() / 100
    }

    static func legacySeconds(_ seconds: Double?) -> Int? {
        seconds.flatMap { $0.isFinite && $0 >= 0 && $0 <= 86_400 ? Int($0.rounded()) : nil }
    }
}

enum WorkoutDecimalInput {
    static func text(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...12)))
    }

    static func accepts(_ text: String, locale: Locale = .current) -> Bool {
        let normalized = text.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard normalized.range(of: #"^\d*(?:\.\d*)?$"#, options: .regularExpression) != nil else {
            return false
        }
        return normalized.isEmpty || normalized == "." || number(text, locale: locale) != nil
    }

    static func number(_ text: String, locale: Locale = .current) -> Double? {
        guard
            let value = Double(
                text.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")),
            value.isFinite, value >= 0
        else { return nil }
        return value
    }
}

enum WorkoutLoadUnit: String, CaseIterable, Identifiable {
    case pounds = "lb"
    case kilograms = "kg"
    var id: String { rawValue }
    var displayName: String { self == .pounds ? "lbs" : "kg" }

    static func normalized(_ value: String?) -> WorkoutLoadUnit? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lb", "lbs", "pound", "pounds", "#": .pounds
        case "kg", "kgs", "kilogram", "kilograms": .kilograms
        default: nil
        }
    }
}

enum WorkoutValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyRawText
    case invalidConfidence
    case missingSegments
    case invalidSegment
    case invalidMovement
    case unknownMovement(String)
    case invalidCompletedWorkout(String)

    var errorDescription: String? {
        switch self {
        case .emptyRawText: "Enter a workout before parsing."
        case .invalidConfidence: "Parser confidence must be between zero and one."
        case .missingSegments: "The parser returned no workout segments."
        case .invalidSegment: "The parser returned an invalid workout segment."
        case .invalidMovement: "The parser returned an invalid movement prescription."
        case .unknownMovement(let id): "The parser returned an unknown movement: \(id)."
        case .invalidCompletedWorkout(let message): message
        }
    }
}

struct WorkoutParserPayloadValidator: Sendable {
    private let decoder = JSONDecoder()

    func decode(_ data: Data, catalog: MovementCatalog = .standard) throws -> ParsedWorkout {
        do {
            return try decoder.decode(ParsedWorkout.self, from: data).validated(catalog: catalog)
        } catch let error as WorkoutValidationError {
            throw error
        } catch {
            throw AppError.decoding(error.localizedDescription)
        }
    }
}

struct MovementCatalog: Sendable {
    let items: [MovementCatalogItem]

    func item(id: String) -> MovementCatalogItem? { items.first { $0.id == id } }

    func match(_ text: String) -> MovementCatalogItem? {
        let normalized = Self.normalize(text)
        let padded = " \(normalized) "
        return
            items
            .sorted { lhs, rhs in
                let left =
                    ([lhs.canonicalName] + lhs.aliases).map(Self.normalize).map(\.count).max()
                    ?? 0
                let right =
                    ([rhs.canonicalName] + rhs.aliases).map(Self.normalize).map(\.count).max()
                    ?? 0
                return left > right
            }
            .first { item in
                ([item.canonicalName] + item.aliases).contains { alias in
                    let normalizedAlias = Self.normalize(alias)
                    return !normalizedAlias.isEmpty
                        && (normalized == normalizedAlias
                            || padded.contains(" \(normalizedAlias) "))
                }
            }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static let standard = MovementCatalog(items: [
        item(
            "row", "Row", ["rowing", "rower"], "monostructural",
            [.aerobic, .hipDominant, .gripIntensive], ["air_bike", "run"]),
        item(
            "run", "Run", ["running"], "monostructural", [.aerobic, .highImpact, .footImpact],
            ["air_bike", "row"]),
        item(
            "air_bike", "Air bike", ["bike", "assault bike", "echo bike"], "monostructural",
            [.aerobic, .kneeDominant], ["row"]),
        item(
            "strict_press", "Strict press", ["shoulder press"], "press",
            [.elbowExtension, .overhead], ["landmine_press", "goblet_squat"]),
        item(
            "push_press", "Push press", [], "press",
            [.elbowExtension, .ballisticElbowExtension, .overhead], ["landmine_press", "air_bike"]),
        item(
            "landmine_press", "Landmine press", [], "press", [.elbowExtension],
            ["goblet_squat", "air_bike"]),
        item(
            "bench_press", "Bench press", [], "press", [.elbowExtension, .horizontalPress],
            ["goblet_squat", "air_bike"]),
        item(
            "push_up", "Push-up", ["push up", "pushups", "push ups"], "press",
            [.elbowExtension, .horizontalPress], ["air_bike", "goblet_squat"]),
        item(
            "pull_up", "Pull-up", ["pull up", "pullups", "pull ups"], "pull",
            [.verticalPull, .gripIntensive], ["ring_row", "air_bike"]),
        item(
            "kipping_pull_up", "Kipping pull-up", ["kipping pull up"], "pull",
            [.verticalPull, .gripIntensive, .kipping], ["ring_row", "air_bike"]),
        item("ring_row", "Ring row", [], "pull", [.gripIntensive], ["air_bike"]),
        item(
            "deadlift", "Deadlift", [], "hinge",
            [.hipDominant, .spinalCompression, .gripIntensive], ["sled_push", "air_bike"]),
        item(
            "overhead_kettlebell_swing", "Overhead kettlebell swing",
            [
                "overhead kettlebell swings", "overhead kb swing", "overhead kb swings",
                "american kettlebell swing", "american kettlebell swings",
                "american kb swing", "american kb swings",
            ],
            "hinge", [.hipDominant, .gripIntensive, .overhead, .elbowExtension, .anaerobic],
            ["deadlift", "air_bike"]),
        item(
            "back_squat", "Back squat", [], "squat",
            [.kneeDominant, .hipDominant, .spinalCompression], ["goblet_squat", "sled_push"]),
        item(
            "front_squat", "Front squat", [], "squat",
            [.kneeDominant, .hipDominant, .spinalCompression], ["goblet_squat", "sled_push"]),
        item(
            "goblet_squat", "Goblet squat", ["goblet squats"], "squat",
            [.kneeDominant, .hipDominant],
            ["air_bike", "sled_push"]),
        item(
            "wall_ball", "Wall ball", ["wallball", "wall balls"], "squat",
            [.kneeDominant, .overhead, .ballisticElbowExtension], ["goblet_squat", "air_bike"]),
        item(
            "thruster", "Thruster", ["thrusters"], "squat_press",
            [.kneeDominant, .overhead, .ballisticElbowExtension], ["goblet_squat", "air_bike"]),
        item(
            "burpee", "Burpee", ["burpees"], "bodyweight",
            [.highImpact, .footImpact, .elbowExtension, .anaerobic], ["air_bike", "goblet_squat"]),
        item(
            "box_jump", "Box jump", ["box jumps"], "jump",
            [.highImpact, .footImpact, .kneeDominant], ["sled_push", "air_bike"]),
        item(
            "double_under", "Double-under", ["double under", "double unders", "du", "dus"],
            "jump_rope", [.highImpact, .footImpact, .skillDependent], ["air_bike", "row"]),
        item(
            "clean", "Clean", ["power clean", "squat clean"], "olympic_lift",
            [.hipDominant, .spinalCompression, .skillDependent, .anaerobic],
            ["deadlift", "sled_push"]),
        item(
            "snatch", "Snatch", ["power snatch", "squat snatch"], "olympic_lift",
            [.overhead, .spinalCompression, .skillDependent, .anaerobic], ["clean", "sled_push"]),
        item(
            "sled_push", "Sled push", ["sled"], "loaded_carry",
            [.kneeDominant, .hipDominant, .anaerobic], ["air_bike"]),
    ])

    private static func item(
        _ id: String,
        _ name: String,
        _ aliases: [String],
        _ family: String,
        _ tags: Set<MovementDemand>,
        _ substitutions: [String]
    ) -> MovementCatalogItem {
        MovementCatalogItem(
            id: id,
            canonicalName: name,
            aliases: aliases,
            movementFamily: family,
            tags: tags,
            substitutionCandidates: substitutions
        )
    }
}
