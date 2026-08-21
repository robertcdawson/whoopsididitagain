import Foundation
import SwiftData

@Model
final class MovementDefinitionRecord {
    @Attribute(.unique) var id: String
    var canonicalName: String
    var aliasesData: Data
    var category: String
    var movementFamily: String
    var equipmentData: Data
    var supportedMeasurementsData: Data
    var preferredUnit: String?
    var demandTagsData: Data
    var substitutionCandidateIDsData: Data
    var origin: String
    var sourceIdentifier: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        movement: MovementDefinition,
        encoder: JSONEncoder
    ) throws {
        id = movement.id
        canonicalName = movement.canonicalName
        aliasesData = try encoder.encode(movement.aliases)
        category = movement.category.rawValue
        movementFamily = movement.movementFamily
        equipmentData = try encoder.encode(movement.equipment)
        supportedMeasurementsData = try encoder.encode(movement.supportedMeasurements)
        preferredUnit = movement.preferredUnit
        demandTagsData = try encoder.encode(movement.demandTags)
        substitutionCandidateIDsData = try encoder.encode(movement.substitutionCandidateIDs)
        origin = movement.origin.rawValue
        sourceIdentifier = movement.sourceIdentifier
        isArchived = movement.isArchived
        createdAt = movement.createdAt
        updatedAt = movement.updatedAt
    }
}

enum MovementLibraryError: Error, LocalizedError, Sendable {
    case blankName
    case duplicateName(String)
    case unknownMovement

    var errorDescription: String? {
        switch self {
        case .blankName: "Enter a movement name."
        case .duplicateName(let name): "A movement named \(name) already exists."
        case .unknownMovement: "That movement is no longer in the library."
        }
    }
}

@MainActor
final class MovementLibraryPersistence: MovementLibraryRepository, @unchecked Sendable {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let importer = WODLabMovementImporter()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func prepareDefaults() async throws {
        let records = try context.fetch(FetchDescriptor<MovementDefinitionRecord>())
        var inserted = false
        for bundled in MovementDefinition.bundled
        where !records.contains(where: { $0.id == bundled.id }) {
            context.insert(try MovementDefinitionRecord(movement: bundled, encoder: encoder))
            inserted = true
        }
        if inserted { try context.save() }
    }

    func movements(includeArchived: Bool = false) async throws -> [MovementDefinition] {
        let decoded = try context.fetch(FetchDescriptor<MovementDefinitionRecord>())
            .compactMap { definition(from: $0) }
            .filter { includeArchived || !$0.isArchived }
        return decoded.sorted {
            $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
        }
    }

    func usageSummaries() async throws -> [MovementUsageSummary] {
        let definitions = try await movements(includeArchived: false)
        let planDates = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutPlanRecord>())
                .map { ($0.id, $0.scheduledAt) }
        )
        let segmentPlans = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSegmentRecord>())
                .map { ($0.id, $0.workoutPlanID) }
        )
        let completedDates = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<CompletedWorkoutRecord>())
                .map { ($0.id, $0.startedAt) }
        )
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]

        for record in try context.fetch(FetchDescriptor<MovementPrescriptionRecord>()) {
            guard let id = record.canonicalMovementID else { continue }
            counts[id, default: 0] += 1
            if let planID = segmentPlans[record.segmentID], let date = planDates[planID] {
                lastUsed[id] = max(lastUsed[id] ?? .distantPast, date)
            }
        }
        for record in try context.fetch(FetchDescriptor<CompletedMovementRecord>()) {
            guard let id = record.canonicalMovementID else { continue }
            counts[id, default: 0] += 1
            if let date = completedDates[record.workoutRecordID] {
                lastUsed[id] = max(lastUsed[id] ?? .distantPast, date)
            }
        }

        return definitions.map {
            MovementUsageSummary(
                movement: $0,
                appearanceCount: counts[$0.id, default: 0],
                lastUsedAt: lastUsed[$0.id]
            )
        }.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case (let left?, let right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if lhs.appearanceCount != rhs.appearanceCount {
                    return lhs.appearanceCount > rhs.appearanceCount
                }
                return lhs.movement.canonicalName.localizedCaseInsensitiveCompare(
                    rhs.movement.canonicalName
                ) == .orderedAscending
            }
        }
    }

    func saveMovement(_ movement: MovementDefinition) async throws {
        var movement = movement
        movement.canonicalName = movement.canonicalName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !movement.canonicalName.isEmpty else { throw MovementLibraryError.blankName }
        movement.aliases = Self.cleaned(movement.aliases, excluding: movement.canonicalName)
        movement.equipment = Self.cleaned(movement.equipment, excluding: nil)
        movement.updatedAt = .now

        let records = try context.fetch(FetchDescriptor<MovementDefinitionRecord>())
        if let duplicate = records.compactMap({ definition(from: $0) }).first(where: {
            $0.id != movement.id
                && Self.normalize($0.canonicalName) == Self.normalize(movement.canonicalName)
        }) {
            throw MovementLibraryError.duplicateName(duplicate.canonicalName)
        }
        if let record = records.first(where: { $0.id == movement.id }) {
            try update(record, from: movement)
        } else {
            context.insert(try MovementDefinitionRecord(movement: movement, encoder: encoder))
        }
        try context.save()
    }

    func setArchived(_ archived: Bool, movementID: String) async throws {
        guard
            let record = try context.fetch(FetchDescriptor<MovementDefinitionRecord>())
                .first(where: { $0.id == movementID })
        else { throw MovementLibraryError.unknownMovement }
        record.isArchived = archived
        record.updatedAt = .now
        try context.save()
    }

    func reconcile(_ plan: WorkoutPlan) async throws -> WorkoutPlan {
        var plan = plan
        var definitions = try await movements(includeArchived: true)
        var catalog = MovementCatalog(
            items: definitions.filter { !$0.isArchived }.map(\.catalogItem))

        for segmentIndex in plan.segments.indices {
            for movementIndex in plan.segments[segmentIndex].movements.indices {
                var prescription = plan.segments[segmentIndex].movements[movementIndex]
                if let canonicalID = prescription.canonicalMovementID,
                    let index = definitions.firstIndex(where: { $0.id == canonicalID })
                {
                    let displayName = prescription.displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if Self.isStableName(
                        displayName,
                        originalText: prescription.originalText
                    ),
                        Self.normalize(displayName)
                            != Self.normalize(definitions[index].canonicalName),
                        !definitions[index].aliases.contains(where: {
                            Self.normalize($0) == Self.normalize(displayName)
                        })
                    {
                        definitions[index].aliases.append(displayName)
                        try await saveMovement(definitions[index])
                    }
                } else if let matched = catalog.match(prescription.displayName) {
                    prescription.canonicalMovementID = matched.id
                    prescription.displayName = matched.canonicalName
                } else if Self.isStableName(
                    prescription.displayName,
                    originalText: prescription.originalText
                ) {
                    let definition = MovementDefinition.custom(name: prescription.displayName)
                    try await saveMovement(definition)
                    definitions.append(definition)
                    catalog = MovementCatalog(
                        items: definitions.filter { !$0.isArchived }.map(\.catalogItem)
                    )
                    prescription.canonicalMovementID = definition.id
                    prescription.displayName = definition.canonicalName
                }
                plan.segments[segmentIndex].movements[movementIndex] = prescription
            }
        }
        return plan
    }

    func previewWODLabImport(_ data: Data) async throws -> MovementLibraryImportPreview {
        let result = try importer.importMovements(from: data)
        let existing = try await movements(includeArchived: true)
        var occupiedNames = Set(
            existing.flatMap { [$0.canonicalName] + $0.aliases }.map(Self.normalize))
        var occupiedSources = Set(
            existing.compactMap { definition -> String? in
                guard definition.origin == .wodLab, let source = definition.sourceIdentifier else {
                    return nil
                }
                return Self.normalize(source)
            })
        var additions: [MovementDefinition] = []
        var matched = 0
        for candidate in result.candidates {
            let sourceKey = Self.normalize(candidate.id)
            let nameKey = Self.normalize(candidate.name)
            if occupiedSources.contains(sourceKey) || occupiedNames.contains(nameKey) {
                matched += 1
                continue
            }
            let now = Date.now
            let category = Self.category(candidate.category)
            additions.append(
                MovementDefinition(
                    id: "wod-lab-\(UUID().uuidString.lowercased())",
                    canonicalName: candidate.name,
                    aliases: candidate.aliases,
                    category: category,
                    movementFamily: category.rawValue,
                    equipment: [],
                    supportedMeasurements: Self.measurements(for: category),
                    preferredUnit: nil,
                    demandTags: [],
                    substitutionCandidateIDs: [],
                    origin: .wodLab,
                    sourceIdentifier: candidate.id,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now
                )
            )
            occupiedSources.insert(sourceKey)
            occupiedNames.insert(nameKey)
        }
        return MovementLibraryImportPreview(
            data: data,
            additions: additions,
            matchedCount: matched,
            skippedCount: result.skippedCount,
            issues: result.issues.map(\.message)
        )
    }

    func importWODLab(_ data: Data) async throws -> MovementLibraryImportResult {
        let parsed = try importer.importMovements(from: data)
        var existing = try await movements(includeArchived: true)
        var addedCount = 0
        var matchedCount = 0

        for candidate in parsed.candidates {
            if let index = existing.firstIndex(where: {
                ($0.origin == .wodLab && $0.sourceIdentifier == candidate.id)
                    || Self.normalize($0.canonicalName) == Self.normalize(candidate.name)
                    || $0.aliases.contains(where: {
                        Self.normalize($0) == Self.normalize(candidate.name)
                    })
            }) {
                existing[index].aliases = Self.cleaned(
                    existing[index].aliases + candidate.aliases,
                    excluding: existing[index].canonicalName
                )
                try await saveMovement(existing[index])
                matchedCount += 1
                continue
            }
            let now = Date.now
            let category = Self.category(candidate.category)
            let definition = MovementDefinition(
                id: "wod-lab-\(UUID().uuidString.lowercased())",
                canonicalName: candidate.name,
                aliases: candidate.aliases,
                category: category,
                movementFamily: category.rawValue,
                equipment: [],
                supportedMeasurements: Self.measurements(for: category),
                preferredUnit: nil,
                demandTags: [],
                substitutionCandidateIDs: [],
                origin: .wodLab,
                sourceIdentifier: candidate.id,
                isArchived: false,
                createdAt: now,
                updatedAt: now
            )
            try await saveMovement(definition)
            existing.append(definition)
            addedCount += 1
        }

        return MovementLibraryImportResult(
            addedCount: addedCount,
            matchedCount: matchedCount,
            skippedCount: parsed.skippedCount,
            issues: parsed.issues.map(\.message)
        )
    }

    private func definition(from record: MovementDefinitionRecord) -> MovementDefinition? {
        guard let category = MovementCategory(rawValue: record.category),
            let origin = MovementOrigin(rawValue: record.origin),
            let aliases = try? decoder.decode([String].self, from: record.aliasesData),
            let equipment = try? decoder.decode([String].self, from: record.equipmentData),
            let measurements = try? decoder.decode(
                Set<MovementMeasurement>.self,
                from: record.supportedMeasurementsData
            ),
            let demands = try? decoder.decode(
                Set<MovementDemand>.self, from: record.demandTagsData),
            let substitutions = try? decoder.decode(
                [String].self,
                from: record.substitutionCandidateIDsData
            )
        else { return nil }
        return MovementDefinition(
            id: record.id,
            canonicalName: record.canonicalName,
            aliases: aliases,
            category: category,
            movementFamily: record.movementFamily,
            equipment: equipment,
            supportedMeasurements: measurements,
            preferredUnit: record.preferredUnit,
            demandTags: demands,
            substitutionCandidateIDs: substitutions,
            origin: origin,
            sourceIdentifier: record.sourceIdentifier,
            isArchived: record.isArchived,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func update(
        _ record: MovementDefinitionRecord,
        from movement: MovementDefinition
    ) throws {
        record.canonicalName = movement.canonicalName
        record.aliasesData = try encoder.encode(movement.aliases)
        record.category = movement.category.rawValue
        record.movementFamily = movement.movementFamily
        record.equipmentData = try encoder.encode(movement.equipment)
        record.supportedMeasurementsData = try encoder.encode(movement.supportedMeasurements)
        record.preferredUnit = movement.preferredUnit
        record.demandTagsData = try encoder.encode(movement.demandTags)
        record.substitutionCandidateIDsData = try encoder.encode(movement.substitutionCandidateIDs)
        record.origin = movement.origin.rawValue
        record.sourceIdentifier = movement.sourceIdentifier
        record.isArchived = movement.isArchived
        record.createdAt = movement.createdAt
        record.updatedAt = movement.updatedAt
    }

    private static func category(_ category: WODLabMovementCategory) -> MovementCategory {
        switch category {
        case .weightlifting: .weightlifting
        case .power: .strength
        case .gymnastics: .gymnastics
        case .machine: .machine
        case .running: .running
        case .jumping: .jumping
        case .carry: .carry
        case .oddObject: .oddObject
        case .crossfit: .mixed
        }
    }

    private static func measurements(
        for category: MovementCategory
    ) -> Set<MovementMeasurement> {
        switch category {
        case .machine, .running: [.distance, .calories, .duration]
        case .jumping, .gymnastics: [.repetitions, .duration]
        case .carry, .oddObject: [.repetitions, .load, .distance, .duration]
        case .weightlifting, .strength: [.repetitions, .load, .percentageOneRepMax]
        case .mixed: [.repetitions, .load, .distance, .calories, .duration]
        }
    }

    private static func cleaned(_ values: [String], excluding: String?) -> [String] {
        var seen = Set(excluding.map { [normalize($0)] } ?? [])
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(normalize(trimmed)).inserted else { return nil }
            return trimmed
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isStableName(_ value: String, originalText: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return false }
        let normalized = normalize(trimmed)
        guard normalized != "movement", normalized.split(separator: " ").count <= 8 else {
            return false
        }
        if trimmed.rangeOfCharacter(from: .decimalDigits) != nil,
            normalized == normalize(originalText)
        {
            return false
        }
        return true
    }
}
