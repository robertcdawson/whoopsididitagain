import Foundation

/// Deterministic parser for PT protocol sheets. Every line is preserved as an item,
/// quantities are extracted only when they are explicit, and an unmatched movement
/// surfaces catalog candidates or a new-movement marker instead of a guess.
struct DeterministicProtocolParser: ProtocolParser {
    static let parserVersion = "protocol-1.0.0"
    let catalog: MovementCatalog

    init(catalog: MovementCatalog = .standard) {
        self.catalog = catalog
    }

    func parse(rawText: String, source: ProtocolSource) async throws -> ParsedProtocol {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProtocolParseError.emptyText }

        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.precomposedStringWithCompatibilityMapping }
        var title: String?
        var phaseNumber: Int?
        var phaseCount: Int?
        var unlockMilestone: String?
        var defaultCadence: ProtocolCadence?
        var items: [ParsedProtocolItem] = []

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let phase = Self.phase(in: line) {
                phaseNumber = phase.number
                phaseCount = phase.count
                if let milestone = Self.unlockMilestone(in: line) {
                    unlockMilestone = milestone
                }
                continue
            }
            if title == nil, items.isEmpty, line.hasSuffix(":") {
                let candidate = String(line.dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    title = candidate
                    continue
                }
            }
            if let cadence = Self.wholeLineCadence(line) {
                defaultCadence = cadence
                continue
            }
            items.append(Self.item(from: line, lineNumber: index + 1, catalog: catalog))
        }

        guard !items.isEmpty else { throw ProtocolParseError.noItemsFound }
        let matchedCount = items.filter { item in
            if case .matched = item.resolution { return true }
            return false
        }.count
        let confidence = max(0.2, min(1, Double(matchedCount) / Double(items.count)))
        return ParsedProtocol(
            id: UUID().uuidString.lowercased(),
            title: title ?? "PT protocol",
            rawText: rawText,
            source: source,
            phaseNumber: phaseNumber,
            phaseCount: phaseCount,
            unlockMilestone: unlockMilestone,
            defaultCadence: defaultCadence,
            items: items,
            parserConfidence: confidence,
            parserVersion: Self.parserVersion
        )
    }

    // MARK: - Line classification

    private static func phase(in line: String) -> (number: Int, count: Int?)? {
        let groups = captureGroups(#"(?i)\bphase\s+(\d+)(?:\s+of\s+(\d+))?\b"#, in: line)
        guard let first = groups.first, let number = Int(first) else { return nil }
        let count = groups.count > 1 ? Int(groups[1]) : nil
        return (number, count)
    }

    private static func unlockMilestone(in line: String) -> String? {
        guard let raw = captureGroups(#"(?i)\buntil\s+(.+)$"#, in: line).first else { return nil }
        let cleaned = raw.replacingOccurrences(
            of: #"(?i)\s*(?:unlocks?|is unlocked)?[\s.·:;,–—-]*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static let weeklyCadencePattern =
        #"(?i)\b(\d+)\s*(?:[x×]|times)\s*(?:/\s*|per\s+|a\s+|each\s+)?(?:week|wk)\b"#
    private static let dailyCadencePattern =
        #"(?i)\b(?:daily|every\s+day|(?:twice|\d+\s*[x×])\s*(?:/\s*|per\s+|a\s+)?day)\b"#

    private static func wholeLineCadence(_ line: String) -> ProtocolCadence? {
        var working = line
        let cadence = takeCadence(from: &working)
        guard cadence != nil else { return nil }
        let leftover = working.replacingOccurrences(
            of: #"[\s\-–—·•,;:.()]+"#,
            with: "",
            options: .regularExpression
        )
        return leftover.isEmpty ? cadence : nil
    }

    private static func takeCadence(from working: inout String) -> ProtocolCadence? {
        if let groups = takeGroups(weeklyCadencePattern, from: &working),
            let count = groups.first.flatMap(Int.init)
        {
            return .timesPerWeek(count)
        }
        if takeGroups(dailyCadencePattern, from: &working) != nil {
            return .daily
        }
        return nil
    }

    // MARK: - Item extraction

    private static func item(
        from line: String,
        lineNumber: Int,
        catalog: MovementCatalog
    ) -> ParsedProtocolItem {
        var working = line
        _ = takeGroups(#"^\s*(?:\d+[.)]|[-–—•*·]+)\s+"#, from: &working)
        let cadence = takeCadence(from: &working)

        var sets: Int?
        var repetitions: Int?
        var durationSeconds: Int?
        if let groups = takeGroups(
            #"(?i)(\d+)\s*(?:sets?\s*(?:of|[x×])?|[x×])\s*(\d+)\s*(?:s|sec|secs|seconds?)\b"#,
            from: &working
        ) {
            sets = Int(groups[0])
            durationSeconds = Int(groups[1])
        } else if let groups = takeGroups(
            #"(?i)(\d+)\s*(?:sets?\s*(?:of|[x×])?\s*|[x×]\s*)(\d+)\b(?:\s*reps?\b)?"#,
            from: &working
        ) {
            sets = Int(groups[0])
            repetitions = Int(groups[1])
        }
        if durationSeconds == nil,
            let groups = takeGroups(
                #"(?i)(\d+)\s*(?:s|sec|secs|seconds?)\b(?:\s*holds?\b)?"#,
                from: &working
            )
        {
            durationSeconds = Int(groups[0])
        }
        if repetitions == nil,
            let groups = takeGroups(#"(?i)(\d+)\s*reps?\b"#, from: &working)
        {
            repetitions = Int(groups[0])
        }

        var loadValue: Double?
        var loadUnit: String?
        if let groups = takeGroups(
            #"(?i)(\d+(?:\.\d+)?)\s*(lb|lbs|kg|kgs|#)\b"#,
            from: &working
        ) {
            loadValue = Double(groups[0])
            loadUnit = groups[1].lowercased().hasPrefix("k") ? "kg" : "lb"
        }

        var notes = ""
        if let groups = takeGroups(
            #"(?i)\b(?:each|per|both)\s+(sides?|legs?|arms?)\b"#,
            from: &working
        ) {
            notes = "Each \(groups[0].lowercased())"
        }
        if sets == nil, repetitions == nil,
            let groups = takeGroups(#"^\s*(\d+)\s+"#, from: &working)
        {
            repetitions = Int(groups[0])
        }

        let movementText = cleanedMovementText(working, fallback: line)
        let resolution: ProtocolItemResolution
        if let matched = catalog.match(movementText) {
            resolution = .matched(movementID: matched.id, name: matched.canonicalName)
        } else {
            let candidates = candidateIDs(for: movementText, in: catalog)
            resolution =
                candidates.isEmpty
                ? .unknown : .ambiguous(candidateIDs: candidates)
        }
        return ParsedProtocolItem(
            id: UUID().uuidString.lowercased(),
            line: lineNumber,
            originalText: line,
            movementText: movementText,
            sets: sets,
            repetitions: repetitions,
            durationSeconds: durationSeconds,
            loadValue: loadValue,
            loadUnit: loadUnit,
            cadence: cadence,
            notes: notes,
            resolution: resolution
        )
    }

    private static func cleanedMovementText(_ value: String, fallback: String) -> String {
        var name = value.replacingOccurrences(
            of: #"["“”'’]"#,
            with: "",
            options: .regularExpression
        )
        name = name.replacingOccurrences(
            of: #"^[\s\-–—·•,;:.()]+|[\s\-–—·•,;:.()]+$"#,
            with: "",
            options: .regularExpression
        )
        name = name.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return name.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : name
    }

    // MARK: - Candidate matching

    /// Word-level overlap against catalog names and aliases. A partial overlap is a
    /// candidate the user must confirm, never an automatic match; only
    /// `MovementCatalog.match` (exact name or alias) resolves without a tap.
    static func candidateIDs(for text: String, in catalog: MovementCatalog) -> [String] {
        let queryTokens = matchTokens(text)
        guard !queryTokens.isEmpty else { return [] }
        let scored = catalog.items.compactMap { item -> (id: String, score: Int, name: String)? in
            let itemTokens = matchTokens(
                ([item.canonicalName] + item.aliases).joined(separator: " ")
            )
            let score = queryTokens.filter { query in
                itemTokens.contains { tokensAlign(query, $0) }
            }.count
            guard score > 0 else { return nil }
            return (item.id, score, item.canonicalName)
        }
        return scored.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.name < rhs.name
        }
        .prefix(3)
        .map(\.id)
    }

    private static let matchStopWords: Set<String> = [
        "the", "and", "with", "of", "a", "an", "to", "for", "per", "each", "hold", "holds",
    ]

    private static func matchTokens(_ value: String) -> [String] {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !matchStopWords.contains($0) && Int($0) == nil }
            .map(stem)
    }

    private static func stem(_ token: String) -> String {
        token.count > 3 && token.hasSuffix("s") ? String(token.dropLast()) : token
    }

    private static func tokensAlign(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs
            || (min(lhs.count, rhs.count) >= 3 && (lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)))
    }

    // MARK: - Regex helpers

    /// Returns the first match's capture groups and removes the matched range from `text`.
    private static func takeGroups(_ pattern: String, from text: inout String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[groupRange])
        }
        if let fullRange = Range(match.range, in: text) {
            text.replaceSubrange(fullRange, with: " ")
        }
        return groups
    }

    private static func captureGroups(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return [] }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[groupRange])
        }
    }
}
