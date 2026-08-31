import Foundation

enum ProtocolSource: String, Codable, CaseIterable, Hashable, Sendable {
    case photo
    case paste
    case dictation

    var displayName: String {
        switch self {
        case .photo: "from photo"
        case .paste: "from paste"
        case .dictation: "from dictation"
        }
    }
}

enum ProtocolCadence: Codable, Equatable, Hashable, Sendable {
    case daily
    case timesPerWeek(Int)
    case daysOfWeek(Set<Int>)

    var displayName: String {
        switch self {
        case .daily: "daily"
        case .timesPerWeek(let count): "\(count)×/wk"
        case .daysOfWeek(let days):
            days.sorted().map(Self.shortWeekdayName).joined(separator: "/")
        }
    }

    var isValid: Bool {
        switch self {
        case .daily: true
        case .timesPerWeek(let count): (1...7).contains(count)
        case .daysOfWeek(let days):
            !days.isEmpty && days.allSatisfy { (1...7).contains($0) }
        }
    }

    static func shortWeekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: "Su"
        case 2: "M"
        case 3: "Tu"
        case 4: "W"
        case 5: "Th"
        case 6: "F"
        case 7: "Sa"
        default: "?"
        }
    }
}

enum ProtocolItemResolution: Equatable, Hashable, Sendable {
    case matched(movementID: String, name: String)
    case ambiguous(candidateIDs: [String])
    case unknown
}

struct ParsedProtocolItem: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let line: Int
    let originalText: String
    var movementText: String
    var sets: Int?
    var repetitions: Int?
    var durationSeconds: Int?
    var loadValue: Double?
    var loadUnit: String?
    var cadence: ProtocolCadence?
    var notes: String
    var resolution: ProtocolItemResolution
}

struct ParsedProtocol: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    var title: String
    let rawText: String
    let source: ProtocolSource
    var phaseNumber: Int?
    var phaseCount: Int?
    var unlockMilestone: String?
    var defaultCadence: ProtocolCadence?
    var items: [ParsedProtocolItem]
    var parserConfidence: Double
    let parserVersion: String
}

enum ProtocolParseError: Error, Equatable, LocalizedError, Sendable {
    case emptyText
    case noItemsFound
    case noTextRecognized

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "Enter or capture the protocol text before parsing."
        case .noItemsFound:
            "No protocol items were found on that sheet. Try a clearer photo, or paste the text."
        case .noTextRecognized:
            "Couldn't read any text in that photo. Try more light, or paste the text instead."
        }
    }
}

/// One reviewable row on the parse-review screen. Ambiguous rows must be resolved by
/// tapping a candidate and unknown rows by adding a personal movement before the row
/// can become part of a saved protocol; the parser itself never picks for the user.
struct ProtocolReviewItem: Equatable, Identifiable, Sendable {
    let id: String
    let originalText: String
    var movementText: String
    var displayName: String
    var canonicalMovementID: String?
    var candidateIDs: [String]
    var isNewMovement: Bool
    var sets: Int?
    var repetitions: Int?
    var durationSeconds: Int?
    var loadValue: Double?
    var loadUnit: String?
    var cadence: ProtocolCadence
    var notes: String

    init(parsed: ParsedProtocolItem, defaultCadence: ProtocolCadence) {
        id = parsed.id
        originalText = parsed.originalText
        movementText = parsed.movementText
        sets = parsed.sets
        repetitions = parsed.repetitions
        durationSeconds = parsed.durationSeconds
        loadValue = parsed.loadValue
        loadUnit = parsed.loadUnit
        cadence = parsed.cadence ?? defaultCadence
        notes = parsed.notes
        switch parsed.resolution {
        case .matched(let movementID, let name):
            canonicalMovementID = movementID
            displayName = name
            candidateIDs = []
            isNewMovement = false
        case .ambiguous(let candidateIDs):
            canonicalMovementID = nil
            displayName = parsed.movementText
            self.candidateIDs = candidateIDs
            isNewMovement = false
        case .unknown:
            canonicalMovementID = nil
            displayName = parsed.movementText
            candidateIDs = []
            isNewMovement = true
        }
    }

    var isResolved: Bool { canonicalMovementID != nil }
    var needsAttention: Bool { !isResolved || !cadence.isValid }

    mutating func resolve(toMovementID movementID: String, name: String) {
        canonicalMovementID = movementID
        displayName = name
    }

    var quantitySummary: String? {
        var values: [String] = []
        switch (sets, repetitions, durationSeconds) {
        case (let sets?, let repetitions?, _):
            values.append("\(sets)×\(repetitions)")
        case (let sets?, nil, let duration?):
            values.append("\(sets)×\(duration)s")
        case (nil, let repetitions?, _):
            values.append("\(repetitions) reps")
        case (nil, nil, let duration?):
            values.append("\(duration)s")
        case (let sets?, nil, nil):
            values.append("\(sets) sets")
        case (nil, nil, nil):
            break
        }
        if let loadValue {
            values.append("\(loadValue.formatted()) \(loadUnit ?? "lb")")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    func savedItem(order: Int) -> TherapyProtocolItem? {
        guard let canonicalMovementID, cadence.isValid else { return nil }
        return TherapyProtocolItem(
            id: id,
            order: order,
            canonicalMovementID: canonicalMovementID,
            displayName: displayName,
            originalText: originalText,
            sets: sets,
            repetitions: repetitions,
            durationSeconds: durationSeconds,
            loadValue: loadValue,
            loadUnit: loadUnit,
            cadence: cadence,
            notes: notes
        )
    }

    func evaluationPrescription() -> MovementPrescription? {
        guard let canonicalMovementID else { return nil }
        return MovementPrescription(
            id: id,
            canonicalMovementID: canonicalMovementID,
            displayName: displayName,
            originalText: originalText,
            repetitions: repetitions,
            distanceMeters: nil,
            calories: nil,
            loadValue: loadValue,
            loadUnit: loadUnit,
            percentageOfOneRepMax: nil,
            durationSeconds: durationSeconds.map(Double.init),
            tempo: nil,
            notes: notes
        )
    }
}

/// Builds a transient plan so protocol items run through the same restriction
/// evaluation as workout plans. The plan is never persisted.
enum ProtocolRestrictionCheck {
    static func evaluationPlan(title: String, items: [ProtocolReviewItem]) -> WorkoutPlan? {
        let prescriptions = items.compactMap { $0.evaluationPrescription() }
        guard !prescriptions.isEmpty else { return nil }
        let now = Date.now
        return WorkoutPlan(
            id: "protocol-review-check",
            title: title,
            rawText: title,
            parsedAt: now,
            scheduledAt: now,
            status: .draft,
            format: .manual,
            intendedStimulus: WorkoutStimulus(
                primary: "PT protocol",
                secondary: [],
                estimatedDurationMinimumMinutes: nil,
                estimatedDurationMaximumMinutes: nil
            ),
            timeCapSeconds: nil,
            parserVersion: DeterministicProtocolParser.parserVersion,
            modelVersion: nil,
            confidence: 1,
            ambiguities: [],
            segments: [
                WorkoutSegment(
                    id: "protocol-review-check-segment",
                    sequence: 1,
                    type: .work,
                    rounds: nil,
                    durationSeconds: nil,
                    restSeconds: nil,
                    notes: "",
                    movements: prescriptions
                )
            ]
        )
    }
}

struct TherapyProtocolItem: Equatable, Identifiable, Sendable {
    let id: String
    var order: Int
    var canonicalMovementID: String
    var displayName: String
    var originalText: String
    var sets: Int?
    var repetitions: Int?
    var durationSeconds: Int?
    var loadValue: Double?
    var loadUnit: String?
    var cadence: ProtocolCadence
    var notes: String

    var prescriptionSummary: String? {
        var values: [String] = []
        switch (sets, repetitions, durationSeconds) {
        case (let sets?, let repetitions?, _):
            values.append("\(sets)×\(repetitions)")
        case (let sets?, nil, let duration?):
            values.append("\(sets)×\(duration)s")
        case (nil, let repetitions?, _):
            values.append("\(repetitions) reps")
        case (nil, nil, let duration?):
            values.append("\(duration)s")
        case (let sets?, nil, nil):
            values.append("\(sets) sets")
        case (nil, nil, nil):
            break
        }
        if let loadValue {
            values.append("\(loadValue.formatted()) \(loadUnit ?? "lb")")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

struct TherapyProtocol: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var source: ProtocolSource
    var rawText: String
    var phaseNumber: Int?
    var phaseCount: Int?
    var unlockMilestone: String?
    var startedAt: Date
    var endsAt: Date?
    var parserVersion: String
    var confidence: Double
    var isArchived: Bool
    var createdAt: Date
    var items: [TherapyProtocolItem]

    func validated() throws -> TherapyProtocol {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProtocolValidationError.emptyTitle
        }
        guard !items.isEmpty else { throw ProtocolValidationError.missingItems }
        guard (0...1).contains(confidence) else { throw ProtocolValidationError.invalidConfidence }
        for item in items {
            guard
                !item.canonicalMovementID.isEmpty,
                !item.displayName.trimmingCharacters(in: .whitespaces).isEmpty,
                item.order > 0
            else { throw ProtocolValidationError.invalidItem }
            guard item.cadence.isValid else { throw ProtocolValidationError.invalidCadence }
            let integers = [item.sets, item.repetitions, item.durationSeconds].compactMap { $0 }
            guard integers.allSatisfy({ $0 > 0 }) else {
                throw ProtocolValidationError.invalidItem
            }
            if let load = item.loadValue, load <= 0 {
                throw ProtocolValidationError.invalidItem
            }
        }
        return self
    }

    var phaseSummary: String? {
        guard let phaseNumber else { return nil }
        guard let phaseCount else { return "phase \(phaseNumber)" }
        return "phase \(phaseNumber) of \(phaseCount)"
    }
}

enum ProtocolValidationError: Error, Equatable, LocalizedError, Sendable {
    case emptyTitle
    case missingItems
    case invalidConfidence
    case invalidItem
    case invalidCadence

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Give the protocol a title before saving."
        case .missingItems: "A protocol needs at least one item."
        case .invalidConfidence: "Parser confidence must be between zero and one."
        case .invalidItem: "A protocol item is incomplete or has an invalid quantity."
        case .invalidCadence: "Pick at least one day for every custom-cadence item."
        }
    }
}
