import SwiftUI

struct TrainingView: View {
    let parser: any WorkoutParser
    let scalingEngine: any WorkoutScalingEngine
    let workoutRepository: any WorkoutRepository
    let assessmentRepository: any AssessmentRepository
    let movementLibrary: any MovementLibraryRepository

    @State private var rawText = ""
    @State private var plans: [WorkoutPlan] = []
    @State private var completedWorkouts: [CompletedWorkout] = []
    @State private var restrictions: [RestrictionProfile] = []
    @State private var evaluations: [String: WorkoutEvaluation] = [:]
    @State private var editingPlan: WorkoutPlan?
    @State private var completingPlan: WorkoutPlan?
    @State private var planPendingDeletion: WorkoutPlan?
    @State private var isParsing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FoundationCard(title: "Plan a Workout") {
                        Text(
                            "Paste CrossFit, weightlifting, or conditioning text. You’ll review every parsed field before it is saved."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        TextEditor(text: $rawText)
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("raw-workout-entry")
                        Button {
                            Task { await parseWorkout() }
                        } label: {
                            if isParsing {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Parse and review", systemImage: "text.magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            isParsing
                                || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("parse-workout")
                        Button("Enter manually") { editingPlan = manualPlan() }
                            .frame(maxWidth: .infinity)
                    }

                    FoundationCard(title: "Your Movements") {
                        Text(
                            "Search movements you have used, maintain stable details, or import movement names from WOD Lab."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        NavigationLink {
                            MovementLibraryView(repository: movementLibrary)
                        } label: {
                            Label(
                                "Open movement library",
                                systemImage: "figure.strengthtraining.traditional"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("movement-library-link")
                    }

                    if plans.filter({ $0.status != .completed }).isEmpty {
                        FoundationCard(title: "Planned") {
                            ContentUnavailableView(
                                "No planned workout",
                                systemImage: "figure.strengthtraining.traditional",
                                description: Text("Paste a workout above or enter it manually.")
                            )
                        }
                    } else {
                        ForEach(plans.filter { $0.status != .completed }) { plan in
                            planCard(plan)
                        }
                    }

                    if !completedWorkouts.isEmpty {
                        FoundationCard(title: "Recent Actual Work") {
                            ForEach(completedWorkouts) { workout in
                                NavigationLink {
                                    CompletedWorkoutDetailView(workout: workout) {
                                        try await workoutRepository.deleteCompletedWorkout(
                                            id: workout.id
                                        )
                                        await load()
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(workout.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(
                                                "RPE \(workout.sessionRPE)/10 · Post-session pain \(workout.postSessionPain)/10"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 12)
                                        VStack(alignment: .trailing, spacing: 6) {
                                            Text(
                                                workout.startedAt,
                                                format: .dateTime.month().day()
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            Image(systemName: "chevron.forward")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "View completed workout: \(workout.title)"
                                )
                                if workout.id != completedWorkouts.last?.id { Divider() }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Train")
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $editingPlan) { plan in
                WorkoutPlanEditorView(
                    plan: plan,
                    restrictions: restrictions,
                    scalingEngine: scalingEngine,
                    movementLibrary: movementLibrary
                ) { saved in
                    await savePlan(saved)
                }
            }
            .sheet(item: $completingPlan) { plan in
                WorkoutCompletionView(plan: plan) { workout in
                    await saveCompleted(workout)
                }
            }
            .alert("Couldn’t update the workout", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .confirmationDialog(
                "Delete this workout plan?",
                isPresented: planDeletionIsPresented,
                titleVisibility: .visible,
                presenting: planPendingDeletion
            ) { plan in
                Button("Delete plan", role: .destructive) {
                    Task { await deletePlan(plan) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the plan. Any completed workout stays in your history.")
            }
        }
    }

    @ViewBuilder
    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                WorkoutPlanDetailView(plan: plan, evaluation: evaluations[plan.id])
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(plan.title)
                            .font(.headline)
                        Spacer(minLength: 12)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    HStack {
                        Label(plan.format.displayName, systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text(plan.scheduledAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(plan.intendedStimulus.primary)
                        .font(.subheadline)
                    ForEach(plan.movements.prefix(6)) { movement in
                        HStack {
                            Text(movement.displayName)
                            Spacer()
                            Text(movementSummary(movement))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if plan.movements.count > 6 {
                        Text("+ \(plan.movements.count - 6) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let evaluation = evaluations[plan.id] {
                        Divider()
                        Label(
                            evaluation.recommendation.displayName,
                            systemImage: evaluation.recommendation.symbolName
                        )
                        .font(.headline)
                        if let hardConflict = evaluation.conflicts.first(where: {
                            $0.severity == .hard
                        }) {
                            Text(hardConflict.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        } else if let conflict = evaluation.conflicts.first {
                            Text(conflict.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View workout details: \(plan.title)")
            .accessibilityIdentifier("workout-plan-details-\(plan.id)")
            Divider()
            HStack {
                Button("Edit") { editingPlan = plan }
                    .buttonStyle(.bordered)
                Button("Record actual") { completingPlan = plan }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Menu {
                    Button("Delete plan", role: .destructive) {
                        planPendingDeletion = plan
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var planDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { planPendingDeletion != nil },
            set: { if !$0 { planPendingDeletion = nil } }
        )
    }

    @MainActor
    private func parseWorkout() async {
        isParsing = true
        defer { isParsing = false }
        do {
            let parsed = try await parser.parse(rawText: rawText)
            editingPlan = WorkoutPlan(parsed: parsed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func manualPlan() -> WorkoutPlan {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let movement = MovementPrescription(
            id: UUID().uuidString.lowercased(),
            canonicalMovementID: nil,
            displayName: source.isEmpty ? "Movement" : source,
            originalText: source,
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
        let parsed = ParsedWorkout(
            title: "Manual workout",
            rawText: source.isEmpty ? "Manual workout" : source,
            format: .manual,
            timeCapSeconds: nil,
            intendedStimulus: .unknown,
            segments: [
                WorkoutSegment(
                    id: UUID().uuidString.lowercased(),
                    sequence: 1,
                    type: .work,
                    rounds: nil,
                    durationSeconds: nil,
                    restSeconds: nil,
                    notes: "",
                    movements: [movement]
                )
            ],
            ambiguities: [],
            parserConfidence: 1,
            parserVersion: "manual-1.0.0",
            modelVersion: nil
        )
        return WorkoutPlan(parsed: parsed)
    }

    @MainActor
    private func load() async {
        do {
            try await assessmentRepository.prepareDefaults()
            try await movementLibrary.prepareDefaults()
            restrictions = try await assessmentRepository.restrictions()
            plans = try await workoutRepository.plans()
            completedWorkouts = try await workoutRepository.completedWorkouts()
            var nextEvaluations: [String: WorkoutEvaluation] = [:]
            for plan in plans where plan.status != .completed {
                nextEvaluations[plan.id] = await scalingEngine.evaluate(
                    plan: plan,
                    restrictions: restrictions
                )
            }
            evaluations = nextEvaluations
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePlan(_ plan: WorkoutPlan) async -> Bool {
        do {
            let reconciled = try await movementLibrary.reconcile(plan)
            try await workoutRepository.savePlan(reconciled)
            rawText = ""
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func saveCompleted(_ workout: CompletedWorkout) async -> Bool {
        do {
            try await workoutRepository.saveCompletedWorkout(workout)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func deletePlan(_ plan: WorkoutPlan) async {
        do {
            try await workoutRepository.deletePlan(id: plan.id)
            planPendingDeletion = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func movementSummary(_ movement: MovementPrescription) -> String {
        if let distance = movement.distanceMeters { return "\(distance) m" }
        if let calories = movement.calories { return "\(calories) cal" }
        var result = movement.repetitions.map { "\($0) reps" } ?? "Review"
        if let load = movement.loadValue {
            result += " @ \(load.formatted()) \(movement.loadUnit ?? "")"
        }
        return result
    }
}

private struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlan
    let evaluation: WorkoutEvaluation?

    var body: some View {
        List {
            Section("Workout overview") {
                LabeledContent("Format", value: plan.format.displayName)
                LabeledContent("Scheduled") {
                    Text(
                        plan.scheduledAt,
                        format: .dateTime.weekday().month().day().hour().minute()
                    )
                }
                LabeledContent("Status", value: statusName)
                if let timeCap = plan.timeCapSeconds {
                    LabeledContent("Time cap", value: "\(timeCap / 60) min")
                }
            }

            Section("Intended stimulus") {
                Text(plan.intendedStimulus.primary)
                ForEach(Array(plan.intendedStimulus.secondary.enumerated()), id: \.offset) {
                    item in
                    Label(item.element, systemImage: "target")
                        .foregroundStyle(.secondary)
                }
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conflict.severity == .hard ? "Must modify" : "Use caution")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(conflict.severity == .hard ? .red : .orange)
                            Text(conflict.explanation)
                            Text(conflict.preservedStimulus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(conflict.compromise)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(plan.segments) { segment in
                Section("Segment \(segment.sequence) · \(segment.type.displayName)") {
                    segmentStructure(segment)
                    if !segment.notes.isEmpty {
                        LabeledContent("Notes and targets") {
                            Text(segment.notes)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    ForEach(segment.movements) { movement in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(movement.displayName)
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier(
                                    "planned-movement-name-\(movement.id)"
                                )
                            Text(prescriptionSummary(movement))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier(
                                    "planned-movement-prescription-\(movement.id)"
                                )
                            if movement.originalText != movement.displayName,
                                !movement.originalText.isEmpty
                            {
                                Text("Entered as: \(movement.originalText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !movement.notes.isEmpty {
                                Text(movement.notes)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            Section("Parsing") {
                LabeledContent("Parser", value: plan.parserVersion)
                LabeledContent(
                    "Confidence",
                    value: plan.confidence.formatted(.percent.precision(.fractionLength(0)))
                )
                if !plan.ambiguities.isEmpty {
                    ForEach(plan.ambiguities) { ambiguity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ambiguity.originalText)
                            Text(ambiguity.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Original source") {
                DisclosureGroup("Show pasted workout") {
                    Text(plan.rawText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityIdentifier("workout-plan-detail")
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func segmentStructure(_ segment: WorkoutSegment) -> some View {
        if segment.type == .rest {
            LabeledContent(
                "Rest duration",
                value: segment.durationSeconds.map { "\($0) sec" } ?? "Missing"
            )
        } else {
            if let rounds = segment.rounds {
                LabeledContent("Rounds", value: rounds.formatted())
            }
            if let duration = segment.durationSeconds {
                LabeledContent("Duration", value: "\(duration) sec")
            }
            if let rest = segment.restSeconds {
                LabeledContent(uniformRestLabel(segment), value: "\(rest) sec")
            }
        }
    }

    private func uniformRestLabel(_ segment: WorkoutSegment) -> String {
        guard segment.type == .work else { return "Rest after segment" }
        return segment.rounds == nil ? "Rest between efforts" : "Rest between rounds"
    }

    private func prescriptionSummary(_ movement: MovementPrescription) -> String {
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
        if let tempo = movement.tempo { values.append("Tempo \(tempo)") }
        return values.isEmpty ? "No quantity entered" : values.joined(separator: " · ")
    }

    private var statusName: String {
        switch plan.status {
        case .draft: "Draft"
        case .planned: "Planned"
        case .completed: "Completed"
        }
    }
}

private struct CompletedWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: CompletedWorkout
    let onDelete: () async throws -> Void

    @State private var isConfirmingDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Started") {
                    Text(
                        workout.startedAt,
                        format: .dateTime.weekday().month().day().hour().minute()
                    )
                }
                LabeledContent("Ended") {
                    Text(workout.endedAt, format: .dateTime.hour().minute())
                }
                LabeledContent("Duration", value: durationDescription)
                LabeledContent("Session RPE", value: "\(workout.sessionRPE)/10")
                LabeledContent("Post-session pain", value: "\(workout.postSessionPain)/10")
                if !workout.notes.isEmpty {
                    LabeledContent("Notes") {
                        Text(workout.notes)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Actual work") {
                if workout.movements.isEmpty {
                    Text("No movement results were recorded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(workout.movements) { movement in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(movement.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(actualSummary(movement))
                            .foregroundStyle(.secondary)
                        Text("Pain during: \(movement.painDuring)/10")
                            .font(.caption)
                        if !movement.modification.isEmpty {
                            Text("Modification: \(movement.modification)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !movement.notes.isEmpty {
                            Text(movement.notes)
                                .font(.caption)
                        }
                    }
                }
            }

            Section {
                Button("Delete completed workout", role: .destructive) {
                    isConfirmingDeletion = true
                }
            } footer: {
                Text("Deleting removes this workout from your history and trend calculations.")
            }
        }
        .accessibilityIdentifier("completed-workout-detail")
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this completed workout?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete workout", role: .destructive) {
                Task { await deleteWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the workout and its movement results. This cannot be undone.")
        }
        .alert("Couldn’t delete workout", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var durationDescription: String {
        let seconds = max(0, Int(workout.endedAt.timeIntervalSince(workout.startedAt)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes) min"
    }

    private func actualSummary(_ movement: CompletedMovement) -> String {
        var values: [String] = []
        if let repetitions = movement.actualRepetitions { values.append("\(repetitions) reps") }
        if let distance = movement.actualDistanceMeters { values.append("\(distance) m") }
        if let load = movement.actualLoadValue {
            values.append(
                [load.formatted(), movement.actualLoadUnit].compactMap { $0 }.joined(separator: " ")
            )
        }
        if let duration = movement.actualDurationSeconds { values.append("\(duration) sec") }
        return values.isEmpty ? "No result entered" : values.joined(separator: " · ")
    }

    @MainActor
    private func deleteWorkout() async {
        do {
            try await onDelete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

#Preview {
    TrainingView(
        parser: VersionedWorkoutParser(),
        scalingEngine: DeterministicWorkoutScalingEngine(),
        workoutRepository: PreviewWorkoutRepository(),
        assessmentRepository: PreviewAssessmentRepository(),
        movementLibrary: PreviewMovementLibraryRepository()
    )
}
