import SwiftUI

struct WorkoutPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var plan: WorkoutPlan
    @State private var evaluation: WorkoutEvaluation?
    @State private var isSaving = false
    @State private var isConfirmingSave = false
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
        _plan = State(initialValue: plan)
        self.restrictions = restrictions
        self.scalingEngine = scalingEngine
        self.movementLibrary = movementLibrary
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Review the plan once", systemImage: "checkmark.circle")
                        .font(.headline)
                    Text(
                        "Check the workout details, edit any movement that needs a change, review restriction warnings, then save. Nothing is confirmed individually."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("Workout") {
                    LabeledFormTextField(
                        title: "Title",
                        text: $plan.title,
                        prompt: "Required"
                    )
                    DatePicker("Scheduled", selection: $plan.scheduledAt)
                    NavigationLink {
                        WorkoutDetailsEditor(plan: $plan)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Workout details")
                            Text(workoutSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !plan.ambiguities.isEmpty {
                    Section {
                        ForEach(plan.ambiguities) { ambiguity in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ambiguity.originalText)
                                    .font(.subheadline.weight(.medium))
                                Text(ambiguity.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                        .font(.headline)
                        if evaluation.conflicts.isEmpty {
                            Text("No active movement restriction conflicts were detected.")
                                .foregroundStyle(.secondary)
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
            .navigationTitle("Review Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review & Save") {
                        isConfirmingSave = true
                    }
                    .disabled(isSaving || !isValid)
                    .accessibilityIdentifier("review-and-save-workout")
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("segment-setup-\(segmentIndex)")
            if !plan.segments[segmentIndex].notes.isEmpty {
                Text(plan.segments[segmentIndex].notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if plan.segments[segmentIndex].type != .rest {
                ForEach(plan.segments[segmentIndex].movements.indices, id: \.self) {
                    movementIndex in
                    NavigationLink {
                        MovementPrescriptionEditor(
                            movement: $plan.segments[segmentIndex].movements[movementIndex],
                            definitions: availableMovements
                        )
                    } label: {
                        let movement = plan.segments[segmentIndex].movements[movementIndex]
                        let status = movementStatus(movement)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(movement.displayName)
                            if let summary = prescriptionSummary(movement) {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Label(status.title, systemImage: status.symbolName)
                                .font(.caption)
                                .foregroundStyle(status.color)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            plan.segments[segmentIndex].movements.remove(at: movementIndex)
                        }
                    }
                }
                Button("Add movement", systemImage: "plus") {
                    plan.segments[segmentIndex].movements.append(Self.emptyMovement())
                }
            }
            if plan.segments.count > 1 {
                Button("Delete segment", role: .destructive) {
                    plan.segments.remove(at: segmentIndex)
                    for index in plan.segments.indices {
                        plan.segments[index].sequence = index + 1
                    }
                }
            }
        } header: {
            Text("Segment \(segmentIndex + 1)")
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
            .foregroundStyle(conflict.severity == .hard ? .red : .orange)
            Text(conflict.explanation)
            Text(conflict.preservedStimulus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(conflict.compromise)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !conflict.substitutionCandidates.isEmpty {
                Text("Candidate substitutions")
                    .font(.caption.weight(.semibold))
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
            && !plan.segments.isEmpty
            && plan.segments.allSatisfy { segment in
                segment.hasValidStructure
                    && segment.movements.allSatisfy {
                        !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
            }
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
        if let seconds = plan.timeCapSeconds { values.append("\(seconds / 60) min cap") }
        return values.joined(separator: " · ")
    }

    private func segmentSummary(_ segment: WorkoutSegment) -> String {
        if segment.type == .rest {
            guard let duration = segment.durationSeconds else {
                return "Rest · duration required"
            }
            return "Rest · \(duration) sec"
        }
        var values = [segment.type.displayName]
        if let rounds = segment.rounds { values.append("\(rounds) rounds") }
        if let duration = segment.durationSeconds { values.append("\(duration) sec") }
        if let rest = segment.restSeconds {
            if segment.type == .work {
                values.append(
                    segment.rounds == nil
                        ? "\(rest) sec between efforts" : "\(rest) sec between rounds"
                )
            } else {
                values.append("\(rest) sec after segment")
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
        if let duration = movement.durationSeconds { values.append("\(duration) sec") }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func movementStatus(_ movement: MovementPrescription) -> MovementReviewStatus {
        guard movement.canonicalMovementID != nil else {
            return MovementReviewStatus(
                title: "Manual or unmapped movement",
                symbolName: "pencil.circle",
                color: .orange
            )
        }
        guard prescriptionSummary(movement) != nil else {
            return MovementReviewStatus(
                title: "No quantity entered",
                symbolName: "exclamationmark.circle",
                color: .orange
            )
        }
        return MovementReviewStatus(
            title: "Prescription details present",
            symbolName: "list.bullet.clipboard",
            color: .secondary
        )
    }

    @MainActor
    private func savePlan() async {
        isSaving = true
        plan.status = .planned
        if await onSave(plan) { dismiss() }
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

private struct LabeledFormTextField: View {
    let title: String
    @Binding var text: String
    var prompt = "Optional"
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        LabeledContent(title) {
            TextField("", text: $text, prompt: Text(prompt))
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text(prompt), axis: .vertical)
                .lineLimit(1...4)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 2)
    }
}

private struct WorkoutDetailsEditor: View {
    @Binding var plan: WorkoutPlan

    var body: some View {
        Form {
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
                    text: secondaryTargets
                )
                LabeledFormTextField(
                    title: "Time cap in minutes",
                    text: optionalMinutes,
                    keyboardType: .numberPad
                )
            }
        }
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var optionalMinutes: Binding<String> {
        Binding(
            get: { plan.timeCapSeconds.map { String($0 / 60) } ?? "" },
            set: { plan.timeCapSeconds = Int($0).flatMap { $0 > 0 ? $0 * 60 : nil } }
        )
    }

    private var secondaryTargets: Binding<String> {
        Binding(
            get: { plan.intendedStimulus.secondary.joined(separator: "\n") },
            set: { value in
                plan.intendedStimulus.secondary = value.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct WorkoutSegmentEditor: View {
    @Binding var segment: WorkoutSegment

    var body: some View {
        Form {
            Section("Segment") {
                if segment.type == .rest {
                    LabeledContent("Type", value: WorkoutSegmentType.rest.displayName)
                    numberField(
                        "Rest duration in seconds",
                        value: $segment.durationSeconds
                    )
                    Text(
                        "This recovery occurs once at this point in the workout. Add separate Rest segments when recovery times vary."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if hasIncompatibleRestContent {
                        Label(
                            "This older Rest segment contains incompatible work details.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        Button("Remove incompatible work details", role: .destructive) {
                            segment.rounds = nil
                            segment.restSeconds = nil
                            segment.movements = []
                        }
                    }
                } else {
                    Picker("Type", selection: $segment.type) {
                        ForEach(WorkoutSegmentType.allCases.filter { $0 != .rest }) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    numberField("Rounds", value: $segment.rounds)
                    numberField("Duration in seconds", value: $segment.durationSeconds)
                    numberField(restFieldTitle, value: $segment.restSeconds)
                    Text(restExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledFormMultilineField(
                    title: "Notes and targets",
                    text: $segment.notes
                )
            }
        }
        .navigationTitle("Segment Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasIncompatibleRestContent: Bool {
        segment.rounds != nil || segment.restSeconds != nil || !segment.movements.isEmpty
    }

    private var restFieldTitle: String {
        guard segment.type == .work else { return "Rest after segment in seconds" }
        return segment.rounds == nil
            ? "Rest between efforts in seconds" : "Rest between rounds in seconds"
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
    @Binding var movement: MovementPrescription
    let definitions: [MovementDefinition]

    var body: some View {
        Form {
            Section("Movement") {
                LabeledFormTextField(
                    title: "Display name",
                    text: $movement.displayName,
                    prompt: "Required"
                )
                NavigationLink {
                    MovementSelectionView(movement: $movement, definitions: definitions)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose from your movements")
                        Text(selectedMovementName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Prescription") {
                numberField("Repetitions", value: $movement.repetitions)
                numberField("Distance in meters", value: $movement.distanceMeters)
                numberField("Calories", value: $movement.calories)
                decimalField("Load", value: $movement.loadValue)
                LabeledFormTextField(
                    title: "Load unit",
                    text: optionalString($movement.loadUnit)
                )
                decimalField("Percent of 1RM", value: $movement.percentageOfOneRepMax)
                numberField("Duration in seconds", value: $movement.durationSeconds)
                LabeledFormTextField(
                    title: "Tempo",
                    text: optionalString($movement.tempo)
                )
                LabeledFormMultilineField(title: "Notes", text: $movement.notes)
            }
        }
        .navigationTitle("Movement")
        .navigationBarTitleDisplayMode(.inline)
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
        LabeledFormTextField(
            title: title,
            text: optionalDouble(value),
            keyboardType: .decimalPad
        )
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0).flatMap { $0 > 0 ? $0 : nil } }
        )
    }

    private func optionalDouble(_ value: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map { $0.formatted() } ?? "" },
            set: { value.wrappedValue = Double($0).flatMap { $0 > 0 ? $0 : nil } }
        )
    }

    private func optionalString(_ value: Binding<String?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct MovementSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var movement: MovementPrescription
    let definitions: [MovementDefinition]
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Button("Use a new personal movement") {
                    movement.canonicalMovementID = nil
                    dismiss()
                }
            } footer: {
                Text("Enter its clean name on the previous screen; it will be remembered on save.")
            }
            Section("Your Movements") {
                ForEach(filteredDefinitions) { definition in
                    Button {
                        movement.canonicalMovementID = definition.id
                        movement.displayName = definition.canonicalName
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.canonicalName)
                                .foregroundStyle(.primary)
                            Text(definition.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Movement")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Name or alias")
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
