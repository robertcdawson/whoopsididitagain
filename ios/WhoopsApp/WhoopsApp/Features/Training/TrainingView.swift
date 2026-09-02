import SwiftUI

struct TrainingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: UUID?
    let parser: any WorkoutParser
    let scalingEngine: any WorkoutScalingEngine
    let workoutRepository: any WorkoutRepository
    let assessmentRepository: any AssessmentRepository
    let movementLibrary: any MovementLibraryRepository
    let protocolParser: any ProtocolParser
    let protocolRepository: any ProtocolRepository
    var docketRepository: (any DocketRepository)? = nil

    @State private var rawText = ""
    @State private var showingComposer = false
    @State private var protocolPendingDeletion: TherapyProtocol?
    @State private var weekCompletions: [DocketCompletion] = []
    @State private var plans: [WorkoutPlan] = []
    @State private var completedWorkouts: [CompletedWorkout] = []
    @State private var therapyProtocols: [TherapyProtocol] = []
    @State private var restrictions: [RestrictionProfile] = []
    @State private var evaluations: [String: WorkoutEvaluation] = [:]
    @State private var editingPlan: WorkoutPlan?
    @State private var completingPlan: WorkoutPlan?
    @State private var isCapturingProtocol = false
    @State private var planPendingDeletion: WorkoutPlan?
    @State private var isParsing = false
    @State private var parsingTask: Task<Void, Never>?
    @State private var parsingID: UUID?
    @AppStorage("appleWorkoutParsingEnabled") private var appleParsingEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            JournalPage(title: "Work") {
                if therapyProtocols.isEmpty {
                    JournalTapeCard {
                        Text("your PT sheet belongs here").font(.journal(.title2, weight: .bold))
                        Text("Capture a protocol to put your prescribed work on the docket.")
                            .font(.journal(.subheadline))
                        captureProtocolButton
                    }
                } else {
                    ForEach(therapyProtocols) { therapyProtocol in
                        JournalTapeCard { protocolRow(therapyProtocol) }
                    }
                    captureProtocolButton
                }
                JournalRule()
                JournalSection(title: "training") {
                    if plans.filter({ $0.status != .completed }).isEmpty {
                        Text("Nothing planned yet.").italic()
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                    }
                    ForEach(plans.filter { $0.status != .completed }) { plan in
                        planCard(plan)
                    }
                }
                Button {
                    focusedField = nil
                    showingComposer.toggle()
                } label: {
                    HStack {
                        Text("Paste a workout")
                        Spacer()
                        Image(systemName: showingComposer ? "chevron.down" : "chevron.right")
                            .font(.journal(.caption, weight: .semibold))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(JournalLinkButtonStyle())
                .font(.journal(.subheadline))
                .accessibilityValue(showingComposer ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("workout-composer")
                if showingComposer {
                    JournalSection(title: "") {
                        Text(
                            "Paste CrossFit, weightlifting, or conditioning text. You’ll review every parsed field before it is saved."
                        )
                        .font(.journal(.subheadline))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                        TextEditor(text: $rawText)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .journalInput()
                            .formKeyboardField(dismissOnSubmit: false)
                            .accessibilityIdentifier("raw-workout-entry")
                            .disabled(isParsing)
                        if FeatureFlags.appleWorkoutParserTestModeEnabled() {
                            Toggle(
                                "Try Apple Intelligence (experimental)", isOn: $appleParsingEnabled
                            )
                            .disabled(isParsing)
                            .accessibilityIdentifier("apple-workout-parsing-toggle")
                            Text(
                                "Synthetic simulator test mode. Apple parsing is unavailable in normal phone runs."
                            )
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                        } else {
                            Text("Parsed locally with the built-in parser.")
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                        Button {
                            startParsing()
                        } label: {
                            if isParsing {
                                ProgressView("Parsing workout…").frame(maxWidth: .infinity)
                            } else {
                                Label("Parse and review", systemImage: "text.magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(JournalPrimaryButtonStyle())
                        .disabled(
                            isParsing
                                || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("parse-workout")
                        if isParsing {
                            Button("Cancel parsing") { cancelParsing() }
                                .accessibilityIdentifier("cancel-workout-parsing")
                        }
                        Button("Enter manually") {
                            focusedField = nil
                            cancelParsing()
                            editingPlan = manualPlan()
                        }
                        .frame(maxWidth: .infinity)
                    }

                }
                Text("Your workout gets checked against your restrictions.")
                    .font(.journal(.footnote)).italic().foregroundStyle(Color.journalRedPen)
                if !completedWorkouts.isEmpty {
                    JournalSection(title: "Recent Actual Work") {
                        ForEach(completedWorkouts) { workout in
                            NavigationLink {
                                CompletedWorkoutDetailView(
                                    workout: workout, movementLibrary: movementLibrary,
                                    onSave: { await saveCompleted($0) }
                                ) {
                                    try await workoutRepository.deleteCompletedWorkout(
                                        id: workout.id
                                    )
                                    await load()
                                }
                            } label: {
                                completedWorkoutRowLayout {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workout.title)
                                            .font(.journal(.subheadline, weight: .semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .accessibilityIdentifier(
                                                "completed-workout-summary-title-\(workout.id)")
                                        Text(
                                            "RPE \(workout.sessionRPE)/10 · Post-session pain \(workout.postSessionPain)/10"
                                        )
                                        .font(.journal(.caption))
                                        .foregroundStyle(Color.journalInk.opacity(0.7))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if !dynamicTypeSize.isAccessibilitySize {
                                        Spacer(minLength: 12)
                                    }
                                    completedWorkoutMetadataLayout {
                                        Text(
                                            workout.startedAt,
                                            format: .dateTime.month().day()
                                        )
                                        .font(.journal(.caption))
                                        .foregroundStyle(Color.journalInk.opacity(0.7))
                                        Image(systemName: "chevron.forward")
                                            .font(.journal(.caption, weight: .semibold))
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
                Spacer(minLength: 12)
                NavigationLink {
                    MovementLibraryView(repository: movementLibrary)
                } label: {
                    Text("your movements →").underline().frame(minHeight: 44)
                }
                .accessibilityLabel("Open movement library")
                .accessibilityIdentifier("movement-library-link")
            }
            .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
            .onDisappear { cancelParsing() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { cancelParsing() }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: editingPlan?.id) { _, _ in focusedField = nil }
            .onChange(of: completingPlan?.id) { _, _ in focusedField = nil }
            .sheet(item: $editingPlan, onDismiss: { focusedField = nil }) { plan in
                WorkoutPlanEditorView(
                    plan: plan,
                    restrictions: restrictions,
                    scalingEngine: scalingEngine,
                    movementLibrary: movementLibrary
                ) { saved in
                    await savePlan(saved)
                }
            }
            .sheet(item: $completingPlan, onDismiss: { focusedField = nil }) { plan in
                WorkoutCompletionView(plan: plan, movementLibrary: movementLibrary) { workout in
                    await saveCompleted(workout)
                }
            }
            .fullScreenCover(
                isPresented: $isCapturingProtocol, onDismiss: { focusedField = nil }
            ) {
                ProtocolCaptureView(
                    parser: protocolParser,
                    scalingEngine: scalingEngine,
                    movementLibrary: movementLibrary,
                    protocolRepository: protocolRepository,
                    restrictions: restrictions
                ) {
                    await load()
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
            .confirmationDialog(
                "Delete this PT protocol?",
                isPresented: Binding(
                    get: { protocolPendingDeletion != nil },
                    set: { if !$0 { protocolPendingDeletion = nil } }
                ), titleVisibility: .visible
            ) {
                Button("Delete protocol", role: .destructive) {
                    if let value = protocolPendingDeletion { Task { await deleteProtocol(value) } }
                }
                Button("Cancel", role: .cancel) { protocolPendingDeletion = nil }
            } message: {
                Text("The protocol will leave your docket. This cannot be undone.")
            }
        }
    }

    private var captureProtocolButton: some View {
        Button {
            focusedField = nil
            cancelParsing()
            isCapturingProtocol = true
        } label: {
            Label("New protocol from PT sheet", systemImage: "camera.viewfinder")
                .font(.journal(.subheadline)).frame(minHeight: 44)
        }
        .accessibilityIdentifier("new-protocol")
    }

    private var completedWorkoutRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }

    private var completedWorkoutMetadataLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
    }

    private func protocolRow(_ therapyProtocol: TherapyProtocol) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            protocolHeaderLayout {
                Text(therapyProtocol.title)
                    .font(
                        .journal(
                            dynamicTypeSize.isAccessibilitySize ? .headline : .title2,
                            weight: .bold))
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Menu {
                    Button("Delete protocol", role: .destructive) {
                        protocolPendingDeletion = therapyProtocol
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Protocol actions: \(therapyProtocol.title)")
            }
            Text(protocolSummary(therapyProtocol))
                .font(.journal(.subheadline)).foregroundStyle(Color.journalInk.opacity(0.75))
            Text(
                "Started \(therapyProtocol.startedAt.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.journal(.caption)).foregroundStyle(Color.journalInk.opacity(0.7))
            JournalRule()
            ForEach(therapyProtocol.items) { item in
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        [item.displayName, item.prescriptionSummary, item.cadence.displayName]
                            .compactMap { $0 }.joined(separator: " · "))
                    Spacer(minLength: 4)
                    if weekCompletions.contains(where: {
                        $0.sourceID == item.id
                            && $0.day == DeterministicDocketEngine().day(containing: .now)
                    }) {
                        DrawnCheckmarkView().accessibilityHidden(false).accessibilityLabel(
                            "Completed today")
                    }
                }
                .font(.journal(.subheadline))
            }
            Text(
                "\(weekCompletions.filter { $0.protocolID == therapyProtocol.id }.count) item completions this calendar week"
            )
            .font(.journal(.footnote)).italic().foregroundStyle(Color.journalRedPen)
        }
        .accessibilityIdentifier("therapy-protocol-\(therapyProtocol.id)")
    }

    private var protocolHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    private func protocolSummary(_ therapyProtocol: TherapyProtocol) -> String {
        var parts: [String] = []
        if let phase = therapyProtocol.phaseSummary { parts.append(phase) }
        let count = therapyProtocol.items.count
        parts.append("\(count) item\(count == 1 ? "" : "s")")
        if let milestone = therapyProtocol.unlockMilestone {
            parts.append("until \(milestone)")
        }
        return parts.joined(separator: " · ")
    }

    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                WorkoutPlanDetailView(
                    plan: plan, evaluation: evaluations[plan.id], restrictions: restrictions,
                    scalingEngine: scalingEngine, movementLibrary: movementLibrary,
                    onSave: { await savePlan($0) })
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.journal(.headline, weight: .semibold))
                    Text(plan.scheduledAt, format: .dateTime.month().day().hour().minute())
                        .font(.journal(.caption)).foregroundStyle(Color.journalInk.opacity(0.7))
                    if let evaluation = evaluations[plan.id], !evaluation.conflicts.isEmpty {
                        Label(evaluation.recommendation.displayName, systemImage: "hand.raised")
                            .font(.journal(.caption)).foregroundStyle(Color.journalRedPen)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View workout details: \(plan.title)")
            .accessibilityIdentifier("workout-plan-details-\(plan.id)")
            HStack {
                Button("Edit") {
                    focusedField = nil
                    editingPlan = plan
                }
                .accessibilityIdentifier("edit-workout-plan-\(plan.id)")
                Button("Record actual") {
                    focusedField = nil
                    completingPlan = plan
                }
                .accessibilityIdentifier("record-actual-workout-\(plan.id)")
                Spacer()
                Menu {
                    Button("Delete plan", role: .destructive) {
                        focusedField = nil
                        planPendingDeletion = plan
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
            }
            .font(.journal(.caption))
            .buttonStyle(.bordered)
        }
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
    private func startParsing() {
        focusedField = nil
        cancelParsing()
        let id = UUID()
        parsingID = id
        let source = rawText
        isParsing = true
        errorMessage = nil
        parsingTask = Task {
            defer {
                if parsingID == id {
                    isParsing = false
                    parsingTask = nil
                    parsingID = nil
                }
            }
            do {
                let parsed = try await parser.parse(rawText: source)
                try Task.checkCancellation()
                guard parsingID == id else { return }
                editingPlan = WorkoutPlan(parsed: parsed)
            } catch {
                guard parsingID == id, !Task.isCancelled, !(error is CancellationError) else {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func cancelParsing() {
        parsingTask?.cancel()
        parsingTask = nil
        parsingID = nil
        isParsing = false
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
        if let docketRepository {
            do {
                weekCompletions = try await docketRepository.completions(
                    days: DeterministicDocketEngine().weekDays(containing: .now))
            } catch { errorMessage = error.localizedDescription }
        }
        do {
            try await assessmentRepository.prepareDefaults()
            try await movementLibrary.prepareDefaults()
            restrictions = try await assessmentRepository.restrictions()
            plans = try await workoutRepository.plans()
            completedWorkouts = try await workoutRepository.completedWorkouts()
            therapyProtocols = try await protocolRepository.protocols(includeArchived: false)
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
            showingComposer = false
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

    @MainActor
    private func deleteProtocol(_ therapyProtocol: TherapyProtocol) async {
        do {
            try await protocolRepository.deleteProtocol(id: therapyProtocol.id)
            protocolPendingDeletion = nil
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
    @State private var plan: WorkoutPlan
    @State private var evaluation: WorkoutEvaluation?
    @State private var isEditing = false
    let restrictions: [RestrictionProfile]
    let scalingEngine: any WorkoutScalingEngine
    let movementLibrary: any MovementLibraryRepository
    let onSave: (WorkoutPlan) async -> Bool

    init(
        plan: WorkoutPlan, evaluation: WorkoutEvaluation?, restrictions: [RestrictionProfile],
        scalingEngine: any WorkoutScalingEngine, movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (WorkoutPlan) async -> Bool
    ) {
        _plan = State(initialValue: plan)
        _evaluation = State(initialValue: evaluation)
        self.restrictions = restrictions
        self.scalingEngine = scalingEngine
        self.movementLibrary = movementLibrary
        self.onSave = onSave
    }

    var body: some View {
        JournalList {
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
                    LabeledContent(
                        "Time cap", value: WorkoutDurationInput.summary(seconds: timeCap))
                }
            }

            if let result = plan.reportedResult {
                Section("Reported result") {
                    LabeledContent("Completed rounds", value: String(result.completedRounds))
                    LabeledContent("Additional reps", value: String(result.additionalRepetitions))
                }
            }

            Section("Intended stimulus") {
                Text(plan.intendedStimulus.primary)
                if let minimum = plan.intendedStimulus.estimatedDurationMinimumMinutes {
                    LabeledContent(
                        "Estimated minimum",
                        value: WorkoutDurationInput.summary(seconds: minimum * 60))
                }
                if let maximum = plan.intendedStimulus.estimatedDurationMaximumMinutes {
                    LabeledContent(
                        "Estimated maximum",
                        value: WorkoutDurationInput.summary(seconds: maximum * 60))
                }
                ForEach(Array(plan.intendedStimulus.secondary.enumerated()), id: \.offset) {
                    item in
                    Label(item.element, systemImage: "target")
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conflict.severity == .hard ? "Must modify" : "Use caution")
                                .font(.journal(.subheadline, weight: .semibold))
                                .foregroundStyle(
                                    conflict.severity == .hard
                                        ? Color.journalRedPen : .journalAmberText)
                            Text(conflict.explanation)
                            Text(conflict.preservedStimulus)
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                            Text(conflict.compromise)
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                    }
                }
            }

            ForEach(plan.segments) { segment in
                Section("Segment \(segment.sequence) · \(segment.type.displayName)") {
                    segmentStructure(segment)
                    let notes = plan.visibleNotes(segment.notes)
                    if !notes.isEmpty {
                        LabeledContent("Notes and targets") {
                            Text(notes)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    ForEach(segment.movements) { movement in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(movement.displayName)
                                .font(.journal(.subheadline, weight: .semibold))
                                .accessibilityIdentifier(
                                    "planned-movement-name-\(movement.id)"
                                )
                            Text(prescriptionSummary(movement))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                                .accessibilityIdentifier(
                                    "planned-movement-prescription-\(movement.id)"
                                )
                            if let total = plan.effectiveReportedRepetitionTotals[movement.id] {
                                Text(
                                    "Reported total: \(total) reps\(plan.reportedRepetitionOverrides[movement.id] == nil ? "" : " (edited)")"
                                )
                                .font(.journal(.caption))
                            }
                            if movement.originalText != movement.displayName,
                                !movement.originalText.isEmpty
                            {
                                Text("Entered as: \(movement.originalText)")
                                    .font(.journal(.caption))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
                            }
                            if !movement.notes.isEmpty {
                                Text(movement.notes)
                                    .font(.journal(.caption))
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
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("edit-planned-workout")
            }
        }
        .sheet(isPresented: $isEditing) {
            WorkoutPlanEditorView(
                plan: plan, restrictions: restrictions,
                scalingEngine: scalingEngine, movementLibrary: movementLibrary
            ) { updated in
                guard await onSave(updated) else { return false }
                plan = updated
                evaluation = await scalingEngine.evaluate(plan: updated, restrictions: restrictions)
                return true
            }
        }
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func segmentStructure(_ segment: WorkoutSegment) -> some View {
        if segment.type == .rest {
            LabeledContent(
                "Rest duration",
                value: segment.durationSeconds.map { WorkoutDurationInput.summary(seconds: $0) }
                    ?? "Missing"
            )
        } else {
            if let rounds = segment.rounds {
                LabeledContent("Rounds", value: rounds.formatted())
            }
            if let duration = segment.durationSeconds {
                LabeledContent("Duration", value: WorkoutDurationInput.summary(seconds: duration))
            }
            if let rest = segment.restSeconds {
                LabeledContent(
                    uniformRestLabel(segment), value: WorkoutDurationInput.summary(seconds: rest))
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
        if let duration = movement.durationSeconds {
            values.append(WorkoutDurationInput.summary(seconds: duration))
        }
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
    @State private var workout: CompletedWorkout
    let movementLibrary: any MovementLibraryRepository
    let onSave: (CompletedWorkout) async -> Bool
    let onDelete: () async throws -> Void

    @State private var isEditing = false
    @State private var isConfirmingDeletion = false
    @State private var errorMessage: String?

    init(
        workout: CompletedWorkout, movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (CompletedWorkout) async -> Bool,
        onDelete: @escaping () async throws -> Void
    ) {
        _workout = State(initialValue: workout)
        self.movementLibrary = movementLibrary
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        JournalList {
            Section("Session") {
                Text(workout.title)
                    .font(.journal(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("completed-workout-title")
                LabeledContent("Started") {
                    Text(
                        workout.startedAt,
                        format: .dateTime.weekday().month().day().hour().minute()
                    )
                }
                LabeledContent("Ended") {
                    Text(workout.endedAt, format: .dateTime.month().day().hour().minute())
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

            if let result = workout.reportedResult {
                Section("Reported result") {
                    Text(result.summary)
                }
            }

            Section("Actual work") {
                if workout.movements.isEmpty {
                    Text("No movement results were recorded.")
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
                ForEach(workout.movements) { movement in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(movement.displayName)
                            .font(.journal(.subheadline, weight: .semibold))
                        Text(actualSummary(movement))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                        Text("Pain during: \(movement.painDuring)/10")
                            .font(.journal(.caption))
                        if !movement.modification.isEmpty {
                            Text("Modification: \(movement.modification)")
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                        if !movement.notes.isEmpty {
                            Text(movement.notes)
                                .font(.journal(.caption))
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("edit-completed-workout")
            }
        }
        .sheet(isPresented: $isEditing) {
            WorkoutCompletionView(workout: workout, movementLibrary: movementLibrary) { updated in
                guard await onSave(updated) else { return false }
                workout = updated
                return true
            }
        }
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
        WorkoutDurationInput.summary(seconds: max(0, workout.durationSeconds))
    }

    private func actualSummary(_ movement: CompletedMovement) -> String {
        var values: [String] = []
        if let repetitions = movement.actualRepetitions { values.append("\(repetitions) reps") }
        if let distance = movement.actualDistanceMeters { values.append("\(distance) m") }
        if let calories = movement.actualCalories { values.append("\(calories) cal") }
        if let load = movement.actualLoadValue {
            values.append(
                [load.formatted(), movement.actualLoadUnit].compactMap { $0 }.joined(separator: " ")
            )
        }
        if let duration = movement.actualDurationSeconds {
            values.append(WorkoutDurationInput.summary(seconds: duration))
        }
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
        movementLibrary: PreviewMovementLibraryRepository(),
        protocolParser: DeterministicProtocolParser(),
        protocolRepository: PreviewProtocolRepository()
    )
}
