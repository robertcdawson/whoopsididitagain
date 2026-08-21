import Foundation

struct VersionedWorkoutParser: WorkoutParser {
    static let parserVersion = "deterministic-1.2.0"
    let catalog: MovementCatalog

    init(catalog: MovementCatalog = .standard) {
        self.catalog = catalog
    }

    func parse(rawText: String) async throws -> ParsedWorkout {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkoutValidationError.emptyRawText }

        let lines = rawText.components(separatedBy: .newlines).map(Self.normalizedLine)
        let normalizedText = lines.joined(separator: "\n")
        let format = Self.format(in: normalizedText)
        let timeCap = Self.timeCap(in: normalizedText, format: format)
        let rounds = Self.rounds(in: normalizedText)
        let header = Self.workoutHeader(in: lines)
        var blocks = [WorkBlock()]
        var ambiguities: [WorkoutAmbiguity] = []
        var context: [String] = []
        var candidateLineCount = 0

        for (index, normalizedLine) in lines.enumerated() {
            let line = normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if header?.index == index { continue }
            if let metadata = Self.contextMetadata(from: line) {
                context.append(metadata)
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
                if quantities.hasNoPrescription {
                    ambiguities.append(
                        WorkoutAmbiguity(
                            id: "missing-quantity-\(index + 1)-\(candidateLineCount)",
                            line: index + 1,
                            originalText: prescription,
                            message:
                                "No repetitions, distance, calories, duration, or load were found."
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
                context: context
            ),
            ambiguities: ambiguities,
            parserConfidence: confidence,
            parserVersion: Self.parserVersion,
            modelVersion: nil
        )
        return try result.validated(catalog: catalog)
    }

    private struct WorkBlock {
        var movements: [MovementPrescription] = []
        var followingRestSeconds: Int?
    }

    private static func normalizedLine(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
    }

    private static func workoutHeader(in lines: [String]) -> (index: Int, title: String)? {
        guard
            let first = lines.enumerated().first(where: {
                !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { return nil }
        let line = first.element.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasSuffix(":"), contextMetadata(from: line) == nil,
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

    private static func restDuration(from line: String) -> Int? {
        let lower = line.lowercased()
        guard
            lower.range(
                of: #"^(?:rest|recover|recovery)\b"#,
                options: .regularExpression
            ) != nil
        else { return nil }
        let clockGroups = captureGroups(#"(?i)\b(\d+):(\d{2})\b"#, in: line)
        if clockGroups.count == 2, let minutes = Int(clockGroups[0]),
            let seconds = Int(clockGroups[1])
        {
            return minutes * 60 + seconds
        }
        if let seconds = captureDouble(#"(?i)(\d+)\s*(?:sec|secs|seconds?)\b"#, in: line) {
            return Int(seconds)
        }
        if let minutes = captureDouble(#"(?i)(\d+(?:\.\d+)?)\s*(?:min|minutes?)\b"#, in: line) {
            return Int((minutes * 60).rounded())
        }
        return nil
    }

    private static func segments(
        from blocks: [WorkBlock],
        format: WorkoutFormat,
        rounds: Int?,
        timeCap: Int?,
        context: [String]
    ) -> [WorkoutSegment] {
        let restValues = blocks.dropLast().compactMap(\.followingRestSeconds)
        let canCoalesce =
            blocks.count > 1
            && blocks.allSatisfy { $0.movements.count == 1 }
            && restValues.count == blocks.count - 1
            && Set(restValues).count == 1
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
        if lower.contains("amrap") { return .amrap }
        if lower.contains("emom") || lower.contains("every minute") { return .emom }
        if lower.contains("for time") || lower.contains("complete for time") { return .forTime }
        if lower.contains("rounds") { return .rounds }
        if lower.contains("interval") || lower.contains("rest") { return .intervals }
        if lower.contains("build to") || lower.contains("one rep max") || lower.contains("1rm") {
            return .strength
        }
        return .manual
    }

    private static func timeCap(in text: String, format: WorkoutFormat) -> Int? {
        let patterns: [String]
        switch format {
        case .amrap, .emom:
            patterns = [
                #"(?i)(?:amrap|emom)[ \t]*(\d+)"#,
                #"(?i)(\d+)[ \t]*(?:min|minutes)"#,
            ]
        default:
            patterns = [#"(?i)time\s*cap:?\s*(\d+)\s*(?:min|minutes)?"#]
        }
        for pattern in patterns {
            if let minutes = captureDouble(pattern, in: text) { return Int(minutes * 60) }
        }
        return nil
    }

    private static func rounds(in text: String) -> Int? {
        captureDouble(#"(?i)(\d+)\s+rounds?"#, in: text).map(Int.init)
    }

    private static func isInstructionLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower == "complete for time"
            || lower == "for time"
            || lower.hasPrefix("time cap")
            || lower.contains("amrap")
            || lower.contains("emom")
            || lower.range(of: #"^(\d+\s+)?(rounds?|amrap|emom)\b"#, options: .regularExpression)
                != nil
    }

    private static func prescriptionContent(from line: String) -> String? {
        let lower = line.lowercased()
        if let colon = line.firstIndex(of: ":") {
            let prefix = String(line[..<colon]).lowercased()
            if prefix.contains("round") || prefix.contains("amrap") || prefix.contains("emom")
                || prefix.contains("time cap")
            {
                let content = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                return content.isEmpty ? nil : content
            }
        }
        if lower.range(of: #"^\d+\s+rounds?\s+"#, options: .regularExpression) != nil {
            let content = line.replacingOccurrences(
                of: #"(?i)^\d+\s+rounds?\s+"#,
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

    private func stimulus(
        for movements: [MovementPrescription],
        format: WorkoutFormat,
        timeCap: Int?,
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
        let estimatedMinutes = timeCap.map { max(1, $0 / 60) }
        return WorkoutStimulus(
            primary: primary,
            secondary: secondary,
            estimatedDurationMinimumMinutes: estimatedMinutes ?? (format == .forTime ? 12 : nil),
            estimatedDurationMaximumMinutes: estimatedMinutes ?? (format == .forTime ? 30 : nil)
        )
    }

    private static func manualMovement(line: String, index: Int) -> MovementPrescription {
        MovementPrescription(
            id: UUID().uuidString.lowercased(),
            canonicalMovementID: nil,
            displayName: line,
            originalText: line,
            repetitions: nil,
            distanceMeters: nil,
            calories: nil,
            loadValue: nil,
            loadUnit: nil,
            percentageOfOneRepMax: nil,
            durationSeconds: nil,
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
        let durationSeconds: Int?

        var hasNoPrescription: Bool {
            repetitions == nil && distanceMeters == nil && calories == nil && loadValue == nil
                && percentageOfOneRepMax == nil && durationSeconds == nil
        }
    }

    private static func quantities(in line: String) -> Quantities {
        let distanceValue = captureDouble(
            #"(?i)(\d+(?:\.\d+)?)\s*(km|kilometers?|m|meters?)\b"#,
            in: line
        )
        let distanceUnit = captureString(
            #"(?i)\d+(?:\.\d+)?\s*(km|kilometers?|m|meters?)\b"#,
            in: line
        )?.lowercased()
        let distanceMeters = distanceValue.map {
            Int(($0 * ((distanceUnit?.hasPrefix("k") == true) ? 1_000 : 1)).rounded())
        }
        let calories = captureDouble(#"(?i)(\d+)\s*(?:cal|cals|calories)\b"#, in: line)
            .map(Int.init)
        let loadValue = captureDouble(
            #"(?i)(\d+(?:\.\d+)?)\s*(?:lb|lbs|kg|kgs|#)\b"#,
            in: line
        )
        let loadUnitRaw = captureString(
            #"(?i)\d+(?:\.\d+)?\s*(lb|lbs|kg|kgs|#)\b"#,
            in: line
        )?.lowercased()
        let loadUnit: String? = loadUnitRaw.map { $0.hasPrefix("k") ? "kg" : "lb" }
        let percentage = captureDouble(#"(?i)(\d+(?:\.\d+)?)\s*%"#, in: line)
        let colonMinutes = captureGroups(#"(?i)\b(\d+):(\d{2})\b"#, in: line)
        let durationSeconds: Int?
        if colonMinutes.count == 2,
            let minutes = Int(colonMinutes[0]), let seconds = Int(colonMinutes[1])
        {
            durationSeconds = minutes * 60 + seconds
        } else if let seconds = captureDouble(#"(?i)(\d+)\s*(?:sec|seconds?)\b"#, in: line) {
            durationSeconds = Int(seconds)
        } else {
            durationSeconds = nil
        }
        let repetitions = captureDouble(
            #"(?i)^\s*(\d+)\s+(?!m\b|meters?\b|km\b|cal|sec|minutes?\b|lb\b|kg\b)"#,
            in: line
        ).map(Int.init)
        return Quantities(
            repetitions: repetitions,
            distanceMeters: distanceMeters,
            calories: calories,
            loadValue: loadValue,
            loadUnit: loadUnit,
            percentageOfOneRepMax: percentage,
            durationSeconds: durationSeconds
        )
    }

    private static func captureDouble(_ pattern: String, in text: String) -> Double? {
        captureGroups(pattern, in: text).first.flatMap(Double.init)
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
