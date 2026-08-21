import Foundation

enum MovementCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case weightlifting
    case strength
    case gymnastics
    case machine
    case running
    case jumping
    case carry
    case oddObject = "odd_object"
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightlifting: "Weightlifting"
        case .strength: "Power & Strength"
        case .gymnastics: "Gymnastics"
        case .machine: "Machine"
        case .running: "Running"
        case .jumping: "Jumping"
        case .carry: "Carry"
        case .oddObject: "Odd Object"
        case .mixed: "CrossFit / Mixed"
        }
    }
}

enum MovementMeasurement: String, Codable, CaseIterable, Identifiable, Sendable {
    case repetitions
    case load
    case distance
    case calories
    case duration
    case percentageOneRepMax = "percentage_1rm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .repetitions: "Repetitions"
        case .load: "Load"
        case .distance: "Distance"
        case .calories: "Calories"
        case .duration: "Duration"
        case .percentageOneRepMax: "Percentage of 1RM"
        }
    }
}

enum MovementOrigin: String, Codable, Sendable {
    case builtIn = "built_in"
    case custom
    case wodLab = "wod_lab"
}

struct MovementDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var canonicalName: String
    var aliases: [String]
    var category: MovementCategory
    var movementFamily: String
    var equipment: [String]
    var supportedMeasurements: Set<MovementMeasurement>
    var preferredUnit: String?
    var demandTags: Set<MovementDemand>
    var substitutionCandidateIDs: [String]
    var origin: MovementOrigin
    var sourceIdentifier: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var catalogItem: MovementCatalogItem {
        MovementCatalogItem(
            id: id,
            canonicalName: canonicalName,
            aliases: aliases,
            movementFamily: movementFamily,
            tags: demandTags,
            substitutionCandidates: substitutionCandidateIDs
        )
    }

    static func custom(
        name: String,
        aliases: [String] = [],
        category: MovementCategory = .mixed,
        equipment: [String] = [],
        supportedMeasurements: Set<MovementMeasurement> = [.repetitions],
        preferredUnit: String? = nil,
        now: Date = .now
    ) -> MovementDefinition {
        MovementDefinition(
            id: UUID().uuidString.lowercased(),
            canonicalName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: aliases,
            category: category,
            movementFamily: category.rawValue,
            equipment: equipment,
            supportedMeasurements: supportedMeasurements,
            preferredUnit: preferredUnit,
            demandTags: [],
            substitutionCandidateIDs: [],
            origin: .custom,
            sourceIdentifier: nil,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
    }

    static let bundled: [MovementDefinition] = MovementCatalog.standard.items.map { item in
        let category = category(for: item)
        return MovementDefinition(
            id: item.id,
            canonicalName: item.canonicalName,
            aliases: item.aliases,
            category: category,
            movementFamily: item.movementFamily,
            equipment: equipment(for: item),
            supportedMeasurements: measurements(for: item, category: category),
            preferredUnit: preferredUnit(for: item, category: category),
            demandTags: item.tags,
            substitutionCandidateIDs: item.substitutionCandidates,
            origin: .builtIn,
            sourceIdentifier: nil,
            isArchived: false,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private static func category(for item: MovementCatalogItem) -> MovementCategory {
        switch item.id {
        case "row", "air_bike": .machine
        case "run": .running
        case "box_jump", "double_under": .jumping
        case "clean", "snatch": .weightlifting
        case "pull_up", "kipping_pull_up", "push_up", "burpee", "ring_row": .gymnastics
        case "sled_push": .carry
        default: .strength
        }
    }

    private static func equipment(for item: MovementCatalogItem) -> [String] {
        switch item.id {
        case "row": ["Rower"]
        case "air_bike": ["Air bike"]
        case "double_under": ["Jump rope"]
        case "pull_up", "kipping_pull_up": ["Pull-up bar"]
        case "ring_row": ["Rings"]
        case "box_jump": ["Box"]
        case "sled_push": ["Sled"]
        case "goblet_squat": ["Dumbbell", "Kettlebell"]
        case "wall_ball": ["Medicine ball"]
        case "push_up", "burpee", "run": []
        default: ["Barbell"]
        }
    }

    private static func measurements(
        for item: MovementCatalogItem,
        category: MovementCategory
    ) -> Set<MovementMeasurement> {
        switch item.id {
        case "row", "run", "air_bike": [.distance, .calories, .duration]
        case "sled_push": [.distance, .load, .duration]
        case "double_under", "box_jump", "burpee", "push_up", "pull_up", "kipping_pull_up",
            "ring_row", "wall_ball":
            [.repetitions, .duration]
        default: [.repetitions, .load, .percentageOneRepMax]
        }
    }

    private static func preferredUnit(
        for item: MovementCatalogItem,
        category: MovementCategory
    ) -> String? {
        switch item.id {
        case "row", "run", "sled_push": "m"
        case "air_bike": "cal"
        default: category == .strength || category == .weightlifting ? "lb" : nil
        }
    }
}

struct MovementUsageSummary: Equatable, Identifiable, Sendable {
    let movement: MovementDefinition
    let appearanceCount: Int
    let lastUsedAt: Date?

    var id: String { movement.id }
}

struct MovementLibraryImportPreview: Equatable, Sendable {
    let data: Data
    let additions: [MovementDefinition]
    let matchedCount: Int
    let skippedCount: Int
    let issues: [String]

    var canImport: Bool { !additions.isEmpty }
}

struct MovementLibraryImportResult: Equatable, Sendable {
    let addedCount: Int
    let matchedCount: Int
    let skippedCount: Int
    let issues: [String]
}
