import Foundation

protocol WorkoutTextGenerating: Sendable {
    var modelIdentifier: String { get }
    func generate(workout: String) async throws -> Data
}

enum WorkoutAIFailure: Error, Sendable {
    case unsupported, disabled, notReady, busy, tooLong, timedOut, invalidOutput, generationFailed

    var message: String {
        switch self {
        case .unsupported: "Apple’s on-device model is not supported on this device or OS."
        case .disabled: "Apple Intelligence is turned off in device Settings."
        case .notReady: "Apple’s on-device model is still getting ready."
        case .busy: "Apple’s on-device model is finishing another request."
        case .tooLong: "This workout exceeds the on-device parser’s input limit."
        case .timedOut: "Apple parsing took too long."
        case .invalidOutput: "The AI draft could not be verified against the pasted workout."
        case .generationFailed: "Apple could not produce a complete workout draft."
        }
    }
}

/// A small extraction contract, independent of the OS framework and its generated types.
/// Quantities are source quotations, not model-computed numbers or converted units.
struct WorkoutExtraction: Codable, Sendable {
    var format: String
    var timeCap: String?
    var segments: [Segment]

    struct Segment: Codable, Sendable {
        var kind: String
        var rounds: String?
        var duration: String?
        var rest: String?
        var contextLines: [Int]
        var movements: [Movement]
    }

    struct Movement: Codable, Sendable {
        var line: Int
        var name: String
        var reps: String?
        var distance: String?
        var calories: String?
        var load: String?
        var duration: String?
        var percentage: String?
    }
}

/// Each call sees exactly one source line, never earlier generated content. The assembler, not
/// the model, owns source IDs, ordering, segment boundaries, and the final extraction document.
protocol WorkoutPartGenerating: Sendable {
    func generate(part: String) async throws -> WorkoutPartExtraction
}

struct WorkoutPartExtraction: Codable, Sendable {
    var role: String
    var format: String

    /// One model label maps to these internal fields. The model cannot independently assign a
    /// movement role and a conflicting format inferred from that exercise's type.
    static func classified(as kind: String) throws -> Self {
        switch kind {
        case "exercise_line": .init(role: "movement", format: "unspecified")
        case "for_time_header": .init(role: "instruction", format: "for_time")
        case "amrap_header": .init(role: "instruction", format: "amrap")
        case "emom_header": .init(role: "instruction", format: "emom")
        case "round_count_header": .init(role: "instruction", format: "rounds")
        case "set_count_header", "strength_header": .init(role: "instruction", format: "strength")
        case "time_cap_line": .init(role: "instruction", format: "unspecified")
        case "rest_line": .init(role: "rest", format: "unspecified")
        case "context_line": .init(role: "context", format: "unspecified")
        default: throw WorkoutAIFailure.invalidOutput
        }
    }
}

struct StagedWorkoutExtractor: Sendable {
    static let maximumParts = 16
    let model: any WorkoutPartGenerating

    func generate(workout: String) async throws -> Data {
        let parts = try workout.components(separatedBy: .newlines).map { line -> (Int, String) in
            guard let colon = line.firstIndex(of: ":"),
                let number = Int(line[..<colon]), number > 0
            else { throw WorkoutAIFailure.invalidOutput }
            let text = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { throw WorkoutAIFailure.invalidOutput }
            return (number, text)
        }
        guard !parts.isEmpty, parts.count <= Self.maximumParts else {
            throw WorkoutAIFailure.tooLong
        }
        guard zip(parts, parts.dropFirst()).allSatisfy({ $0.0 < $1.0 }) else {
            throw WorkoutAIFailure.invalidOutput
        }
        var formats = Set<String>()
        var cap: String?
        var rounds: String?
        var context: [Int] = []
        var segments: [WorkoutExtraction.Segment] = []
        var movements: [WorkoutExtraction.Movement] = []

        for (number, text) in parts {
            try Task.checkCancellation()
            let part = try await model.generate(part: text)
            try Task.checkCancellation()
            guard ["movement", "instruction", "rest", "context"].contains(part.role),
                ["unspecified", "for_time", "amrap", "emom", "rounds", "strength", "intervals"]
                    .contains(part.format)
            else { throw WorkoutAIFailure.invalidOutput }
            let quantities = VersionedWorkoutParser.quotedQuantities(in: text)
            let keys = Set(quantities.keys)
            if !Self.isContextMetadata(text) {
                guard
                    WorkoutExtraction.numbers(in: text).isSubset(
                        of:
                            WorkoutExtraction.numbers(in: quantities.values.joined(separator: " ")))
                else { throw WorkoutAIFailure.invalidOutput }
            }
            if let expected = Self.explicitFormat(text) {
                guard part.role == "instruction", part.format == expected else {
                    throw WorkoutAIFailure.invalidOutput
                }
            }
            if part.role != "instruction", part.format != "unspecified" {
                throw WorkoutAIFailure.invalidOutput
            }
            switch part.role {
            case "instruction":
                guard keys.isSubset(of: ["duration", "rounds"]) else {
                    throw WorkoutAIFailure.invalidOutput
                }
                if part.format == "unspecified", quantities.isEmpty {
                    // Empty classification of an unfamiliar instruction is not a complete parse.
                    throw WorkoutAIFailure.invalidOutput
                }
                // Instructions after work may add a cap, but cannot silently change scope or format.
                if part.format != "unspecified" {
                    guard segments.isEmpty, movements.isEmpty else {
                        throw WorkoutAIFailure.invalidOutput
                    }
                    formats.insert(part.format)
                }
                if let count = quantities["rounds"] {
                    guard rounds == nil, segments.isEmpty, movements.isEmpty else {
                        throw WorkoutAIFailure.invalidOutput
                    }
                    rounds = count
                }
                if let duration = quantities["duration"] {
                    guard cap == nil,
                        part.format == "amrap" || part.format == "emom"
                            || text.range(
                                of: #"(?i)\b(?:cap|limit)\b"#, options: .regularExpression) != nil
                    else { throw WorkoutAIFailure.invalidOutput }
                    cap = duration
                }
                guard
                    quantities.isEmpty || part.format != "unspecified" || cap != nil
                        || rounds != nil
                else {
                    throw WorkoutAIFailure.invalidOutput
                }
                context.append(number)
            case "movement":
                guard
                    keys.isSubset(of: [
                        "reps", "distance", "calories", "load", "duration", "percentage",
                    ]),
                    !Self.isStructuralLine(text)
                else { throw WorkoutAIFailure.invalidOutput }
                movements.append(
                    .init(
                        line: number, name: text, reps: quantities["reps"],
                        distance: quantities["distance"], calories: quantities["calories"],
                        load: quantities["load"], duration: quantities["duration"],
                        percentage: quantities["percentage"]))
            case "rest":
                guard keys == ["duration"], !movements.isEmpty,
                    text.range(
                        of: #"(?i)^\s*(?:rest|recover|recovery)\b"#, options: .regularExpression)
                        != nil
                else { throw WorkoutAIFailure.invalidOutput }
                segments.append(.init(kind: "work", contextLines: context, movements: movements))
                context = []
                movements = []
                segments.append(
                    .init(
                        kind: "rest", duration: quantities["duration"], contextLines: [number],
                        movements: []))
            default:
                // An unfamiliar exercise must not disappear as generic context. Permit only a
                // leading title or explicit metadata; everything else needs deterministic fallback.
                guard quantities.isEmpty,
                    (!Self.isStructuralLine(text) && number == parts.first?.0
                        && text.hasSuffix(":"))
                        || Self.isContextMetadata(text)
                else { throw WorkoutAIFailure.invalidOutput }
                context.append(number)
            }
        }
        if !movements.isEmpty {
            segments.append(.init(kind: "work", contextLines: context, movements: movements))
        } else if !context.isEmpty, !segments.isEmpty {
            segments[0].contextLines += context
        }
        // A fixed-round instruction plus explicit rest blocks has ambiguous scope in this first
        // staged contract. Do not guess whether the entire sequence or one block repeats.
        guard !segments.isEmpty, formats.count <= 1 || formats == ["for_time", "rounds"],
            rounds == nil || segments.count == 1,
            formats.isDisjoint(with: ["amrap", "emom"]) || segments.count == 1
        else { throw WorkoutAIFailure.invalidOutput }
        let format = formats.contains("for_time") ? "for_time" : formats.first ?? "manual"
        if segments.count == 1 {
            segments[0].rounds = rounds
            if format == "amrap" || format == "emom" { segments[0].duration = cap }
        }
        return try JSONEncoder().encode(
            WorkoutExtraction(format: format, timeCap: cap, segments: segments))
    }

    private static func isStructuralLine(_ text: String) -> Bool {
        text.range(
            of:
                #"(?i)^\s*(?:(?:complete\s+)?for time\b|(?:complete\s+)?as many\b|amrap\b|emom\b|time cap\b|strength\b|\d+\s+(?:rounds?|sets?)\b|rest\b)"#,
            options: .regularExpression) != nil
    }

    private static func explicitFormat(_ text: String) -> String? {
        let patterns = [
            (
                "amrap",
                #"(?i)\b(?:amrap|as many (?:rounds(?: and reps)?|reps|repetitions) as possible)\b"#
            ),
            ("emom", #"(?i)\b(?:emom|every minute)\b"#),
            ("for_time", #"(?i)^\s*(?:complete\s+)?for time\b"#),
            ("strength", #"(?i)^\s*(?:strength\b|\d+\s+sets?\b)"#),
            ("rounds", #"(?i)^\s*\d+\s+rounds?\b"#),
        ]
        return patterns.first { text.range(of: $0.1, options: .regularExpression) != nil }?.0
    }

    private static func isContextMetadata(_ text: String) -> Bool {
        text.range(
            of:
                #"(?i)^\s*(?:heart rate target|hr target|intensity|target intensity|intended rpe|rpe target)\s*:"#,
            options: .regularExpression) != nil
    }
}

struct OnDeviceWorkoutParser: WorkoutParser {
    static let parserVersion = "apple-extraction-2.0.0"
    static let maximumInputBytes = 2_400
    let model: any WorkoutTextGenerating
    var catalog: MovementCatalog = .standard
    var timeout: Duration = .seconds(20)

    func parse(rawText: String) async throws -> ParsedWorkout {
        try Task.checkCancellation()
        let source = WorkoutExtractionSource(rawText)
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkoutValidationError.emptyRawText
        }
        guard source.prompt.utf8.count <= Self.maximumInputBytes else {
            throw WorkoutAIFailure.tooLong
        }
        let data = try await WorkoutParserDeadline.run(timeout: timeout) {
            try await model.generate(workout: source.prompt)
        }
        try Task.checkCancellation()
        do {
            guard data.count <= 64_000 else { throw WorkoutAIFailure.invalidOutput }
            let extraction = try JSONDecoder().decode(WorkoutExtraction.self, from: data)
                .normalizingAbsentQuantities()
            return try extraction.validated(
                source: source, catalog: catalog,
                modelIdentifier: model.modelIdentifier)
        } catch {
            throw WorkoutAIFailure.invalidOutput
        }
    }
}

struct WorkoutExtractionSource: Sendable {
    let rawText: String
    let lines: [String]
    let resultLines: Set<Int>

    init(_ rawText: String) {
        self.rawText = rawText
        let lines = rawText.components(separatedBy: .newlines)
        self.lines = lines
        resultLines = Set(
            lines.indices.filter {
                Self.normalized(lines[$0]).range(
                    of: #"^(?:[•●▪◦‣∙·*-]\s*)?(?:score|result|completed)\s*:"#,
                    options: .regularExpression
                ) != nil
            })
    }

    var prompt: String {
        lines.enumerated().filter {
            !resultLines.contains($0.offset)
                && !$0.element.trimmingCharacters(in: .whitespaces).isEmpty
        }
        .map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
    }

    var prescriptionText: String {
        lines.enumerated().filter { !resultLines.contains($0.offset) }
            .map(\.element).joined(separator: "\n")
    }

    func line(_ number: Int) throws -> String {
        guard lines.indices.contains(number - 1), !resultLines.contains(number - 1) else {
            throw WorkoutAIFailure.invalidOutput
        }
        return lines[number - 1]
    }

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func verify(_ quote: String?, in source: String) throws -> String? {
        guard let quote else { return nil }
        let normalized = normalized(quote)
        let pattern =
            #"(?<![\p{L}\p{N}.])"#
            + NSRegularExpression.escapedPattern(for: normalized)
            + #"(?![\p{L}\p{N}.])"#
        guard !normalized.isEmpty, normalized.count <= 120,
            Self.normalized(source).range(of: pattern, options: .regularExpression) != nil
        else { throw WorkoutAIFailure.invalidOutput }
        return normalized
    }
}

extension WorkoutExtraction {
    /// Some system model revisions emit the literal string "null" for optional quoted fields.
    /// Only this exact absence sentinel is normalized; malformed numbers still fail validation.
    func normalizingAbsentQuantities() -> WorkoutExtraction {
        func absent(_ value: String?) -> String? {
            value.map(WorkoutExtractionSource.normalized) == "null" ? nil : value
        }
        var copy = self
        copy.timeCap = absent(timeCap)
        for s in copy.segments.indices {
            copy.segments[s].rounds = absent(copy.segments[s].rounds)
            copy.segments[s].duration = absent(copy.segments[s].duration)
            copy.segments[s].rest = absent(copy.segments[s].rest)
            for m in copy.segments[s].movements.indices {
                copy.segments[s].movements[m].reps = absent(copy.segments[s].movements[m].reps)
                copy.segments[s].movements[m].distance = absent(
                    copy.segments[s].movements[m].distance)
                copy.segments[s].movements[m].calories = absent(
                    copy.segments[s].movements[m].calories)
                copy.segments[s].movements[m].load = absent(copy.segments[s].movements[m].load)
                copy.segments[s].movements[m].duration = absent(
                    copy.segments[s].movements[m].duration)
                copy.segments[s].movements[m].percentage = absent(
                    copy.segments[s].movements[m].percentage)
            }
        }
        return copy
    }

    func validated(
        source: WorkoutExtractionSource, catalog: MovementCatalog,
        modelIdentifier: String
    ) throws -> ParsedWorkout {
        guard let format = WorkoutFormat(rawValue: format), (1...8).contains(segments.count),
            segments.reduce(0, { $0 + $1.movements.count }) <= 24
        else { throw WorkoutAIFailure.invalidOutput }
        let timeCap = try Self.seconds(timeCap, in: source.prescriptionText)
        var covered = Set<Int>()
        var seenMovements = Set<Int>()
        var ambiguities: [WorkoutAmbiguity] = []
        var built: [WorkoutSegment] = []
        for (index, segment) in segments.enumerated() {
            guard let kind = WorkoutSegmentType(rawValue: segment.kind),
                segment.contextLines.count <= source.lines.count
            else { throw WorkoutAIFailure.invalidOutput }
            let context = try segment.contextLines.map { number in
                covered.insert(number)
                return try source.line(number)
            }
            if let rounds = segment.rounds {
                let count = try Self.integer(
                    rounds, in: source.prescriptionText,
                    suffix: #"rounds?|sets?|efforts?"#)!
                guard
                    WorkoutExtractionSource.normalized(source.prescriptionText).range(
                        of: "\\b\(count)\\s*(?:rounds?|sets?|efforts?)\\b",
                        options: .regularExpression
                    ) != nil
                else { throw WorkoutAIFailure.invalidOutput }
            }
            if kind == .rest || segment.rest != nil {
                guard
                    context.contains(where: {
                        WorkoutExtractionSource.normalized($0).range(
                            of: #"\b(?:rest|recover|recovery)\b"#, options: .regularExpression
                        ) != nil
                    })
                else { throw WorkoutAIFailure.invalidOutput }
            }
            let movements = try segment.movements.map { item -> MovementPrescription in
                let original = try source.line(item.line)
                _ = try WorkoutExtractionSource.verify(item.name, in: original)
                guard seenMovements.insert(item.line).inserted
                else { throw WorkoutAIFailure.invalidOutput }
                covered.insert(item.line)
                // The model never selects catalog IDs, demand tags, or substitutions.
                let match = catalog.match(original)
                let load = try Self.quantity(
                    item.load, in: original, units: #"lb|lbs|pounds?|kg|kilograms?|#"#)
                let distance = try Self.quantity(
                    item.distance, in: original,
                    units: #"m|meters?|metres?|km|kilometers?|kilometres?"#)
                let percentage = try Self.quantity(item.percentage, in: original, units: #"%"#)
                let reps = try Self.integer(item.reps, in: original, suffix: #"reps?|repetitions?"#)
                let calories = try Self.integer(
                    item.calories, in: original, suffix: #"cal|cals|calories?"#)
                let duration = try Self.seconds(item.duration, in: original)
                let quotes = [
                    item.reps, item.distance, item.calories, item.load,
                    item.duration, item.percentage,
                ].compactMap { $0 }.joined(separator: " ")
                if !Self.numbers(in: original).isSubset(of: Self.numbers(in: quotes)) {
                    ambiguities.append(
                        .init(
                            id: "apple-parser-incomplete-numbers-\(item.line)", line: item.line,
                            originalText: original,
                            message:
                                "Some source numbers were not extracted. Check quantities, alternatives, and tempo manually."
                        ))
                }
                if match == nil
                    || [
                        item.reps, item.distance, item.calories, item.load,
                        item.duration, item.percentage,
                    ].allSatisfy({ $0 == nil })
                {
                    ambiguities.append(
                        .init(
                            id: match == nil
                                ? UUID().uuidString
                                : "apple-parser-incomplete-quantity-\(item.line)", line: item.line,
                            originalText: original,
                            message: match == nil
                                ? "Unmapped movement; review its name and restrictions."
                                : "No quantity was extracted; review the original prescription."))
                }
                guard percentage.map({ $0.value <= 100 }) ?? true else {
                    throw WorkoutAIFailure.invalidOutput
                }
                return MovementPrescription(
                    id: UUID().uuidString.lowercased(), canonicalMovementID: match?.id,
                    displayName: match?.canonicalName ?? item.name, originalText: original,
                    repetitions: reps,
                    distanceMeters: distance.map {
                        Int(($0.value * ($0.unit.hasPrefix("k") ? 1_000 : 1)).rounded())
                    },
                    calories: calories, loadValue: load?.value,
                    loadUnit: load.map { $0.unit.hasPrefix("k") ? "kg" : "lb" },
                    percentageOfOneRepMax: percentage?.value, durationSeconds: duration,
                    tempo: nil, notes: ""
                )
            }
            built.append(
                WorkoutSegment(
                    id: UUID().uuidString.lowercased(), sequence: index + 1, type: kind,
                    rounds: try Self.integer(
                        segment.rounds, in: source.prescriptionText,
                        suffix: #"rounds?|sets?|efforts?"#),
                    durationSeconds: try Self.seconds(
                        segment.duration, in: source.prescriptionText),
                    restSeconds: try Self.seconds(segment.rest, in: source.prescriptionText),
                    notes: context.joined(separator: "\n"), movements: movements
                ))
        }
        // No source line disappears silently, including unsupported instructions or quantities.
        for (index, line) in source.lines.enumerated()
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if source.resultLines.contains(index) {
                built[0].notes += "\nReported result (not a prescription): \(line)"
            } else if !covered.contains(index + 1)
                || (!seenMovements.contains(index + 1) && catalog.match(line) != nil)
            {
                ambiguities.append(
                    .init(
                        id: "apple-parser-incomplete-line-\(index + 1)", line: index + 1,
                        originalText: line,
                        message: "This source line was not structured; review it manually."))
            }
        }
        let movements = built.flatMap(\.movements)
        guard !movements.isEmpty else { throw WorkoutAIFailure.invalidOutput }
        let result = ParsedWorkout(
            title: "\(movements.first?.displayName ?? "Workout") · \(format.displayName)",
            rawText: source.rawText, format: format, timeCapSeconds: timeCap,
            intendedStimulus: VersionedWorkoutParser(catalog: catalog).stimulus(
                for: movements, format: format, timeCap: timeCap, context: []),
            segments: built, ambiguities: ambiguities,
            // A conservative review indicator, not model self-reported probability of correctness.
            parserConfidence: ambiguities.isEmpty ? 0.7 : 0.4,
            parserVersion: OnDeviceWorkoutParser.parserVersion, modelVersion: modelIdentifier,
            reportedResult: WorkoutReportedResult.parse(source.rawText)
        )
        return try result.validated(catalog: catalog)
    }

    private static func integer(_ quote: String?, in source: String, suffix: String) throws -> Int?
    {
        guard let text = try WorkoutExtractionSource.verify(quote, in: source) else { return nil }
        let groups = try captures(#"^(\d+)(?:\s*(?:"# + suffix + #"))?$"#, text)
        guard let value = Int(groups[0]), (1...100_000).contains(value) else {
            throw WorkoutAIFailure.invalidOutput
        }
        return value
    }

    private static func quantity(_ quote: String?, in source: String, units: String)
        throws -> (value: Double, unit: String)?
    {
        guard let text = try WorkoutExtractionSource.verify(quote, in: source) else { return nil }
        let groups = try captures(#"^(\d+(?:\.\d+)?)\s*("# + units + #")$"#, text)
        guard let value = Double(groups[0]), value.isFinite, value > 0, value <= 100_000 else {
            throw WorkoutAIFailure.invalidOutput
        }
        return (value, groups[1])
    }

    private static func seconds(_ quote: String?, in source: String) throws -> Double? {
        guard let text = try WorkoutExtractionSource.verify(quote, in: source) else { return nil }
        if text.contains(":") {
            let groups = try captures(#"^(\d{1,3}):(\d{2})$"#, text)
            guard let minutes = Int(groups[0]), let seconds = Int(groups[1]), seconds < 60,
                minutes * 60 + seconds > 0
            else { throw WorkoutAIFailure.invalidOutput }
            return Double(minutes * 60 + seconds)
        }
        let quantity = try quantity(
            text, in: source, units: #"s|sec|secs|seconds?|min|mins|minutes?|h|hours?"#)!
        let multiplier =
            quantity.unit.hasPrefix("m") ? 60 : quantity.unit.hasPrefix("h") ? 3_600 : 1
        let seconds = quantity.value * Double(multiplier)
        guard seconds > 0 && seconds <= 86_400 else { throw WorkoutAIFailure.invalidOutput }
        return seconds
    }

    private static func captures(_ pattern: String, _ text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else {
            throw WorkoutAIFailure.invalidOutput
        }
        return (1..<match.numberOfRanges).map {
            Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }

    fileprivate static func numbers(in text: String) -> Set<String> {
        // "1RM" names a reference maximum, not an additional prescribed repetition.
        let normalized = WorkoutExtractionSource.normalized(text)
            .replacingOccurrences(of: #"\b1\s*rm\b"#, with: "", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        return Set(
            regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
                .compactMap { Range($0.range, in: normalized).map { String(normalized[$0]) } })
    }
}

/// Returns promptly even if a provider is slow to acknowledge cancellation. The provider must
/// serialize its own requests so a cancelled request cannot overlap another model allocation.
private final class WorkoutParserDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var result: Result<Data, any Error>?
    private var tasks: [Task<Void, Never>] = []

    static func run(timeout: Duration, operation: @escaping @Sendable () async throws -> Data)
        async throws -> Data
    {
        let race = WorkoutParserDeadline()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                race.add(
                    Task {
                        do {
                            try Task.checkCancellation()
                            race.finish(.success(try await operation()))
                        } catch { race.finish(.failure(error)) }
                    })
                race.add(
                    Task {
                        do {
                            try await Task.sleep(for: timeout)
                            race.finish(.failure(WorkoutAIFailure.timedOut))
                        } catch {
                            // The other branch or the caller finished first.
                        }
                    })
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<Data, any Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func add(_ task: Task<Void, Never>) {
        lock.lock()
        if result != nil {
            lock.unlock()
            task.cancel()
        } else {
            tasks.append(task)
            lock.unlock()
        }
    }

    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        for task in tasks { task.cancel() }
        continuation?.resume(with: result)
    }
}
