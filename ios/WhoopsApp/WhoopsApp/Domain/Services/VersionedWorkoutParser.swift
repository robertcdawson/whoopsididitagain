import Foundation

struct VersionedWorkoutParser: WorkoutParser {
    static let parserVersion = "deterministic-1.5.0"
    let catalog: MovementCatalog

    init(catalog: MovementCatalog = .standard) {
        self.catalog = catalog
    }

    func parse(rawText: String) async throws -> ParsedWorkout {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkoutValidationError.emptyRawText }

        let lines = rawText.components(separatedBy: .newlines).map(Self.normalizedLine)
        let header = Self.workoutHeader(in: lines)
        // Result metadata must never supply the planned format, round count, or time cap.
        let normalizedText = lines.enumerated().filter { index, line in
            index != header?.index && Self.reportedResult(from: line) == nil
                && Self.contextMetadata(from: line) == nil
        }.map(\.element).joined(separator: "\n")
        let format = Self.format(in: normalizedText)
        let timeCap = Self.timeCap(in: normalizedText, format: format)
        let rounds = Self.rounds(in: normalizedText)
        var blocks = [WorkBlock()]
        var ambiguities: [WorkoutAmbiguity] = []
        var context: [String] = []
        var structureNotes: [String] = []
        var reportedResults: [String] = []
        var candidateLineCount = 0

        for (index, normalizedLine) in lines.enumerated() {
            let line = normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if header?.index == index { continue }
            if let result = Self.reportedResult(from: line) {
                reportedResults.append(result)
                continue
            }
            if let metadata = Self.contextMetadata(from: line) {
                context.append(metadata)
                continue
            }
            if Self.isTimeCapInstruction(line) {
                structureNotes.append(line)
                if Self.timeCap(in: line, format: .manual) == nil {
                    ambiguities.append(
                        .init(
                            id: "unparsed-cap-\(index + 1)", line: index + 1,
                            originalText: line,
                            message:
                                "The time cap needs a single duration with valid units or mm:ss. Review it manually."
                        ))
                }
                continue
            }
            if let restSeconds = Self.restDuration(from: line) {
                guard !blocks[blocks.count - 1].movements.isEmpty else {
                    ambiguities.append(
                        WorkoutAmbiguity(
                            id: "unexpected-rest-line-\(index + 1)",
                            line: index + 1,
                            originalText: line,
                            message: "Rest appeared before any work; review the interval order."
                        )
                    )
                    continue
                }
                blocks[blocks.count - 1].followingRestSeconds = restSeconds
                blocks.append(WorkBlock())
                continue
            }
            guard !line.isEmpty, let content = Self.prescriptionContent(from: line) else {
                continue
            }
            let prescriptions = content.split(whereSeparator: { $0 == "," || $0 == ";" })
            for prescription in prescriptions {
                let prescription = prescription.trimmingCharacters(in: .whitespaces)
                guard !prescription.isEmpty else { continue }
                candidateLineCount += 1

                guard let item = catalog.match(prescription) else {
                    ambiguities.append(
                        WorkoutAmbiguity(
                            id: "unrecognized-line-\(index + 1)-\(candidateLineCount)",
                            line: index + 1,
                            originalText: prescription,
                            message: "Movement or instruction not recognized; review it manually."
                        )
                    )
                    blocks[blocks.count - 1].movements.append(
                        Self.manualMovement(line: prescription, index: index)
                    )
                    continue
                }

                let quantities = Self.quantities(in: prescription)
                if quantities.hasNoPrescription || quantities.hasAmbiguousNumbers {
                    ambiguities.append(
                        WorkoutAmbiguity(
                            id: "missing-quantity-\(index + 1)-\(candidateLineCount)",
                            line: index + 1,
                            originalText: prescription,
                            message: quantities.hasAmbiguousNumbers
                                ? "A range, alternative, or negative quantity needs manual review; no value was chosen from it."
                                : "No repetitions, distance, calories, duration, or load were found."
                        )
                    )
                }
                blocks[blocks.count - 1].movements.append(
                    MovementPrescription(
                        id: UUID().uuidString.lowercased(),
                        canonicalMovementID: item.id,
                        displayName: item.canonicalName,
                        originalText: prescription,
                        repetitions: quantities.repetitions,
                        distanceMeters: quantities.distanceMeters,
                        calories: quantities.calories,
                        loadValue: quantities.loadValue,
                        loadUnit: quantities.loadUnit,
                        percentageOfOneRepMax: quantities.percentageOfOneRepMax,
                        durationSeconds: quantities.durationSeconds,
                        tempo: nil,
                        notes: ""
                    )
                )
            }
        }

        blocks.removeAll { $0.movements.isEmpty }
        let movements = blocks.flatMap(\.movements)
        guard !movements.isEmpty else { throw WorkoutValidationError.missingSegments }
        let recognizedCount = movements.filter { $0.canonicalMovementID != nil }.count
        let confidence = max(
            0.2,
            min(1, Double(recognizedCount) / Double(max(1, candidateLineCount)))
        )
        let result = ParsedWorkout(
            title: header?.title ?? Self.title(for: movements, format: format),
            rawText: rawText,
            format: format,
            timeCapSeconds: timeCap,
            intendedStimulus: stimulus(
                for: movements,
                format: format,
                timeCap: timeCap,
                context: context
            ),
            segments: Self.segments(
                from: blocks,
                format: format,
                rounds: rounds,
                timeCap: timeCap,
                context: context + structureNotes + reportedResults
            ),
            ambiguities: ambiguities,
            parserConfidence: confidence,
            parserVersion: Self.parserVersion,
            modelVersion: nil,
            reportedResult: WorkoutReportedResult.parse(rawText)
        )
        return try result.validated(catalog: catalog)
    }

    private struct WorkBlock {
        var movements: [MovementPrescription] = []
        var followingRestSeconds: Double?
    }

    private static func normalizedLine(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(
                of: #"^\s*(?:[•●▪◦‣∙·]\s*|[-*–—]\s+)"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func workoutHeader(in lines: [String]) -> (index: Int, title: String)? {
        guard
            let first = lines.enumerated().first(where: {
                !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { return nil }
        let line = first.element.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasSuffix(":"), contextMetadata(from: line) == nil,
            reportedResult(from: line) == nil,
            restDuration(from: line) == nil, !isInstructionLine(line)
        else { return nil }
        let title = String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : (first.offset, title)
    }

    private static func contextMetadata(from line: String) -> String? {
        let lower = line.lowercased()
        let prefixes = [
            "heart rate target:", "hr target:", "intensity:", "target intensity:",
            "intended rpe:", "rpe target:",
        ]
        guard prefixes.contains(where: lower.hasPrefix) else { return nil }
        return line
    }

    private static func reportedResult(from line: String) -> String? {
        guard
            line.range(
                of: #"(?i)^(?:score|result|completed)\s*:"#,
                options: .regularExpression
            ) != nil
        else { return nil }
        return "Reported result (not a prescription): \(line)"
    }

    private static func isAMRAPInstruction(_ text: String) -> Bool {
        text.range(
            of: #"(?i)\b(?:amrap|as many (?:rounds(?: and reps)?|reps|repetitions) as possible)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func restDuration(from line: String) -> Double? {
        let lower = line.lowercased()
        guard
            lower.range(
                of: #"^(?:rest|recover|recovery)\b"#,
                options: .regularExpression
            ) != nil
        else { return nil }
        return duration(in: line)
    }

    private static func segments(
        from blocks: [WorkBlock],
        format: WorkoutFormat,
        rounds: Int?,
        timeCap: Double?,
        context: [String]
    ) -> [WorkoutSegment] {
        let restValues = blocks.dropLast().compactMap(\.followingRestSeconds)
        let firstMovementID = blocks.first?.movements.first?.canonicalMovementID
        let canCoalesce =
            blocks.count > 1
            && firstMovementID != nil
            && blocks.allSatisfy {
                $0.movements.count == 1 && $0.movements[0].canonicalMovementID == firstMovementID
            }
            && restValues.count == blocks.count - 1
            && Set(restValues).count == 1
            && blocks.last?.followingRestSeconds == nil
        let notes = context.joined(separator: "\n")

        if canCoalesce {
            return [
                WorkoutSegment(
                    id: UUID().uuidString.lowercased(),
                    sequence: 1,
                    type: .work,
                    rounds: rounds,
                    durationSeconds: format == .amrap || format == .emom ? timeCap : nil,
                    restSeconds: restValues.first,
                    notes: notes,
                    movements: blocks.flatMap(\.movements)
                )
            ]
        }

        var segments: [WorkoutSegment] = []
        for (index, block) in blocks.enumerated() {
            segments.append(
                WorkoutSegment(
                    id: UUID().uuidString.lowercased(),
                    sequence: segments.count + 1,
                    type: .work,
                    rounds: blocks.count == 1 ? rounds : nil,
                    durationSeconds:
                        blocks.count == 1 && (format == .amrap || format == .emom)
                        ? timeCap : nil,
                    restSeconds: nil,
                    notes: index == 0 ? notes : "",
                    movements: block.movements
                )
            )
            if let rest = block.followingRestSeconds {
                segments.append(
                    WorkoutSegment(
                        id: UUID().uuidString.lowercased(),
                        sequence: segments.count + 1,
                        type: .rest,
                        rounds: nil,
                        durationSeconds: rest,
                        restSeconds: nil,
                        notes: "",
                        movements: []
                    )
                )
            }
        }
        return segments
    }

    private static func format(in text: String) -> WorkoutFormat {
        let lower = text.lowercased()
        if isAMRAPInstruction(lower) { return .amrap }
        if lower.contains("emom") || lower.contains("every minute") { return .emom }
        if lower.contains("for time") || lower.contains("complete for time") { return .forTime }
        if lower.components(separatedBy: .newlines).contains(where: isStrengthInstruction)
            || lower.range(of: #"(?m)^\s*\d+\s+sets?\b"#, options: .regularExpression) != nil
        {
            return .strength
        }
        if lower.contains("rounds") { return .rounds }
        if lower.contains("interval") || lower.contains("rest") { return .intervals }
        if lower.contains("build to") || lower.contains("one rep max") || lower.contains("1rm") {
            return .strength
        }
        return .manual
    }

    private static func timeCap(in text: String, format: WorkoutFormat) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        if let cap = lines.first(where: isTimeCapInstruction) { return duration(in: cap) }
        guard format == .amrap || format == .emom else { return nil }
        for line in lines
        where isAMRAPInstruction(line)
            || line.range(of: #"(?i)\b(?:emom|every minute)\b"#, options: .regularExpression) != nil
        {
            if let seconds = duration(in: line) { return seconds }
            // Preserve the established shorthand AMRAP 8 / EMOM 8 (minutes).
            if let minutes = captureDouble(
                #"(?i)^\s*(?:amrap|emom)\s+(\d+(?:\.\d+)?)\s*:?[ \t]*$"#, in: line)
            {
                return validDuration(minutes * 60)
            }
        }
        return nil
    }

    private static func rounds(in text: String) -> Int? {
        positiveInteger(captureDouble(#"(?im)^\s*(\d+)\s+(?:rounds?|sets?)\b"#, in: text))
    }

    private static func isTimeCapInstruction(_ line: String) -> Bool {
        line.range(of: #"(?i)^\s*time\s*cap\b"#, options: .regularExpression) != nil
    }

    private static func isStrengthInstruction(_ line: String) -> Bool {
        line.range(
            of: #"(?i)^\s*(?:strength|strength work|weightlifting)\s*(?::|$)"#,
            options: .regularExpression) != nil
    }

    private static func isInstructionLine(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        return lower == "complete for time"
            || lower == "for time"
            || isTimeCapInstruction(lower)
            || isStrengthInstruction(lower)
            || isAMRAPInstruction(lower)
            || lower.contains("emom")
            || lower.range(
                of: #"^(\d+\s+)?(rounds?|sets?|amrap|emom)\b"#, options: .regularExpression)
                != nil
    }

    private static func prescriptionContent(from line: String) -> String? {
        let lower = line.lowercased()
        if isTimeCapInstruction(line) { return nil }
        if let colon = line.indices.first(where: {
            line[$0] == ":"
                && !(line.index(after: $0) < line.endIndex
                    && line[line.index(after: $0)].isNumber
                    && $0 > line.startIndex && line[line.index(before: $0)].isNumber)
        }) {
            let prefix = String(line[..<colon]).lowercased()
            if prefix.contains("round") || isAMRAPInstruction(prefix) || prefix.contains("emom")
                || isStrengthInstruction(prefix)
                || prefix.range(of: #"^\d+\s+sets?\b"#, options: .regularExpression) != nil
            {
                let content = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? nil : content
            }
        }
        if lower.range(of: #"^\d+\s+(?:rounds?|sets?)\s+"#, options: .regularExpression) != nil {
            let content = line.replacingOccurrences(
                of: #"(?i)^\d+\s+(?:rounds?|sets?)\s+(?:of\s+)?"#,
                with: "",
                options: .regularExpression
            )
            return isInstructionLine(content) ? nil : content
        }
        return isInstructionLine(line) ? nil : line
    }

    private static func title(
        for movements: [MovementPrescription],
        format: WorkoutFormat
    ) -> String {
        let names = movements.compactMap { movement -> String? in
            guard movement.canonicalMovementID != nil else { return nil }
            return movement.displayName
        }.reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
        if names.isEmpty { return "Manual workout" }
        let movementTitle = names.prefix(3).joined(separator: " + ")
        return "\(movementTitle) · \(format.displayName)"
    }

    func stimulus(
        for movements: [MovementPrescription],
        format: WorkoutFormat,
        timeCap: Double?,
        context: [String]
    ) -> WorkoutStimulus {
        let items = movements.compactMap { movement in
            movement.canonicalMovementID.flatMap(catalog.item)
        }
        let hasAerobic = items.contains { $0.tags.contains(.aerobic) }
        let hasLoadedStrength = movements.contains { $0.loadValue != nil }
        let primary: String
        if hasAerobic && hasLoadedStrength {
            primary = "Mixed-modal strength endurance"
        } else if hasAerobic {
            primary =
                format == .intervals || format == .emom
                ? "Aerobic intervals" : "Aerobic conditioning"
        } else if hasLoadedStrength {
            primary = format == .strength ? "Strength" : "Strength endurance"
        } else {
            primary = "Mixed-modal conditioning"
        }
        var secondary: [String] = []
        if items.contains(where: { $0.tags.contains(.overhead) }) {
            secondary.append("Overhead work")
        }
        if items.contains(where: { $0.tags.contains(.gripIntensive) }) {
            secondary.append("Grip endurance")
        }
        for item in context where !secondary.contains(item) {
            secondary.append(item)
        }
        let estimatedMinutes = timeCap.map { max(1, ($0 / 60).rounded()) }
        return WorkoutStimulus(
            primary: primary,
            secondary: secondary,
            estimatedDurationMinimumMinutes: estimatedMinutes ?? (format == .forTime ? 12 : nil),
            estimatedDurationMaximumMinutes: estimatedMinutes ?? (format == .forTime ? 30 : nil)
        )
    }

    private static func manualMovement(line: String, index: Int) -> MovementPrescription {
        let quantities = quantities(in: line)
        return MovementPrescription(
            id: UUID().uuidString.lowercased(),
            canonicalMovementID: nil,
            displayName: line,
            originalText: line,
            repetitions: quantities.repetitions,
            distanceMeters: quantities.distanceMeters,
            calories: quantities.calories,
            loadValue: quantities.loadValue,
            loadUnit: quantities.loadUnit,
            percentageOfOneRepMax: quantities.percentageOfOneRepMax,
            durationSeconds: quantities.durationSeconds,
            tempo: nil,
            notes: "Review line \(index + 1)"
        )
    }

    private struct Quantities {
        let repetitions: Int?
        let distanceMeters: Int?
        let calories: Int?
        let loadValue: Double?
        let loadUnit: String?
        let percentageOfOneRepMax: Double?
        let durationSeconds: Double?
        let hasAmbiguousNumbers: Bool

        var hasNoPrescription: Bool {
            repetitions == nil && distanceMeters == nil && calories == nil && loadValue == nil
                && percentageOfOneRepMax == nil && durationSeconds == nil
        }
    }

    private static func quantities(in line: String) -> Quantities {
        let original = line
        let line = removingAmbiguousNumbers(line)
        let distanceValue = captureDouble(
            #"(?i)(\d+(?:\.\d+)?)\s*(km|kilometers?|m|meters?)\b"#,
            in: line
        )
        let distanceUnit = captureString(
            #"(?i)\d+(?:\.\d+)?\s*(km|kilometers?|m|meters?)\b"#,
            in: line
        )?.lowercased()
        let distanceMeters = positiveInteger(
            distanceValue.map {
                $0 * ((distanceUnit?.hasPrefix("k") == true) ? 1_000 : 1)
            }, maximum: 1_000_000)
        let calories = captureDouble(#"(?i)(\d+)\s*(?:cal|cals|calories)\b"#, in: line)
            .flatMap { positiveInteger($0) }
        let loadValue = captureDouble(
            #"(?i)(\d+(?:\.\d+)?)\s*(?:(?:lbs?|kgs?)\b|#(?!\w))"#,
            in: line
        )
        let loadUnitRaw = captureString(
            #"(?i)\d+(?:\.\d+)?\s*((?:lbs?|kgs?)\b|#(?!\w))"#,
            in: line
        )?.lowercased()
        let loadUnit: String? = loadUnitRaw.map { $0.hasPrefix("k") ? "kg" : "lb" }
        let percentage = captureDouble(#"(?i)(\d+(?:\.\d+)?)\s*%"#, in: line)
        let durationSeconds = duration(in: line)
        let repetitions = captureDouble(
            #"(?i)^\s*(\d+)\s+(?!m\b|met(?:er|re)s?\b|k(?:m|ilomet(?:er|re)s?)\b|cal|s\b|sec|mins?\b|minutes?\b|h\b|hours?\b|lbs?\b|kgs?\b)"#,
            in: line
        ).flatMap { positiveInteger($0) }
        return Quantities(
            repetitions: repetitions,
            distanceMeters: distanceMeters,
            calories: calories,
            loadValue: loadValue,
            loadUnit: loadValue == nil ? nil : loadUnit,
            percentageOfOneRepMax: percentage.flatMap { $0 <= 100 ? $0 : nil },
            durationSeconds: durationSeconds,
            hasAmbiguousNumbers: original != line
        )
    }

    private static func removingAmbiguousNumbers(_ text: String) -> String {
        text.replacingOccurrences(
            of:
                #"\d+(?:\.\d+)?[ \t]*(?:/|[-–])[ \t]*\d+(?:\.\d+)?(?:[ \t]*(?:/|[-–])[ \t]*\d+(?:\.\d+)?)*"#,
            with: "[review quantity]", options: .regularExpression
        ).replacingOccurrences(
            of: #"(?<!\w)-[ \t]*\d+(?:\.\d+)?"#,
            with: "[review quantity]", options: .regularExpression)
    }

    /// Literal source tokens for the staged parser. Apple classifies line roles only; it never
    /// supplies quantities. Unit conversion and bounds are validated by the extraction assembler.
    static func quotedQuantities(in text: String) -> [String: String] {
        let text = removingAmbiguousNumbers(normalizedLine(text))
        let patterns: [String: String] = [
            "reps":
                #"(?i)^\s*(\d+)\s+(?!m\b|met(?:er|re)s?\b|k(?:m|ilomet(?:er|re)s?)\b|cal|s\b|sec|mins?\b|minutes?\b|h\b|hours?\b|lbs?\b|kgs?\b|rounds?\b|sets?\b|efforts?\b)"#,
            "distance": #"(?i)(\d+(?:\.\d+)?\s*(?:km|kilomet(?:er|re)s?|m|met(?:er|re)s?)\b)"#,
            "calories": #"(?i)(\d+\s*(?:cal|cals|calories)\b)"#,
            "load": #"(?i)(\d+(?:\.\d+)?\s*(?:(?:lbs?|kgs?|pounds?|kilograms?)\b|#(?!\w)))"#,
            "percentage": #"(\d+(?:\.\d+)?\s*%)"#,
            "rounds": #"(?i)^\s*(\d+\s*(?:rounds?|sets?|efforts?)\b)"#,
            "duration":
                #"(?i)(?<![\d.:])(\d+:\d{2})(?![\d:])|(?<![\d.])(\d+(?:\.\d+)?[ \t]*(?:s|sec|secs|seconds?|min|mins|minutes?|h|hours?)\b)"#,
        ]
        return patterns.reduce(into: [:]) { result, item in
            if let quote = captureGroups(item.value, in: text).first(where: { !$0.isEmpty }) {
                result[item.key] = quote
            }
        }
    }

    private static func positiveInteger(_ value: Double?, maximum: Int = 100_000) -> Int? {
        guard let value, value.isFinite, value >= 1, value <= Double(maximum) else { return nil }
        return Int(value.rounded())
    }

    private static func duration(in text: String) -> Double? {
        guard removingAmbiguousNumbers(text) == text else { return nil }
        let clock = captureGroups(#"(?<![\d.:])(\d+):(\d{2})(?![\d:])"#, in: text)
        if clock.count == 2 {
            guard let minutes = Double(clock[0]), let seconds = Double(clock[1]), seconds < 60
            else { return nil }
            return validDuration(minutes * 60 + seconds)
        }
        let quantity = captureGroups(
            #"(?i)(?<![\d.])(\d+(?:\.\d+)?)[ \t]*(s|sec|secs|seconds?|min|mins|minutes?|h|hours?)\b"#,
            in: text)
        guard quantity.count == 2, let value = Double(quantity[0]) else { return nil }
        let unit = quantity[1].lowercased()
        let multiplier = unit.hasPrefix("h") ? 3_600.0 : unit.hasPrefix("m") ? 60.0 : 1.0
        return validDuration(value * multiplier)
    }

    private static func validDuration(_ seconds: Double) -> Double? {
        seconds.isFinite && seconds > 0 && seconds <= 86_400 ? seconds : nil
    }

    private static func captureDouble(_ pattern: String, in text: String) -> Double? {
        guard let value = captureGroups(pattern, in: text).first.flatMap(Double.init),
            value.isFinite, value > 0, value <= 100_000
        else { return nil }
        return value
    }

    private static func captureString(_ pattern: String, in text: String) -> String? {
        captureGroups(pattern, in: text).first
    }

    private static func captureGroups(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return [] }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
