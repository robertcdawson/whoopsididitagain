import SwiftUI

/// Tap-chip review of a parsed PT protocol. Ambiguous rows resolve by tapping a
/// candidate chip, unknown rows by one tap into the movement library, cadence by
/// preset chips, and the restriction check runs before anything can be saved.
struct ProtocolParseReviewView: View {
    @FocusState private var focusedField: UUID?
    let parsed: ParsedProtocol
    let scalingEngine: any WorkoutScalingEngine
    let movementLibrary: any MovementLibraryRepository
    let protocolRepository: any ProtocolRepository
    let restrictions: [RestrictionProfile]
    let onSaved: () async -> Void

    @State private var title: String
    @State private var items: [ProtocolReviewItem]
    @State private var evaluation: WorkoutEvaluation?
    @State private var definitionNames: [String: String] = [:]
    @State private var addedMovementIDs: Set<String> = []
    @State private var lastDropped: ProtocolReviewItem?
    @State private var lastDroppedIndex = 0
    @State private var undoTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AppStorage("journalLeftHanded") private var leftHanded = false

    init(
        parsed: ParsedProtocol,
        scalingEngine: any WorkoutScalingEngine,
        movementLibrary: any MovementLibraryRepository,
        protocolRepository: any ProtocolRepository,
        restrictions: [RestrictionProfile],
        onSaved: @escaping () async -> Void
    ) {
        self.parsed = parsed
        self.scalingEngine = scalingEngine
        self.movementLibrary = movementLibrary
        self.protocolRepository = protocolRepository
        self.restrictions = restrictions
        self.onSaved = onSaved
        _title = State(initialValue: parsed.title)
        _items = State(
            initialValue: parsed.items.map {
                ProtocolReviewItem(parsed: $0, defaultCadence: parsed.defaultCadence ?? .daily)
            }
        )
    }

    private var unresolvedCount: Int { items.filter(\.needsAttention).count }

    private var journalRowInsets: EdgeInsets {
        EdgeInsets(top: 7, leading: leftHanded ? 22 : 56, bottom: 7, trailing: leftHanded ? 56 : 22)
    }

    var body: some View {
        ZStack {
            JournalPaperBackground()
            JournalList(showsMarginRule: true) {
                Group {
                    header
                    headline
                    ForEach($items) { $item in
                        ProtocolReviewItemCard(
                            item: $item,
                            candidateName: { candidateName(for: $0) },
                            wasAddedToLibrary: item.canonicalMovementID.map {
                                addedMovementIDs.contains($0)
                            } ?? false,
                            onAddToLibrary: { Task { await addToLibrary(itemID: item.id) } }
                        )
                        .listRowInsets(journalRowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                drop(itemID: item.id)
                            } label: {
                                Label("Drop", systemImage: "trash")
                            }
                        }
                    }
                    restrictionRow
                    footerNote
                }
                .listRowInsets(journalRowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .formKeyboardScope($focusedField)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            if let movements = try? await movementLibrary.movements(includeArchived: false) {
                definitionNames = Dictionary(
                    uniqueKeysWithValues: movements.map { ($0.id, $0.canonicalName) }
                )
            }
        }
        .task(id: items.compactMap(\.canonicalMovementID)) {
            guard let plan = ProtocolRestrictionCheck.evaluationPlan(title: title, items: items)
            else {
                evaluation = nil
                return
            }
            evaluation = await scalingEngine.evaluate(plan: plan, restrictions: restrictions)
        }
        .alert("Couldn't save the protocol", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("new protocol")
                    .font(.journal(.body))
                Spacer()
                Text(parsed.source.displayName)
                    .font(.journal(.body))
            }
            .foregroundStyle(Color.journalInk)
            TextField("protocol title", text: $title)
                .formKeyboardField()
                .font(.journal(.title3, weight: .semibold))
                .foregroundStyle(Color.journalInk)
                .accessibilityIdentifier("protocol-title")
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("found \(items.count) \(items.count == 1 ? "movement" : "movements").")
                .font(.journal(.title2, weight: .bold))
            Text(attentionLine)
                .font(.journal(.body))
                .italic()
        }
        .foregroundStyle(Color.journalInk)
        .accessibilityIdentifier("protocol-review-headline")
    }

    private var attentionLine: String {
        switch unresolvedCount {
        case 0: "all matched."
        case 1: "one needs your eyes."
        default: "\(unresolvedCount) need your eyes."
        }
    }

    @ViewBuilder
    private var restrictionRow: some View {
        if items.contains(where: \.isResolved) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                switch restrictionState {
                case .clear:
                    DrawnCheckmarkView()
                    Text("all clear — checked against your restrictions.")
                        .font(.journal(.body))
                        .foregroundStyle(Color.journalInk)
                case .caution(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.journalAmber)
                    Text(message)
                        .font(.journal(.callout))
                        .foregroundStyle(Color.journalAmber)
                case .hard(let message):
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Color.journalRedPen)
                    Text(message)
                        .font(.journal(.callout))
                        .foregroundStyle(Color.journalRedPen)
                case .checking:
                    ProgressView()
                    Text("checking restrictions…")
                        .font(.journal(.callout))
                        .foregroundStyle(Color.journalInk.opacity(0.55))
                case .noRestrictions:
                    Text("no active restrictions to check against.")
                        .font(.journal(.callout))
                        .foregroundStyle(Color.journalInk.opacity(0.55))
                }
            }
            .accessibilityIdentifier("protocol-restriction-check")
        } else {
            Text("resolve the flagged rows to run the restriction check.")
                .font(.journal(.callout))
                .foregroundStyle(Color.journalInk.opacity(0.55))
        }
    }

    private enum RestrictionState {
        case checking
        case clear
        case caution(String)
        case hard(String)
        case noRestrictions
    }

    private var restrictionState: RestrictionState {
        guard restrictions.contains(where: \.isActive) else { return .noRestrictions }
        guard let evaluation else { return .checking }
        if let hard = evaluation.conflicts.first(where: { $0.severity == .hard }) {
            return .hard("must modify: \(hard.explanation)")
        }
        if let caution = evaluation.conflicts.first {
            let extra = evaluation.conflicts.count - 1
            let suffix = extra > 0 ? " (+\(extra) more to review)" : ""
            return .caution(caution.explanation + suffix)
        }
        return .clear
    }

    private var footerNote: some View {
        Text(footerText)
            .font(.journal(.subheadline))
            .foregroundStyle(Color.journalInk.opacity(0.55))
    }

    private var footerText: String {
        var parts: [String] = []
        if let phase = phaseText { parts.append(phase) }
        parts.append("swipe any row left to drop it.")
        return parts.joined(separator: " ")
    }

    private var phaseText: String? {
        guard let phaseNumber = parsed.phaseNumber else { return nil }
        var text = "phase \(phaseNumber)"
        if let phaseCount = parsed.phaseCount { text += " of \(phaseCount)" }
        if let milestone = parsed.unlockMilestone {
            text += " · runs until \(milestone) unlocks."
        } else {
            text += "."
        }
        return text
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let dropped = lastDropped {
                Button {
                    undoDrop(dropped)
                } label: {
                    Label(
                        "dropped \"\(dropped.displayName)\" — undo",
                        systemImage: "arrow.uturn.backward"
                    )
                    .font(.journal(.subheadline))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.journalInk)
                .accessibilityIdentifier("protocol-undo-drop")
            }
            Button {
                focusedField = nil
                Task { await save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Color.journalPaper)
                    } else {
                        Text(saveLabel)
                    }
                }
                .font(.journal(.title3, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(JournalPrimaryButtonStyle())
            .disabled(isSaving || items.isEmpty || unresolvedCount > 0)
            .accessibilityIdentifier("protocol-review-save")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.journalPaper)
    }

    private var saveLabel: String {
        switch unresolvedCount {
        case 0: "save protocol"
        case 1: "one row still needs your eyes"
        default: "\(unresolvedCount) rows still need your eyes"
        }
    }

    // MARK: - Actions

    private func candidateName(for movementID: String) -> String {
        definitionNames[movementID] ?? movementID
    }

    private func addToLibrary(itemID: String) async {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let name = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let definition = MovementDefinition.custom(name: name)
            try await movementLibrary.saveMovement(definition)
            definitionNames[definition.id] = definition.canonicalName
            addedMovementIDs.insert(definition.id)
            resolveItem(itemID, toMovementID: definition.id, name: definition.canonicalName)
        } catch MovementLibraryError.duplicateName {
            let movements = (try? await movementLibrary.movements(includeArchived: false)) ?? []
            if let existing = movements.first(where: {
                $0.canonicalName.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                definitionNames[existing.id] = existing.canonicalName
                resolveItem(itemID, toMovementID: existing.id, name: existing.canonicalName)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveItem(_ itemID: String, toMovementID movementID: String, name: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].resolve(toMovementID: movementID, name: name)
    }

    private func drop(itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        lastDropped = items[index]
        lastDroppedIndex = index
        items.remove(at: index)
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            lastDropped = nil
        }
    }

    private func undoDrop(_ dropped: ProtocolReviewItem) {
        undoTask?.cancel()
        items.insert(dropped, at: min(lastDroppedIndex, items.count))
        lastDropped = nil
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let savedItems = items.enumerated().compactMap { index, item in
            item.savedItem(order: index + 1)
        }
        guard !savedItems.isEmpty, savedItems.count == items.count else {
            errorMessage = ProtocolValidationError.invalidItem.localizedDescription
            return
        }
        let now = Date.now
        let therapyProtocol = TherapyProtocol(
            id: UUID().uuidString.lowercased(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            source: parsed.source,
            rawText: parsed.rawText,
            phaseNumber: parsed.phaseNumber,
            phaseCount: parsed.phaseCount,
            unlockMilestone: parsed.unlockMilestone,
            startedAt: now,
            endsAt: nil,
            parserVersion: parsed.parserVersion,
            confidence: parsed.parserConfidence,
            isArchived: false,
            createdAt: now,
            items: savedItems
        )
        do {
            try await protocolRepository.saveProtocol(therapyProtocol.validated())
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

/// One reviewable row: a bordered card whose state (matched, ambiguous, new)
/// decides its border, aside, and chips.
private struct ProtocolReviewItemCard: View {
    @Binding var item: ProtocolReviewItem
    let candidateName: (String) -> String
    let wasAddedToLibrary: Bool
    let onAddToLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titleText)
                    .font(.journal(.title3))
                    .foregroundStyle(Color.journalInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailingAside
            }
            if let notes = item.notes.isEmpty ? nil : item.notes {
                Text(notes.lowercased())
                    .font(.journal(.footnote))
                    .foregroundStyle(Color.journalInk.opacity(0.55))
            }
            if item.isResolved {
                cadenceRow
                if let count = item.timesPerWeekCount {
                    perWeekStepper(count)
                }
                if case .daysOfWeek(let days) = item.cadence {
                    weekdayRow(days)
                }
            } else if !item.candidateIDs.isEmpty {
                candidateChips
            } else {
                addToLibraryRow
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protocol-item-\(item.id)")
    }

    private var titleText: String {
        if item.isResolved || item.candidateIDs.isEmpty {
            let name = item.displayName.lowercased()
            if let summary = item.quantitySummary {
                return "\(name) \(summary)"
            }
            return name
        }
        return "\u{201C}\(item.originalText.lowercased())\u{201D}"
    }

    @ViewBuilder
    private var trailingAside: some View {
        if item.isResolved {
            DrawnCheckmarkView()
        } else if !item.candidateIDs.isEmpty {
            Text("which one?")
                .font(.journal(.footnote))
                .italic()
                .foregroundStyle(Color.journalRedPen)
        } else {
            Text("new one!")
                .font(.journal(.footnote))
                .italic()
                .foregroundStyle(Color.journalInk.opacity(0.6))
        }
    }

    private var cadenceRow: some View {
        JournalChipLayout(spacing: 7) {
            Text("how often:")
                .font(.journal(.footnote))
                .foregroundStyle(Color.journalInk.opacity(0.55))
            JournalChip(
                label: "daily",
                isSelected: item.cadence == .daily,
                accessibilityID: "cadence-daily-\(item.id)"
            ) {
                item.cadence = .daily
            }
            JournalChip(
                label: item.timesPerWeekCount.map { "\($0)×/wk" } ?? "3×/wk",
                isSelected: item.timesPerWeekCount != nil,
                accessibilityID: "cadence-weekly-\(item.id)"
            ) {
                item.cadence = .timesPerWeek(3)
            }
            JournalChip(
                label: "custom",
                isSelected: item.isCustomCadence,
                accessibilityID: "cadence-custom-\(item.id)"
            ) {
                item.cadence = .daysOfWeek([])
            }
            if wasAddedToLibrary {
                Text("added ✓")
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalGreen)
            }
        }
    }

    private func perWeekStepper(_ count: Int) -> some View {
        JournalChipLayout(spacing: 7) {
            Text("times a week:")
                .font(.journal(.footnote))
                .foregroundStyle(Color.journalInk.opacity(0.55))
            JournalChip(label: "−", accessibilityID: "cadence-weekly-minus-\(item.id)") {
                item.cadence = .timesPerWeek(max(1, count - 1))
            }
            Text("\(count)")
                .font(.journal(.body, weight: .semibold))
                .foregroundStyle(Color.journalInk)
            JournalChip(label: "+", accessibilityID: "cadence-weekly-plus-\(item.id)") {
                item.cadence = .timesPerWeek(min(7, count + 1))
            }
        }
    }

    private func weekdayRow(_ days: Set<Int>) -> some View {
        JournalChipLayout(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                JournalChip(
                    label: ProtocolCadence.shortWeekdayName(weekday),
                    isSelected: days.contains(weekday),
                    accessibilityID: "cadence-day\(weekday)-\(item.id)"
                ) {
                    var updated = days
                    if updated.contains(weekday) {
                        updated.remove(weekday)
                    } else {
                        updated.insert(weekday)
                    }
                    item.cadence = .daysOfWeek(updated)
                }
            }
        }
    }

    private var candidateChips: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(item.candidateIDs, id: \.self) { candidateID in
                Button {
                    item.resolve(toMovementID: candidateID, name: candidateName(candidateID))
                } label: {
                    Text(candidateName(candidateID).lowercased())
                        .font(.journal(.body))
                        .foregroundStyle(Color.journalInk)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 14)
                        .overlay(
                            Capsule().strokeBorder(
                                Color.journalInk.opacity(0.45),
                                lineWidth: 1.5
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("candidate-\(candidateID)-\(item.id)")
            }
            Text("tap one — the parser won't guess for you.")
                .font(.journal(.footnote))
                .foregroundStyle(Color.journalInk.opacity(0.55))
        }
    }

    private var addToLibraryRow: some View {
        HStack {
            JournalChip(
                label: "add to your movements",
                isProminent: true,
                accessibilityID: "add-to-movements-\(item.id)",
                action: onAddToLibrary
            )
            Spacer(minLength: 0)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(needsChoice ? Color.journalRedPen.opacity(0.05) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        needsChoice
                            ? Color.journalRedPen.opacity(0.6)
                            : Color.journalInk.opacity(0.35),
                        lineWidth: needsChoice ? 2 : 1.5
                    )
            )
    }

    private var needsChoice: Bool { !item.isResolved && !item.candidateIDs.isEmpty }
}

extension ProtocolReviewItem {
    fileprivate var timesPerWeekCount: Int? {
        if case .timesPerWeek(let count) = cadence { return count }
        return nil
    }

    fileprivate var isCustomCadence: Bool {
        if case .daysOfWeek = cadence { return true }
        return false
    }
}
