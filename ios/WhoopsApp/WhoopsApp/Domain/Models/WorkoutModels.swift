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
    var estimatedDurationMinimumMinutes: Int?
    var estimatedDurationMaximumMinutes: Int?

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
    var durationSeconds: Int?
    var tempo: String?
    var notes: String
}

struct WorkoutSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var sequence: Int
    var type: WorkoutSegmentType
    var rounds: Int?
    var durationSeconds: Int?
    var restSeconds: Int?
    var notes: String
    var movements: [MovementPrescription]

    var hasValidStructure: Bool {
        guard sequence > 0 else { return false }
        if type == .rest {
            return durationSeconds.map { $0 > 0 } == true
                && rounds == nil
                && restSeconds == nil
                && movements.isEmpty
        }
        let values = [rounds, durationSeconds, restSeconds].compactMap { $0 }
        return !movements.isEmpty && values.allSatisfy { $0 > 0 }
    }
}

struct ParsedWorkout: Codable, Equatable, Sendable {
    var title: String
    let rawText: String
    var format: WorkoutFormat
    var timeCapSeconds: Int?
    var intendedStimulus: WorkoutStimulus
    var segments: [WorkoutSegment]
    var ambiguities: [WorkoutAmbiguity]
    var parserConfidence: Double
    let parserVersion: String
    let modelVersion: String?

    func validated(catalog: MovementCatalog = .standard) throws -> ParsedWorkout {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkoutValidationError.emptyRawText
        }
        guard (0...1).contains(parserConfidence) else {
            throw WorkoutValidationError.invalidConfidence
        }
        guard !segments.isEmpty else { throw WorkoutValidationError.missingSegments }
        let knownMovementIDs = Set(catalog.items.map(\.id))
        for segment in segments {
            guard segment.hasValidStructure else {
                throw WorkoutValidationError.invalidSegment
            }
            for movement in segment.movements {
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
                    movement.durationSeconds,
                ].compactMap { $0 }
                guard integers.allSatisfy({ $0 > 0 }) else {
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
    var timeCapSeconds: Int?
    var parserVersion: String
    var modelVersion: String?
    var confidence: Double
    var ambiguities: [WorkoutAmbiguity]
    var segments: [WorkoutSegment]

    init(
        id: String,
        title: String,
        rawText: String,
        parsedAt: Date,
        scheduledAt: Date,
        status: WorkoutPlanStatus,
        format: WorkoutFormat,
        intendedStimulus: WorkoutStimulus,
        timeCapSeconds: Int?,
        parserVersion: String,
        modelVersion: String?,
        confidence: Double,
        ambiguities: [WorkoutAmbiguity],
        segments: [WorkoutSegment]
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
    var actualLoadValue: Double?
    var actualLoadUnit: String?
    var actualDurationSeconds: Int?
    var modification: String
    var painDuring: Int
    var notes: String
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
}

enum WorkoutValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyRawText
    case invalidConfidence
    case missingSegments
    case invalidSegment
    case invalidMovement
    case unknownMovement(String)

    var errorDescription: String? {
        switch self {
        case .emptyRawText: "Enter a workout before parsing."
        case .invalidConfidence: "Parser confidence must be between zero and one."
        case .missingSegments: "The parser returned no workout segments."
        case .invalidSegment: "The parser returned an invalid workout segment."
        case .invalidMovement: "The parser returned an invalid movement prescription."
        case .unknownMovement(let id): "The parser returned an unknown movement: \(id)."
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
            "back_squat", "Back squat", [], "squat",
            [.kneeDominant, .hipDominant, .spinalCompression], ["goblet_squat", "sled_push"]),
        item(
            "front_squat", "Front squat", [], "squat",
            [.kneeDominant, .hipDominant, .spinalCompression], ["goblet_squat", "sled_push"]),
        item(
            "goblet_squat", "Goblet squat", [], "squat", [.kneeDominant, .hipDominant],
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
