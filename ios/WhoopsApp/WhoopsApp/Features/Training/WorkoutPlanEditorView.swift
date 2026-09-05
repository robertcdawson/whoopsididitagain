import SwiftUI

struct WorkoutPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    private let draftKey: String
    @State private var plan: WorkoutPlan
    @State private var evaluation: WorkoutEvaluation?
    @State private var isSaving = false
    @State private var isConfirmingSave = false
    @State private var isRemovingScore = false
    @State private var availableMovements = MovementDefinition.bundled

    let restrictions: [RestrictionProfile]
    let scalingEngine: any WorkoutScalingEngine
    let movementLibrary: any MovementLibraryRepository
    let onSave: (WorkoutPlan) async -> Bool

    init(
        plan: WorkoutPlan,
        restrictions: [RestrictionProfile],
        scalingEngine: any WorkoutScalingEngine,
        movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (WorkoutPlan) async -> Bool
    ) {
        draftKey = "plan:" + (plan.status == .draft ? "new" : plan.id)
        _plan = State(initialValue: plan)
        self.restrictions = restrictions
        self.scalingEngine = scalingEngine
        self.movementLibrary = movementLibrary
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            JournalForm {
                Section {
                    Label("Review the plan once", systemImage: "checkmark.circle")
                        .font(.journal(.headline))
                    Text(
                        "Check the workout details, edit any movement that needs a change, review restriction warnings, then save. Nothing is confirmed individually."
                    )
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                    Label(
                        plan.parserVersion.hasPrefix("apple-extraction-")
                            ? "Parsed with Apple Intelligence · On device"
                            : "Parsed with the built-in parser or entered manually",
                        systemImage: "iphone"
                    )
                    .font(.journal(.caption))
                    .accessibilityIdentifier("workout-parser-provenance")
                }

                Section("Workout") {
                    LabeledFormTextField(
                        title: "Title",
                        text: $plan.title,
                        prompt: "Required"
                    )
                    DatePicker("Scheduled", selection: $plan.scheduledAt)
                        .accessibilityIdentifier("workout-scheduled-at")
                    NavigationLink {
                        WorkoutDetailsEditor(plan: $plan)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Workout details")
                            Text(workoutSummary)
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                    }
                }

                if plan.reportedResult != nil {
                    Section("Reported result") {
                        resultField("Completed rounds", keyPath: \.completedRounds)
                        resultField("Additional reps", keyPath: \.additionalRepetitions)
                        Button("Remove reported result", role: .destructive) {
                            focusedField = nil
                            isRemovingScore = true
                        }
                        Text(
                            "Completed work, not prescribed rounds. Extra reps follow the movement order below. Saving this plan does not record a completed workout."
                        )
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                        if !plan.reportedRepetitionOverrides.isEmpty {
                            Text(
                                "Edited movement totals are kept when the score changes. They do not change the rounds or additional reps above."
                            )
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                        if plan.reportedRepetitionTotals == nil {
                            Text(
                                "Totals cannot be calculated from this score. Tap each movement to enter its reported total."
                            )
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalAmberText)
                        }
                    }
                } else {
                    Section {
                        Button("Add reported result") {
                            plan.reportedResult = WorkoutReportedResult(
                                completedRounds: 0, additionalRepetitions: 0)
                        }
                    }
                }

                if !plan.ambiguities.isEmpty {
                    Section {
                        ForEach(plan.ambiguities) { ambiguity in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ambiguity.originalText)
                                    .font(.journal(.subheadline, weight: .medium))
                                Text(ambiguity.message)
                                    .font(.journal(.caption))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
                            }
                        }
                    } header: {
                        Text("Parser notes")
                    } footer: {
                        Text(
                            "These notes preserve what the parser could not infer. Edit the corresponding workout details if needed; you do not need to dismiss each note."
                        )
                    }
                }

                ForEach(plan.segments.indices, id: \.self) { segmentIndex in
                    segmentSection(segmentIndex)
                }

                Section {
                    Button("Add work segment", systemImage: "plus") {
                        addSegment(type: .work)
                    }
                    Button("Add rest segment", systemImage: "pause.fill") {
                        addSegment(type: .rest)
                    }
                    .accessibilityIdentifier("add-rest-segment")
                }

                if let evaluation {
                    Section("Restriction evaluation") {
                        Label(
                            evaluation.recommendation.displayName,
                            systemImage: evaluation.recommendation.symbolName
                        )
                        .font(.journal(.headline))
                        if evaluation.conflicts.isEmpty {
                            Text("No active movement restriction conflicts were detected.")
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                        ForEach(evaluation.conflicts) { conflict in
                            conflictView(conflict)
                        }
                    }
                }

                Section("Original source") {
                    DisclosureGroup("Show pasted workout") {
                        Text(plan.rawText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .recoverableDraft(key: draftKey, value: $plan)
            .navigationTitle("Review Workout")
            .onChange(of: plan.movements.map(\.id)) { _, _ in
                plan.discardOrphanedReportedRepetitionOverrides()
            }
            .navigationBarTitleDisplayMode(.inline)
            .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
            .confirmationDialog(
                "Remove the reported result?", isPresented: $isRemovingScore,
                titleVisibility: .visible
            ) {
                Button("Remove result", role: .destructive) { plan.reportedResult = nil }
                Button("Keep result", role: .cancel) {}
            } message: {
                Text(
                    "Edited movement totals are kept. Calculated totals will no longer use this score."
                )
            }
            .journalSaveBar {
                Button("Review & Save") {
                    focusedField = nil
                    isConfirmingSave = true
                }
                .disabled(isSaving || !isValid)
                .accessibilityIdentifier("review-and-save-workout")

            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }

            }
            .confirmationDialog(
                "Save reviewed plan?",
                isPresented: $isConfirmingSave,
                titleVisibility: .visible
            ) {
                Button("Save reviewed plan") {
                    Task { await savePlan() }
                }
                Button("Keep reviewing", role: .cancel) {}
            } message: {
                Text(
                    "This confirms that you reviewed the workout, including its movements, quantities, loads, and restriction warnings."
                )
            }
            .task(id: plan) {
                evaluation = await scalingEngine.evaluate(
                    plan: plan,
                    restrictions: restrictions
                )
            }
            .task {
                if let summaries = try? await movementLibrary.usageSummaries() {
                    availableMovements = summaries.map(\.movement)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentSection(_ segmentIndex: Int) -> some View {
        Section {
            NavigationLink {
                WorkoutSegmentEditor(segment: $plan.segments[segmentIndex])
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Segment setup")
                    Text(segmentSummary(plan.segments[segmentIndex]))
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
            }
            .accessibilityIdentifier("segment-setup-\(segmentIndex)")
            let notes = plan.visibleNotes(plan.segments[segmentIndex].notes)
            if !notes.isEmpty {
                Text(notes)
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }

            if plan.segments[segmentIndex].type != .rest {
                ForEach(plan.segments[segmentIndex].movements.indices, id: \.self) {
                    movementIndex in
                    NavigationLink {
                        MovementPrescriptionEditor(
                            movement: $plan.segments[segmentIndex].movements[movementIndex],
                            definitions: availableMovements,
                            calculatedTotal: plan.reportedRepetitionTotals?[
                                plan.segments[segmentIndex].movements[movementIndex].id],
                            reportedTotalOverride: reportedTotalBinding(
                                segmentIndex, movementIndex),
                            onDuplicate: { duplicateMovement(segmentIndex, movementIndex) }
                        )
                    } label: {
                        let movement = plan.segments[segmentIndex].movements[movementIndex]
                        let status = movementStatus(movement)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(movement.displayName)
                            if let summary = prescriptionSummary(movement) {
                                Text(summary)
                                    .font(.journal(.caption))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
                            }
                            if let total = plan.effectiveReportedRepetitionTotals[movement.id] {
                                Text(
                                    "Reported total: \(total) reps\(plan.reportedRepetitionOverrides[movement.id] == nil ? "" : " (edited)") · Edit"
                                )
                                .font(.journal(.caption))
                                .foregroundStyle(.tint)
                                .accessibilityIdentifier(
                                    "reported-total-\(segmentIndex)-\(movementIndex)")
                            } else if plan.hasReportedRepetitions {
                                Text("Enter reported total")
                                    .font(.journal(.caption))
                                    .foregroundStyle(.tint)
                            }
                            Label(status.title, systemImage: status.symbolName)
                                .font(.journal(.caption))
                                .foregroundStyle(status.color)
                        }
                    }
                    .accessibilityIdentifier("movement-editor-\(segmentIndex)-\(movementIndex)")
                    .contextMenu {
                        Button("Move up", systemImage: "arrow.up") {
                            focusedField = nil
                            plan.segments[segmentIndex].movements.swapAt(
                                movementIndex, movementIndex - 1)
                        }.disabled(movementIndex == 0)
                        Button("Move down", systemImage: "arrow.down") {
                            focusedField = nil
                            plan.segments[segmentIndex].movements.swapAt(
                                movementIndex, movementIndex + 1)
                        }.disabled(movementIndex == plan.segments[segmentIndex].movements.count - 1)
                    }
                    .swipeActions {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            duplicateMovement(segmentIndex, movementIndex)
                        }
                        .tint(.journalInk)
                        Button("Delete", role: .destructive) {
                            plan.segments[segmentIndex].movements.remove(at: movementIndex)
                            plan.discardOrphanedReportedRepetitionOverrides()
                        }
                    }
                }
                Button("Add movement", systemImage: "plus") {
                    plan.segments[segmentIndex].movements.append(Self.emptyMovement())
                }
            }
            if plan.segments.count > 1 {
                Menu("Reorder segment") {
                    Button("Move up", systemImage: "arrow.up") { moveSegment(segmentIndex, by: -1) }
                        .disabled(segmentIndex == 0)
                    Button("Move down", systemImage: "arrow.down") {
                        moveSegment(segmentIndex, by: 1)
                    }
                    .disabled(segmentIndex == plan.segments.count - 1)
                }
                Button("Delete segment", role: .destructive) {
                    plan.segments.remove(at: segmentIndex)
                    plan.discardOrphanedReportedRepetitionOverrides()
                    for index in plan.segments.indices {
                        plan.segments[index].sequence = index + 1
                    }
                }
            }
        } header: {
            Text("Segment \(segmentIndex + 1)")
        } footer: {
            if plan.segments[segmentIndex].type != .rest {
                Text(
                    "Tap a movement to edit it. Touch and hold to reorder; swipe to duplicate or delete."
                )
            }
        }
    }

    @ViewBuilder
    private func conflictView(_ conflict: WorkoutConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                conflict.severity == .hard ? "Must modify" : "Use caution",
                systemImage: conflict.severity == .hard
                    ? "hand.raised.fill" : "exclamationmark.triangle"
            )
            .foregroundStyle(
                conflict.severity == .hard ? Color.journalRedPen : .journalAmberText)
            Text(conflict.explanation)
            Text(conflict.preservedStimulus)
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            Text(conflict.compromise)
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            if !conflict.substitutionCandidates.isEmpty {
                Text("Candidate substitutions")
                    .font(.journal(.caption, weight: .semibold))
                ForEach(conflict.substitutionCandidates) { candidate in
                    Button("Use \(candidate.canonicalName)") {
                        apply(candidate, toMovementID: conflict.movementID)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var isValid: Bool {
        !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (plan.reportedResult?.isValid ?? true)
            && plan.hasValidReportedRepetitionOverrides
            && plan.intendedStimulus.hasValidDurationRange
            && (plan.timeCapSeconds.map { $0.isFinite && $0 > 0 } ?? true)
            && !plan.segments.isEmpty
            && plan.segments.allSatisfy { segment in
                segment.hasValidStructure
                    && segment.movements.allSatisfy {
                        !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && $0.hasValidQuantities
                    }
            }
    }

    private func duplicateMovement(_ segmentIndex: Int, _ movementIndex: Int) {
        let copy = plan.segments[segmentIndex].movements[movementIndex].duplicated()
        plan.segments[segmentIndex].movements.insert(copy, at: movementIndex + 1)
    }

    private func moveSegment(_ index: Int, by offset: Int) {
        focusedField = nil
        plan.segments.swapAt(index, index + offset)
        for index in plan.segments.indices { plan.segments[index].sequence = index + 1 }
    }

    private func reportedTotalBinding(_ segmentIndex: Int, _ movementIndex: Int) -> Binding<Int?> {
        let id = plan.segments[segmentIndex].movements[movementIndex].id
        return Binding(
            get: { plan.reportedRepetitionOverrides[id] },
            set: { plan.reportedRepetitionOverrides[id] = $0 }
        )
    }

    private func resultField(_ title: String, keyPath: WritableKeyPath<WorkoutReportedResult, Int>)
        -> some View
    {
        WorkoutResultCountField(
            title: title,
            value: Binding(
                get: { plan.reportedResult?[keyPath: keyPath] ?? 0 },
                set: { plan.reportedResult?[keyPath: keyPath] = $0 }
            ))
    }

    private func addSegment(type: WorkoutSegmentType) {
        plan.segments.append(
            WorkoutSegment(
                id: UUID().uuidString.lowercased(),
                sequence: plan.segments.count + 1,
                type: type,
                rounds: nil,
                durationSeconds: nil,
                restSeconds: nil,
                notes: "",
                movements: []
            )
        )
    }

    private func apply(_ item: MovementCatalogItem, toMovementID id: String) {
        for segmentIndex in plan.segments.indices {
            guard
                let movementIndex = plan.segments[segmentIndex].movements.firstIndex(where: {
                    $0.id == id
                })
            else { continue }
            plan.segments[segmentIndex].movements[movementIndex].canonicalMovementID = item.id
            plan.segments[segmentIndex].movements[movementIndex].displayName = item.canonicalName
            let note = plan.segments[segmentIndex].movements[movementIndex].notes
            plan.segments[segmentIndex].movements[movementIndex].notes =
                note.isEmpty ? "Substituted to respect an active restriction." : note
        }
    }

    private var workoutSummary: String {
        var values = [plan.format.displayName]
        let stimulus = plan.intendedStimulus.primary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !stimulus.isEmpty { values.append(stimulus) }
        if let seconds = plan.timeCapSeconds {
            values.append("\(WorkoutDurationInput.summary(seconds: seconds)) cap")
        }
        return values.joined(separator: " · ")
    }

    private func segmentSummary(_ segment: WorkoutSegment) -> String {
        if segment.type == .rest {
            guard let duration = segment.durationSeconds else {
                return "Rest · duration required"
            }
            return "Rest · \(WorkoutDurationInput.summary(seconds: duration))"
        }
        var values = [segment.type.displayName]
        if let rounds = segment.rounds { values.append("\(rounds) rounds") }
        if let duration = segment.durationSeconds {
            values.append(WorkoutDurationInput.summary(seconds: duration))
        }
        if let rest = segment.restSeconds {
            if segment.type == .work {
                values.append(
                    segment.rounds == nil
                        ? "\(WorkoutDurationInput.summary(seconds: rest)) between efforts"
                        : "\(WorkoutDurationInput.summary(seconds: rest)) between rounds"
                )
            } else {
                values.append("\(WorkoutDurationInput.summary(seconds: rest)) after segment")
            }
        }
        return values.joined(separator: " · ")
    }

    private func prescriptionSummary(_ movement: MovementPrescription) -> String? {
        var values: [String] = []
        if let repetitions = movement.repetitions { values.append("\(repetitions) reps") }
        if let distance = movement.distanceMeters { values.append("\(distance) m") }
        if let calories = movement.calories { values.append("\(calories) cal") }
        if let load = movement.loadValue {
            values.append(
                [load.formatted(), movement.loadUnit].compactMap { $0 }.joined(separator: " ")
            )
        }
        if let percentage = movement.percentageOfOneRepMax {
            values.append("\(percentage.formatted())% 1RM")
        }
        if let duration = movement.durationSeconds {
            values.append(WorkoutDurationInput.summary(seconds: duration))
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func movementStatus(_ movement: MovementPrescription) -> MovementReviewStatus {
        guard movement.canonicalMovementID != nil else {
            return MovementReviewStatus(
                title: "Manual or unmapped movement",
                symbolName: "pencil.circle",
                color: .journalAmberText
            )
        }
        guard prescriptionSummary(movement) != nil else {
            return MovementReviewStatus(
                title: "No quantity entered",
                symbolName: "exclamationmark.circle",
                color: .journalAmberText
            )
        }
        return MovementReviewStatus(
            title: "Prescription details present",
            symbolName: "list.bullet.clipboard",
            color: .journalInk.opacity(0.7)
        )
    }

    @MainActor
    private func savePlan() async {
        focusedField = nil
        isSaving = true
        if plan.status == .draft { plan.status = .planned }
        if await onSave(plan) {
            try? EditorDraftStore.shared.finish(key: draftKey)
            try? EditorDraftStore.shared.finish(key: "workout-intake:new")
            dismiss()
        }
        isSaving = false
    }

    private static func emptyMovement() -> MovementPrescription {
        MovementPrescription(
            id: UUID().uuidString.lowercased(),
            canonicalMovementID: nil,
            displayName: "",
            originalText: "",
            repetitions: nil,
            distanceMeters: nil,
            calories: nil,
            loadValue: nil,
            loadUnit: nil,
            percentageOfOneRepMax: nil,
            durationSeconds: nil,
            tempo: nil,
            notes: ""
        )
    }
}

private struct MovementReviewStatus {
    let title: String
    let symbolName: String
    let color: Color
}

/// Keeps UIKit's pending edit distinct from the last accepted display/model value.
/// Reconciliation runs after the control receives its edit, never by rolling back an
/// onChange callback's possibly stale `previous` value or writing the model again.
struct WorkoutFieldInput: Equatable {
    private(set) var text: String
    private(set) var acceptedText: String

    init(_ text: String) {
        self.text = text
        acceptedText = text
    }

    mutating func receive(_ candidate: String, accepted: Bool) {
        text = candidate
        if accepted { acceptedText = candidate }
    }

    mutating func reconcile() {
        if text != acceptedText { text = acceptedText }
    }

    mutating func replace(_ text: String) {
        self = Self(text)
    }
}

struct WorkoutResultCountField: View {
    let title: String
    @Binding var value: Int
    @State private var field: WorkoutFieldInput

    init(title: String, value: Binding<Int>) {
        self.title = title
        _value = value
        _field = State(initialValue: WorkoutFieldInput(String(value.wrappedValue)))
    }

    var body: some View {
        LabeledFormTextField(
            title: title, text: input, keyboardType: .numberPad
        )
        .onChange(of: field.text) { _, _ in field.reconcile() }
    }

    private var input: Binding<String> {
        Binding(
            get: { field.text },
            set: { candidate in
                let parsed = candidate.isEmpty ? 0 : Int(candidate)
                let accepted =
                    candidate.allSatisfy(\.isNumber)
                    && parsed.map { (0...100_000).contains($0) } == true
                field.receive(candidate, accepted: accepted)
                if accepted, let parsed { value = parsed }
            })
    }
}

struct WorkoutMinutesField: View {
    let title: String
    @Binding var seconds: Double?
    @State private var field: WorkoutFieldInput

    init(title: String, seconds: Binding<Double?>) {
        self.title = title
        _seconds = seconds
        _field = State(
            initialValue: WorkoutFieldInput(
                seconds.wrappedValue.map { WorkoutDurationInput.minutesText(seconds: $0) } ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextField("", text: input, prompt: Text("Optional"))
                .formKeyboardField()
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(title)
                .onChange(of: field.text) { _, _ in field.reconcile() }
                .onChange(of: seconds) { _, _ in
                    let value = seconds
                    // Date/time edits can update a duration from outside this field. Preserve
                    // in-progress decimal input when it already represents the new value.
                    if let value, let parsed = WorkoutDurationInput.seconds(field.acceptedText),
                        abs(value - parsed) < 0.000_001
                    {
                        return
                    }
                    if value == nil && field.acceptedText.isEmpty { return }
                    field.replace(value.map { WorkoutDurationInput.minutesText(seconds: $0) } ?? "")
                }
        }
    }

    private var input: Binding<String> {
        Binding(
            get: { field.text },
            set: { candidate in
                let parsed = WorkoutDurationInput.seconds(candidate)
                let accepted =
                    WorkoutDurationInput.accepts(candidate)
                    && (candidate.isEmpty || candidate == "."
                        || candidate == Locale.current.decimalSeparator
                        || parsed != nil)
                field.receive(candidate, accepted: accepted)
                guard accepted else { return }
                // Preserve partial decimals and never round stored precision merely by opening.
                if candidate.isEmpty { seconds = nil } else if let parsed { seconds = parsed }
            })
    }
}

struct WorkoutDecimalField: View {
    let title: String
    let allowsZero: Bool
    @Binding var value: Double?
    @State private var field: WorkoutFieldInput

    init(title: String, value: Binding<Double?>, allowsZero: Bool = false) {
        self.title = title
        self.allowsZero = allowsZero
        _value = value
        _field = State(
            initialValue: WorkoutFieldInput(
                value.wrappedValue.map { WorkoutDecimalInput.text($0) } ?? ""))
    }

    var body: some View {
        LabeledFormTextField(title: title, text: input, keyboardType: .decimalPad)
            .onChange(of: field.text) { _, _ in field.reconcile() }
            .onChange(of: value) { _, _ in
                let updated = value
                // Do not rewrite partial input such as "12." while the user types.
                guard updated != parsedValue else { return }
                field.replace(updated.map { WorkoutDecimalInput.text($0) } ?? "")
            }
    }

    private var input: Binding<String> {
        Binding(
            get: { field.text },
            set: { candidate in
                let accepted = WorkoutDecimalInput.accepts(candidate)
                field.receive(candidate, accepted: accepted)
                if accepted { value = parsedValue }
            })
    }

    private var parsedValue: Double? {
        WorkoutDecimalInput.number(field.acceptedText).flatMap { allowsZero || $0 > 0 ? $0 : nil }
    }
}

struct WorkoutLoadUnitPicker: View {
    let title: String
    @Binding var unit: String?

    var body: some View {
        Picker(
            title,
            selection: Binding(
                get: { WorkoutLoadUnit.normalized(unit)?.rawValue ?? "" },
                set: { unit = $0.isEmpty ? nil : $0 }
            )
        ) {
            Text("Select unit").tag("")
            ForEach(WorkoutLoadUnit.allCases) { option in
                Text(option.displayName).tag(option.rawValue)
            }
        }
        .accessibilityIdentifier(
            title == "Load unit" ? "load-unit-picker" : "actual-load-unit-picker")
        if let unit, !unit.isEmpty, WorkoutLoadUnit.normalized(unit) == nil {
            Text(
                "Stored unit: \(unit). Choose lbs or kg to correct it; changing units does not convert the number."
            )
            .font(.journal(.caption))
            .foregroundStyle(Color.journalAmberText)
        }
    }
}

private struct LabeledFormTextField: View {
    let title: String
    @Binding var text: String
    var prompt = "Optional"
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextField(
                "", text: $text, prompt: Text(prompt),
                axis: keyboardType == .default ? .vertical : .horizontal
            )
            .formKeyboardField(singleLineText: keyboardType == .default ? $text : nil)
            .keyboardType(keyboardType)
            .lineLimit(1...4)
            .multilineTextAlignment(keyboardType == .default ? .leading : .trailing)
            .accessibilityLabel(title)
            .accessibilityIdentifier(title)
        }
    }
}

private struct LabeledFormMultilineField: View {
    let title: String
    @Binding var text: String
    var prompt = "Optional"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.journal(.subheadline))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            TextField("", text: $text, prompt: Text(prompt), axis: .vertical)
                .formKeyboardField(dismissOnSubmit: false)
                .dictationInput($text)
                .lineLimit(1...4)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 2)
    }
}

private struct WorkoutDetailsEditor: View {
    @Binding var plan: WorkoutPlan
    @FocusState private var focusedField: UUID?
    @State private var targetsText: String

    init(plan: Binding<WorkoutPlan>) {
        _plan = plan
        _targetsText = State(
            initialValue: plan.wrappedValue.intendedStimulus.secondary.joined(separator: "\n"))
    }

    var body: some View {
        JournalForm {
            Section("Structure") {
                Picker("Format", selection: $plan.format) {
                    ForEach(WorkoutFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                LabeledFormMultilineField(
                    title: "Intended stimulus",
                    text: $plan.intendedStimulus.primary
                )
                LabeledFormMultilineField(
                    title: "Targets and context",
                    text: $targetsText
                )
                .onChange(of: targetsText) { _, text in
                    // Normalize the stored targets without stripping spaces/newlines from
                    // the text currently being edited.
                    plan.intendedStimulus.secondary = text.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
                WorkoutMinutesField(
                    title: "Time cap in minutes",
                    seconds: $plan.timeCapSeconds
                )
                WorkoutMinutesField(
                    title: "Estimated minimum minutes",
                    seconds: estimateBinding(\.estimatedDurationMinimumMinutes))
                WorkoutMinutesField(
                    title: "Estimated maximum minutes",
                    seconds: estimateBinding(\.estimatedDurationMaximumMinutes))
                if !plan.intendedStimulus.hasValidDurationRange {
                    Text(
                        "Estimates must be positive, with the minimum no greater than the maximum."
                    )
                    .font(.journal(.caption)).foregroundStyle(Color.journalAmberText)
                }
            }
        }
        .navigationTitle("Workout Details")
        .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
    }

    private func estimateBinding(_ keyPath: WritableKeyPath<WorkoutStimulus, Double?>) -> Binding<
        Double?
    > {
        Binding(
            get: { plan.intendedStimulus[keyPath: keyPath].map { $0 * 60 } },
            set: { plan.intendedStimulus[keyPath: keyPath] = $0.map { $0 / 60 } })
    }
}

private struct WorkoutSegmentEditor: View {
    @Binding var segment: WorkoutSegment
    @FocusState private var focusedField: UUID?
    @State private var isConvertingToRest = false

    var body: some View {
        JournalForm {
            Section("Segment") {
                Picker("Type", selection: typeBinding) {
                    ForEach(WorkoutSegmentType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                if segment.type == .rest {
                    WorkoutMinutesField(
                        title: "Rest duration in minutes",
                        seconds: $segment.durationSeconds
                    )
                    Text(
                        "This recovery occurs once at this point in the workout. Add separate Rest segments when recovery times vary."
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                    if hasIncompatibleRestContent {
                        Label(
                            "This older Rest segment contains incompatible work details.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalAmberText)
                        Button("Remove incompatible work details", role: .destructive) {
                            focusedField = nil
                            isConvertingToRest = true
                        }
                    }
                } else {
                    numberField("Prescribed rounds", value: $segment.rounds)
                    WorkoutMinutesField(
                        title: "Duration in minutes", seconds: $segment.durationSeconds)
                    WorkoutMinutesField(title: restFieldTitle, seconds: $segment.restSeconds)
                    Text(restExplanation)
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
                LabeledFormMultilineField(
                    title: "Notes and targets",
                    text: $segment.notes
                )
            }
        }
        .navigationTitle("Segment Setup")
        .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
        .confirmationDialog(
            "Convert this segment to rest?", isPresented: $isConvertingToRest,
            titleVisibility: .visible
        ) {
            Button("Convert to rest", role: .destructive) { convertToRest() }
            Button("Keep work details", role: .cancel) {}
        } message: {
            Text(
                "Rest segments cannot contain movements, rounds, or a second recovery value. Converting removes those details from this draft; notes and duration are kept."
            )
        }
    }

    private var typeBinding: Binding<WorkoutSegmentType> {
        Binding(
            get: { segment.type },
            set: { type in
                focusedField = nil
                if type == .rest {
                    if hasIncompatibleRestContent {
                        isConvertingToRest = true
                    } else {
                        convertToRest()
                    }
                } else {
                    segment.type = type
                }
            })
    }

    private func convertToRest() {
        segment.type = .rest
        segment.durationSeconds = segment.durationSeconds ?? segment.restSeconds
        segment.rounds = nil
        segment.restSeconds = nil
        segment.movements = []
    }

    private var hasIncompatibleRestContent: Bool {
        segment.rounds != nil || segment.restSeconds != nil || !segment.movements.isEmpty
    }

    private var restFieldTitle: String {
        guard segment.type == .work else { return "Rest after segment in minutes" }
        return segment.rounds == nil
            ? "Rest between efforts in minutes" : "Rest between rounds in minutes"
    }

    private var restExplanation: String {
        guard segment.type == .work else {
            return "This optional recovery occurs once after the segment."
        }
        return segment.rounds == nil
            ? "Applied uniformly between the segment’s repeated efforts."
            : "Applied uniformly between every round."
    }

    @ViewBuilder
    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        LabeledFormTextField(
            title: title,
            text: optionalInteger(value),
            keyboardType: .numberPad
        )
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0).flatMap { $0 > 0 ? $0 : nil } }
        )
    }
}

private struct MovementPrescriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @Binding var movement: MovementPrescription
    let definitions: [MovementDefinition]
    let calculatedTotal: Int?
    @Binding var reportedTotalOverride: Int?
    let onDuplicate: () -> Void

    var body: some View {
        JournalForm {
            ReportedMovementTotalSection(
                calculatedTotal: calculatedTotal,
                correction: $reportedTotalOverride
            )
            Section("Movement") {
                LabeledFormTextField(
                    title: "Display name",
                    text: $movement.displayName,
                    prompt: "Required"
                )
                NavigationLink {
                    MovementSelectionView(
                        canonicalMovementID: $movement.canonicalMovementID,
                        displayName: $movement.displayName, definitions: definitions)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose from your movements")
                        Text(selectedMovementName)
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                    }
                }
                LabeledFormMultilineField(
                    title: "Original wording",
                    text: $movement.originalText
                )
                if movement.canonicalMovementID == nil {
                    Text(
                        "A clean movement name entered here will be remembered when you save the workout. Repetitions and load stay with this workout only."
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                }
            }
            Section("Prescription") {
                numberField("Repetitions", value: $movement.repetitions)
                numberField("Distance in meters", value: $movement.distanceMeters)
                numberField("Calories", value: $movement.calories)
                decimalField("Load", value: $movement.loadValue)
                WorkoutLoadUnitPicker(
                    title: "Load unit",
                    unit: $movement.loadUnit
                )
                decimalField("Percent of 1RM", value: $movement.percentageOfOneRepMax)
                WorkoutMinutesField(
                    title: "Duration in minutes", seconds: $movement.durationSeconds)
                LabeledFormTextField(
                    title: "Tempo",
                    text: optionalString($movement.tempo)
                )
                LabeledFormMultilineField(title: "Notes", text: $movement.notes)
            }
            Section {
                Button("Duplicate movement", systemImage: "plus.square.on.square") {
                    focusedField = nil
                    onDuplicate()
                    dismiss()
                }
                .accessibilityIdentifier("duplicate-movement")
            }
        }
        .navigationTitle("Movement")
        .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
    }

    private var selectedMovementName: String {
        guard let id = movement.canonicalMovementID,
            let definition = definitions.first(where: { $0.id == id })
        else { return "Unmapped / new personal movement" }
        return definition.canonicalName
    }

    @ViewBuilder
    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        LabeledFormTextField(
            title: title,
            text: optionalInteger(value),
            keyboardType: .numberPad
        )
    }

    @ViewBuilder
    private func decimalField(_ title: String, value: Binding<Double?>) -> some View {
        WorkoutDecimalField(title: title, value: value)
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0).flatMap { $0 > 0 ? $0 : nil } }
        )
    }

    private func optionalString(_ value: Binding<String?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct ReportedMovementTotalSection: View {
    let calculatedTotal: Int?
    @Binding var correction: Int?
    @State private var field: WorkoutFieldInput

    init(calculatedTotal: Int?, correction: Binding<Int?>) {
        self.calculatedTotal = calculatedTotal
        _correction = correction
        _field = State(
            initialValue: WorkoutFieldInput(
                (correction.wrappedValue ?? calculatedTotal).map(String.init) ?? ""))
    }

    var body: some View {
        Section {
            LabeledFormTextField(
                title: "Reported total reps", text: input, keyboardType: .numberPad
            )
            .onChange(of: field.text) { _, _ in field.reconcile() }
            if let calculatedTotal {
                LabeledContent("Calculated from score", value: "\(calculatedTotal) reps")
            }
            if correction != nil {
                Label("Edited total", systemImage: "pencil")
                    .font(.journal(.caption))
                Button(calculatedTotal == nil ? "Clear edited total" : "Use calculated total") {
                    correction = nil
                    field.replace(calculatedTotal.map(String.init) ?? "")
                }
                .accessibilityIdentifier("reset-reported-total")
            }
        } header: {
            Text("Reported total")
        } footer: {
            Text(
                "Total reps completed across all rounds, not reps per round. Editing this leaves your score and prescription unchanged. An edited total stays fixed if the score changes. Leave blank to use the calculated total, when available."
            )
        }
        .onChange(of: calculatedTotal) { _, count in
            if correction == nil { field.replace(count.map(String.init) ?? "") }
        }
    }

    private var input: Binding<String> {
        Binding(
            get: { field.text },
            set: { candidate in
                let count = Int(candidate)
                let accepted =
                    candidate.isEmpty
                    || (candidate.allSatisfy(\.isNumber)
                        && count.map { (0...100_000).contains($0) } == true)
                field.receive(candidate, accepted: accepted)
                guard accepted else { return }
                if candidate.isEmpty {
                    correction = nil
                    return
                }
                guard let count else { return }
                if count != (correction ?? calculatedTotal) { correction = count }
            })
    }
}

struct MovementSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State private var searchFieldID = UUID()
    @Binding var canonicalMovementID: String?
    @Binding var displayName: String
    let definitions: [MovementDefinition]
    var remembersNewMovement = true
    @State private var searchText = ""

    var body: some View {
        JournalList {
            Section {
                Button(
                    remembersNewMovement
                        ? "Use a new personal movement" : "Use an unmapped movement"
                ) {
                    focusedField = nil
                    canonicalMovementID = nil
                    dismiss()
                }
            } footer: {
                Text(
                    remembersNewMovement
                        ? "Enter its clean name on the previous screen; it will be remembered on save."
                        : "Edit its name on the previous screen. This affects this workout only; manage reusable definitions in Your Movements."
                )
            }
            Section("Your Movements") {
                ForEach(filteredDefinitions) { definition in
                    Button {
                        focusedField = nil
                        canonicalMovementID = definition.id
                        displayName = definition.canonicalName
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.canonicalName)
                                .foregroundStyle(.primary)
                            Text(definition.category.displayName)
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Movement")
        .searchable(text: $searchText, prompt: "Name or alias")
        .searchFocused($focusedField, equals: searchFieldID)
        .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
    }

    private var filteredDefinitions: [MovementDefinition] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return definitions
        }
        let query = searchText.lowercased()
        return definitions.filter {
            $0.canonicalName.lowercased().contains(query)
                || $0.aliases.contains { $0.lowercased().contains(query) }
        }
    }
}
