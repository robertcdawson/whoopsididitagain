import SwiftUI

struct ExperimentLabView: View {
    let experimentRepository: any ExperimentRepository
    let whoopRepository: any WhoopRepository
    let healthKitRepository: any HealthKitRepository
    let assessmentRepository: any AssessmentRepository
    let workoutRepository: any WorkoutRepository

    @State private var experiments: [ExperimentDefinition] = []
    @State private var isPresentingNewExperiment = false
    @State private var isPresentingDailyLog = false
    @State private var showsArchived = false
    @State private var errorMessage: String?

    var body: some View {
        JournalList {
            Section {
                Label("Experimental feature", systemImage: "flask")
                    .font(.journal(.headline))
                Text(
                    "Results are descriptive personal associations. They do not establish causation, treatment efficacy, diagnosis, or medical advice."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            }

            Section("One daily check-in") {
                Text(
                    "At the end of a day, record what actually happened across all active experiments. This is one check-in, not one workflow per experiment. Outcomes fill from local history."
                )
                Button {
                    isPresentingDailyLog = true
                } label: {
                    Label("Log a day", systemImage: "checklist")
                }
                .disabled(activeExperiments.isEmpty)
                .accessibilityIdentifier("log-experiment-day")
                if activeExperiments.isEmpty {
                    Text("Start an experiment before logging a day.")
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
            }

            Section("Experiments") {
                if experiments.isEmpty {
                    ContentUnavailableView {
                        Label("No experiments", systemImage: "flask")
                    } description: {
                        Text("Create a structured comparison instead of relying on memory.")
                    } actions: {
                        Button("Create experiment") { isPresentingNewExperiment = true }
                            .buttonStyle(JournalPrimaryButtonStyle())
                    }
                } else {
                    ForEach(experiments) { experiment in
                        NavigationLink {
                            ExperimentDetailView(
                                experiment: experiment,
                                experimentRepository: experimentRepository,
                                whoopRepository: whoopRepository,
                                healthKitRepository: healthKitRepository,
                                assessmentRepository: assessmentRepository,
                                workoutRepository: workoutRepository
                            ) {
                                await load()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(experiment.title).font(.journal(.headline))
                                Text(experiment.primaryOutcome.displayName)
                                    .font(.journal(.subheadline))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
                                Text(experiment.status.displayName)
                                    .font(.journal(.caption))
                                    .foregroundStyle(.tint)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Experiment Lab")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(
                    showsArchived ? "Hide archived" : "Show archived",
                    systemImage: "archivebox"
                ) {
                    showsArchived.toggle()
                    Task { await load() }
                }
                Button {
                    isPresentingNewExperiment = true
                } label: {
                    Label("New experiment", systemImage: "plus")
                }
                .accessibilityIdentifier("new-experiment")
            }
        }
        .sheet(isPresented: $isPresentingNewExperiment) {
            NavigationStack {
                ExperimentEditorView(experiment: .draft()) { experiment in
                    try await experimentRepository.saveExperiment(experiment)
                    await load()
                }
            }
        }
        .sheet(isPresented: $isPresentingDailyLog) {
            NavigationStack {
                DailyExperimentLogView(
                    experiments: activeExperiments,
                    experimentRepository: experimentRepository
                ) {
                    await load()
                }
            }
        }
        .task { await load() }
        .alert("Experiment Lab issue", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func load() async {
        do {
            experiments = try await experimentRepository.experiments(
                includeArchived: showsArchived
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var activeExperiments: [ExperimentDefinition] {
        experiments.filter { $0.status == .active }
    }
}

private struct ExperimentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var experiment: ExperimentDefinition
    let experimentRepository: any ExperimentRepository
    let whoopRepository: any WhoopRepository
    let healthKitRepository: any HealthKitRepository
    let assessmentRepository: any AssessmentRepository
    let workoutRepository: any WorkoutRepository
    let onDelete: () async -> Void

    @State private var observations: [ExperimentObservation] = []
    @State private var analysis: ExperimentAnalysis?
    @State private var analysisInput: ExperimentAnalysisInput?
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisGeneration = 0
    @State private var isAnalyzing = false
    @State private var editingObservation: ExperimentObservation?
    @State private var isEditingExperiment = false
    @State private var isConfirmingExperimentDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        JournalList {
            loggingSection
            analysisSection
            observationSection
            definitionSection
            lifecycleSection
        }
        .navigationTitle(experiment.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditingExperiment = true }
            }
        }
        .sheet(isPresented: $isEditingExperiment) {
            NavigationStack {
                ExperimentEditorView(experiment: experiment) { updated in
                    try await experimentRepository.saveExperiment(updated)
                    experiment = updated
                    scheduleAnalysisRefresh(for: observations)
                }
            }
        }
        .sheet(item: $editingObservation) { observation in
            NavigationStack {
                ExperimentObservationEditorView(
                    observation: observation,
                    experiment: experiment,
                    existingObservations: observations,
                    analysisInput: analysisInput
                ) { updated, originalID in
                    if let originalID {
                        try await experimentRepository.replaceObservation(
                            id: originalID,
                            with: updated
                        )
                        observations.removeAll { $0.id == originalID }
                    } else {
                        try await experimentRepository.saveObservation(updated)
                    }
                    upsertObservation(updated)
                    scheduleAnalysisRefresh(for: observations)
                } onDelete: { deleted in
                    try await experimentRepository.deleteObservation(id: deleted.id)
                    observations.removeAll { $0.id == deleted.id }
                    scheduleAnalysisRefresh(for: observations)
                }
            }
        }
        .task { await load() }
        .onDisappear { analysisTask?.cancel() }
        .alert("Experiment issue", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Delete this experiment?",
            isPresented: $isConfirmingExperimentDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete experiment and logged days", role: .destructive) {
                Task { await deleteExperiment() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes the experiment and all of its logged days. This cannot be undone."
            )
        }
    }

    private var loggingSection: some View {
        Section {
            Button {
                editingObservation = .new(
                    experimentID: experiment.id,
                    day: Self.dayKey(.now)
                )
            } label: {
                Label("Log or update a day", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("record-experiment-observation")
            Text(
                "Choose the condition that actually happened on that day. This does not schedule or promise a future action."
            )
            .font(.journal(.caption))
            .foregroundStyle(Color.journalInk.opacity(0.7))
            LabeledContent("Outcome timing", value: experiment.outcomeTiming.displayName)
            Text(experiment.outcomeTiming.explanation)
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
        } header: {
            Text("Log a day")
        }
    }

    private var definitionSection: some View {
        Section("Definition") {
            LabeledContent("Status", value: experiment.status.displayName)
            VStack(alignment: .leading, spacing: 4) {
                Text("Question").font(.journal(.caption)).foregroundStyle(
                    Color.journalInk.opacity(0.7))
                Text(experiment.question)
            }
            if !experiment.hypothesis.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hypothesis").font(.journal(.caption)).foregroundStyle(
                        Color.journalInk.opacity(0.7))
                    Text(experiment.hypothesis)
                }
            }
            LabeledContent("Condition A", value: experiment.intervention)
            LabeledContent("Condition B", value: experiment.comparisonCondition)
            LabeledContent("Primary outcome", value: experiment.primaryOutcome.displayName)
            LabeledContent("Outcome timing", value: experiment.outcomeTiming.displayName)
            LabeledContent(
                "Minimum per condition",
                value: experiment.minimumObservations.formatted()
            )
            LabeledContent(
                "Dates",
                value: dateRangeText
            )
        }
    }

    @ViewBuilder
    private var analysisSection: some View {
        Section("Deterministic analysis") {
            if let analysis {
                LabeledContent("Evidence status", value: analysis.evidenceStatus.rawValue)
                LabeledContent(
                    experiment.intervention,
                    value:
                        "\(analysis.interventionCount) usable of \(experiment.minimumObservations) · \(analysis.interventionLoggedCount) logged"
                )
                LabeledContent(
                    experiment.comparisonCondition,
                    value:
                        "\(analysis.comparisonCount) usable of \(experiment.minimumObservations) · \(analysis.comparisonLoggedCount) logged"
                )
                if analysis.evidenceStatus == .insufficientData {
                    Text(remainingText(analysis))
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
                Text(analysis.summary)
                if analysis.missingOutcomeCount > 0 {
                    Label(
                        "\(analysis.missingOutcomeCount) logged days have no \(experiment.primaryOutcome.displayName) value",
                        systemImage: "questionmark.circle"
                    )
                    .foregroundStyle(Color.journalAmberText)
                    Text(experiment.primaryOutcome.missingOutcomeExplanation)
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
                Text(analysis.caveat)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                Text(analysis.version)
                    .font(.journal(.caption2))
                    .foregroundStyle(.tertiary)
            } else if isAnalyzing {
                ProgressView("Resolving local outcomes…")
            } else {
                Text("Analysis is unavailable.").foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
    }

    private var observationSection: some View {
        Section {
            if observations.isEmpty {
                Text("No condition days recorded yet.").foregroundStyle(
                    Color.journalInk.opacity(0.7))
            } else {
                ForEach(observations) { observation in
                    Button {
                        editingObservation = observation
                    } label: {
                        ExperimentObservationRow(
                            resolved: analysis?.observations.first { $0.id == observation.id },
                            experiment: experiment
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Condition days")
        } footer: {
            Text(
                "Tap a day to correct its condition, add context, or exclude it. Saving the same date updates the existing entry."
            )
        }
    }

    private func remainingText(_ analysis: ExperimentAnalysis) -> String {
        let interventionRemaining = max(
            0,
            experiment.minimumObservations - analysis.interventionCount
        )
        let comparisonRemaining = max(
            0,
            experiment.minimumObservations - analysis.comparisonCount
        )
        return
            "Still needed with matching outcomes: \(interventionRemaining) \(experiment.intervention) days and \(comparisonRemaining) \(experiment.comparisonCondition) days."
    }

    private var lifecycleSection: some View {
        Section {
            if experiment.status == .draft {
                Button("Start experiment") { Task { await setStatus(.active) } }
            } else if experiment.status == .active {
                Button("Mark completed") { Task { await setStatus(.completed) } }
            }
            Button("Archive experiment", role: .destructive) {
                Task { await setStatus(.archived) }
            }
            Button("Delete experiment", role: .destructive) {
                isConfirmingExperimentDeletion = true
            }
        } footer: {
            Text(
                "Archive to hide this experiment and keep its logged days. Delete to remove both permanently."
            )
        }
    }

    private var dateRangeText: String {
        let start = experiment.startDate.formatted(date: .abbreviated, time: .omitted)
        guard let end = experiment.endDate else { return "From \(start)" }
        return "\(start)–\(end.formatted(date: .abbreviated, time: .omitted))"
    }

    @MainActor
    private func load() async {
        do {
            let savedObservations = try await experimentRepository.observations(
                experimentID: experiment.id
            )
            observations = savedObservations
            scheduleAnalysisRefresh(for: savedObservations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleAnalysisRefresh(for observations: [ExperimentObservation]) {
        analysisTask?.cancel()
        analysisGeneration += 1
        let generation = analysisGeneration
        let currentExperiment = experiment
        analysisTask = Task {
            await loadAnalysis(
                experiment: currentExperiment,
                observations: observations,
                generation: generation
            )
        }
    }

    @MainActor
    private func loadAnalysis(
        experiment: ExperimentDefinition,
        observations: [ExperimentObservation],
        generation: Int
    ) async {
        isAnalyzing = true
        do {
            let input = try await ExperimentAnalysisInputLoader(
                whoopRepository: whoopRepository,
                healthKitRepository: healthKitRepository,
                assessmentRepository: assessmentRepository,
                workoutRepository: workoutRepository
            ).load(for: experiment.primaryOutcome)
            try Task.checkCancellation()
            guard generation == analysisGeneration else { return }
            analysisInput = input
            analysis = DeterministicExperimentEngine().analyze(
                experiment: experiment,
                observations: observations,
                input: input
            )
            isAnalyzing = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == analysisGeneration else { return }
            isAnalyzing = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func upsertObservation(_ observation: ExperimentObservation) {
        observations.removeAll {
            $0.id == observation.id
                || ($0.experimentID == observation.experimentID && $0.day == observation.day)
        }
        observations.append(observation)
        observations.sort { $0.day > $1.day }
    }

    @MainActor
    private func setStatus(_ status: ExperimentStatus) async {
        var updated = experiment
        updated.status = status
        updated.updatedAt = .now
        if status == .completed, updated.endDate == nil { updated.endDate = .now }
        do {
            try await experimentRepository.saveExperiment(updated)
            experiment = updated
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteExperiment() async {
        do {
            try await experimentRepository.deleteExperiment(id: experiment.id)
            await onDelete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct ExperimentObservationRow: View {
    let resolved: ExperimentResolvedObservation?
    let experiment: ExperimentDefinition

    var body: some View {
        let observation = resolved?.observation
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(observation?.day ?? "Observation")
                Text(
                    observation.map { experiment.conditionLabel(for: $0.condition) } ?? "Condition"
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
                if let outcomeDay = resolved?.outcomeDay {
                    Text("\(experiment.primaryOutcome.displayName): \(outcomeDay)")
                        .font(.journal(.caption2))
                        .foregroundStyle(.tertiary)
                }
                if observation?.included == false {
                    Label("Excluded", systemImage: "nosign")
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalAmberText)
                }
            }
            Spacer()
            if let value = resolved?.outcomeValue {
                Text(
                    "\(value.formatted(.number.precision(.fractionLength(1)))) \(experiment.primaryOutcome.unit)"
                )
            } else {
                Text("No outcome").foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ExperimentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State var experiment: ExperimentDefinition
    let onSave: (ExperimentDefinition) async throws -> Void

    @State private var inclusionText: String
    @State private var exclusionText: String
    @State private var confounderText: String
    @State private var hasEndDate: Bool
    @State private var errorMessage: String?

    init(
        experiment: ExperimentDefinition,
        onSave: @escaping (ExperimentDefinition) async throws -> Void
    ) {
        _experiment = State(initialValue: experiment)
        _inclusionText = State(initialValue: experiment.inclusionCriteria.joined(separator: "\n"))
        _exclusionText = State(initialValue: experiment.exclusionCriteria.joined(separator: "\n"))
        _confounderText = State(
            initialValue: experiment.potentialConfounders.joined(separator: "\n"))
        _hasEndDate = State(initialValue: experiment.endDate != nil)
        self.onSave = onSave
    }

    var body: some View {
        JournalForm {
            Section("Question") {
                TextField("Short title", text: $experiment.title)
                    .formKeyboardField()
                    .accessibilityIdentifier("experiment-title")
                TextField(
                    "What are you trying to learn?", text: $experiment.question, axis: .vertical
                )
                .formKeyboardField(dismissOnSubmit: false)
                .lineLimit(2...5)
                TextField("Hypothesis (optional)", text: $experiment.hypothesis, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false)
                    .lineLimit(2...5)
            }
            Section("Conditions") {
                TextField("Condition A", text: $experiment.intervention, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false)
                TextField(
                    "Condition B", text: $experiment.comparisonCondition, axis: .vertical
                )
                .formKeyboardField(dismissOnSubmit: false)
                Text(
                    "At the end of a day, choose the condition that actually happened. These labels do not schedule a future action."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            }
            Section("Outcomes") {
                Picker("Primary outcome", selection: $experiment.primaryOutcome) {
                    ForEach(ExperimentOutcome.allCases) { Text($0.displayName).tag($0) }
                }
                Text(experiment.primaryOutcome.dataSourceExplanation)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                Picker("Measure outcome", selection: $experiment.outcomeTiming) {
                    ForEach(ExperimentOutcomeTiming.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                Text(experiment.outcomeTiming.explanation)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                DisclosureGroup("Secondary outcomes") {
                    ForEach(ExperimentOutcome.allCases.filter { $0 != experiment.primaryOutcome }) {
                        outcome in
                        Toggle(
                            outcome.displayName,
                            isOn: secondaryBinding(outcome)
                        )
                    }
                }
                Stepper(
                    "Minimum per condition: \(experiment.minimumObservations)",
                    value: $experiment.minimumObservations,
                    in: 2...60
                )
                Text(
                    "Requires at least \(experiment.minimumObservations) usable days in each condition (\(2 * experiment.minimumObservations) total)."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
                Text(experiment.analysisMethod)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
            Section("Criteria and context") {
                TextField("Inclusion criteria, one per line", text: $inclusionText, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false)
                    .lineLimit(2...6)
                TextField("Exclusion criteria, one per line", text: $exclusionText, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false)
                    .lineLimit(2...6)
                TextField(
                    "Potential confounders, one per line", text: $confounderText, axis: .vertical
                )
                .formKeyboardField(dismissOnSubmit: false)
                .lineLimit(2...6)
            }
            Section("Schedule") {
                DatePicker(
                    "Start date", selection: $experiment.startDate, displayedComponents: .date)
                Toggle("Set end date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker(
                        "End date",
                        selection: endDateBinding,
                        in: experiment.startDate...,
                        displayedComponents: .date
                    )
                }
                Picker("Status", selection: $experiment.status) {
                    ForEach(ExperimentStatus.allCases.filter { $0 != .archived }) {
                        Text($0.displayName).tag($0)
                    }
                }
                Text("Active experiments appear in the single daily check-in.")
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
        .navigationTitle(experiment.title.isEmpty ? "New Experiment" : "Edit Experiment")
        .navigationBarTitleDisplayMode(.inline)
        .formKeyboardScope($focusedField)
        .onChange(of: experiment.primaryOutcome) { _, outcome in
            experiment.outcomeTiming = outcome.recommendedTiming
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    focusedField = nil
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    focusedField = nil
                    Task { await save() }
                }
                .disabled(!experiment.isValid)
                .accessibilityIdentifier("save-experiment")
            }
        }
        .alert("Couldn’t save experiment", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func secondaryBinding(_ outcome: ExperimentOutcome) -> Binding<Bool> {
        Binding(
            get: { experiment.secondaryOutcomes.contains(outcome) },
            set: { enabled in
                experiment.secondaryOutcomes.removeAll { $0 == outcome }
                if enabled { experiment.secondaryOutcomes.append(outcome) }
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { experiment.endDate ?? experiment.startDate },
            set: { experiment.endDate = $0 }
        )
    }

    @MainActor
    private func save() async {
        experiment.secondaryOutcomes.removeAll { $0 == experiment.primaryOutcome }
        experiment.inclusionCriteria = lines(inclusionText)
        experiment.exclusionCriteria = lines(exclusionText)
        experiment.potentialConfounders = lines(confounderText)
        experiment.endDate = hasEndDate ? endDateBinding.wrappedValue : nil
        experiment.analysisVersion = DeterministicExperimentEngine.version
        experiment.updatedAt = .now
        do {
            try await onSave(experiment)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func lines(_ value: String) -> [String] {
        value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct DailyExperimentSelection: Identifiable {
    let experiment: ExperimentDefinition
    var condition: ExperimentCondition?

    var id: String { experiment.id }
}

struct DailyExperimentLogView: View {
    @Environment(\.dismiss) private var dismiss
    let experiments: [ExperimentDefinition]
    let experimentRepository: any ExperimentRepository
    let onSave: () async -> Void

    @State private var date = Date.now
    @State private var selections: [DailyExperimentSelection]
    @State private var existingByExperiment: [String: ExperimentObservation] = [:]
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        experiments: [ExperimentDefinition],
        experimentRepository: any ExperimentRepository,
        onSave: @escaping () async -> Void
    ) {
        self.experiments = experiments
        self.experimentRepository = experimentRepository
        self.onSave = onSave
        _selections = State(
            initialValue: experiments.map {
                DailyExperimentSelection(experiment: $0, condition: nil)
            })
    }

    var body: some View {
        JournalForm {
            Section("Day") {
                DatePicker(
                    "Local day",
                    selection: $date,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                Text(
                    "At the end of the day, choose what actually happened. Not recorded leaves that experiment unchanged."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            }

            if isLoading {
                ProgressView("Loading existing entries…")
            } else {
                ForEach($selections) { $selection in
                    Section(selection.experiment.title) {
                        Picker("Condition", selection: $selection.condition) {
                            Text("Not recorded").tag(nil as ExperimentCondition?)
                            Text(selection.experiment.intervention)
                                .tag(ExperimentCondition.intervention as ExperimentCondition?)
                            Text(selection.experiment.comparisonCondition)
                                .tag(ExperimentCondition.comparison as ExperimentCondition?)
                        }
                        if existingByExperiment[selection.experiment.id] != nil {
                            Label(
                                "This date already has an entry. Saving updates it.",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                        Text(
                            "\(selection.experiment.primaryOutcome.displayName): \(selection.experiment.outcomeTiming.displayName.lowercased())."
                        )
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                    }
                }
            }
        }
        .navigationTitle("Log Experiment Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Day") { Task { await save() } }
                    .disabled(
                        isLoading || isSaving || selections.allSatisfy { $0.condition == nil }
                    )
                    .accessibilityIdentifier("save-experiment-day")
            }
        }
        .task { await load() }
        .onChange(of: date) { _, _ in
            Task { await load() }
        }
        .alert("Couldn’t log day", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let day = Self.dayKey(date)
            var loaded: [String: ExperimentObservation] = [:]
            for experiment in experiments {
                let observations = try await experimentRepository.observations(
                    experimentID: experiment.id
                )
                loaded[experiment.id] = observations.first { $0.day == day }
            }
            existingByExperiment = loaded
            selections = experiments.map {
                DailyExperimentSelection(
                    experiment: $0,
                    condition: loaded[$0.id]?.condition
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let day = Self.dayKey(date)
            var updates: [ExperimentObservation] = []
            for selection in selections {
                guard let condition = selection.condition else { continue }
                var observation =
                    existingByExperiment[selection.experiment.id]
                    ?? .new(experimentID: selection.experiment.id, day: day)
                observation.condition = condition
                observation.updatedAt = .now
                updates.append(observation)
            }
            try await experimentRepository.saveObservations(updates)
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct ExperimentObservationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State var observation: ExperimentObservation
    let experiment: ExperimentDefinition
    let existingObservations: [ExperimentObservation]
    let analysisInput: ExperimentAnalysisInput?
    let onSave: (ExperimentObservation, String?) async throws -> Void
    let onDelete: (ExperimentObservation) async throws -> Void
    private let originalObservationID: String?
    private let originalDay: String?

    @State private var date: Date
    @State private var confounderText: String
    @State private var errorMessage: String?
    @State private var isConfirmingDeletion = false

    init(
        observation: ExperimentObservation,
        experiment: ExperimentDefinition,
        existingObservations: [ExperimentObservation],
        analysisInput: ExperimentAnalysisInput?,
        onSave: @escaping (ExperimentObservation, String?) async throws -> Void,
        onDelete: @escaping (ExperimentObservation) async throws -> Void
    ) {
        let existingObservation = existingObservations.first {
            $0.id == observation.id || $0.day == observation.day
        }
        let initialObservation = existingObservation ?? observation
        _observation = State(initialValue: initialObservation)
        self.experiment = experiment
        self.existingObservations = existingObservations
        self.analysisInput = analysisInput
        self.onSave = onSave
        self.onDelete = onDelete
        originalObservationID = existingObservation?.id
        originalDay = existingObservation?.day
        _date = State(initialValue: Self.date(initialObservation.day) ?? .now)
        _confounderText = State(
            initialValue: initialObservation.confounders.joined(separator: "\n"))
    }

    var body: some View {
        JournalForm {
            Section("What actually happened") {
                Text(
                    "Choose the condition that was true on this day. This records what happened; it does not schedule a future action."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
                DatePicker("Local day", selection: $date, displayedComponents: .date)
                Picker("Condition", selection: $observation.condition) {
                    Text(experiment.intervention).tag(ExperimentCondition.intervention)
                    Text(experiment.comparisonCondition).tag(ExperimentCondition.comparison)
                }
                if hasDateConflict {
                    Label(
                        "That date already has a condition day.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalAmberText)
                } else if let originalDay, selectedDay != originalDay {
                    Label(
                        "Saving will move this entry from \(originalDay) to \(selectedDay).",
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                } else if isUpdatingExistingDay {
                    Label(
                        "Saving will update this date's existing entry.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                }
                Toggle("Include in analysis", isOn: $observation.included)
                if !observation.included {
                    TextField(
                        "Exclusion reason", text: $observation.exclusionReason, axis: .vertical
                    )
                    .formKeyboardField(dismissOnSubmit: false)
                }
            }
            Section("Automatic outcome") {
                LabeledContent(experiment.primaryOutcome.displayName) {
                    if let formattedResolvedValue {
                        Text(formattedResolvedValue)
                    } else {
                        Text("Not available yet").foregroundStyle(Color.journalInk.opacity(0.7))
                    }
                }
                LabeledContent("Condition day", value: selectedDay)
                LabeledContent("Outcome day", value: outcomeDay)
                Text(experiment.outcomeTiming.explanation)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                if resolvedValue == nil {
                    Text("Synchronize the source if this outcome should already be available.")
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }
            }
            Section {
                TextField("Confounders, one per line", text: $confounderText, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false)
                TextField("Notes", text: $observation.notes, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false)
            } header: {
                Text("Optional context")
            } footer: {
                if originalObservationID != nil {
                    Text(
                        "Changing the date moves this logged day. It does not leave a copy behind."
                    )
                }
            }
            if isUpdatingExistingDay {
                Section {
                    Button("Delete this day", role: .destructive) {
                        focusedField = nil
                        isConfirmingDeletion = true
                    }
                } footer: {
                    Text("Deleting removes this day from the experiment and its analysis.")
                }
            }
        }
        .onChange(of: date) { _, _ in
            loadSelectedDay()
        }
        .navigationTitle("Condition Day")
        .navigationBarTitleDisplayMode(.inline)
        .formKeyboardScope($focusedField)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    focusedField = nil
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    focusedField = nil
                    Task { await save() }
                }
                .disabled(
                    !observation.included
                        && observation.exclusionReason.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || hasDateConflict
                )
            }
        }
        .alert("Couldn’t save observation", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Delete this logged day?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete day", role: .destructive) {
                Task { await deleteSelectedDay() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This day will no longer count in the experiment. This cannot be undone.")
        }
    }

    private var outcomeDay: String {
        DeterministicExperimentEngine().outcomeDay(
            for: selectedDay,
            timing: experiment.outcomeTiming
        )
    }

    private var selectedDay: String {
        Self.dayKey(date)
    }

    private var resolvedValue: Double? {
        guard let analysisInput else { return nil }
        return DeterministicExperimentEngine().resolve(
            experiment.primaryOutcome,
            day: outcomeDay,
            input: analysisInput
        )
    }

    private var formattedResolvedValue: String? {
        guard let resolvedValue else { return nil }
        let number = resolvedValue.formatted(.number.precision(.fractionLength(1)))
        return "\(number) \(experiment.primaryOutcome.unit)"
    }

    private var isUpdatingExistingDay: Bool {
        originalObservationID != nil || existingObservations.contains { $0.day == selectedDay }
    }

    private var hasDateConflict: Bool {
        guard let originalObservationID else { return false }
        return existingObservations.contains {
            $0.id != originalObservationID && $0.day == selectedDay
        }
    }

    private func loadSelectedDay() {
        guard originalObservationID == nil else { return }
        if let existing = existingObservations.first(where: { $0.day == selectedDay }) {
            observation = existing
            confounderText = existing.confounders.joined(separator: "\n")
        } else {
            observation = .new(experimentID: experiment.id, day: selectedDay)
            confounderText = ""
        }
    }

    @MainActor
    private func save() async {
        observation.day = selectedDay
        observation.id = ExperimentObservation.stableID(
            experimentID: observation.experimentID,
            day: observation.day
        )
        observation.confounders = confounderText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if observation.included { observation.exclusionReason = "" }
        observation.updatedAt = .now
        do {
            try await onSave(observation, originalObservationID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteSelectedDay() async {
        guard
            let existing = existingObservations.first(where: {
                $0.id == originalObservationID || $0.day == selectedDay
            })
        else { return }
        do {
            try await onDelete(existing)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.autoupdatingCurrent.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

#Preview {
    NavigationStack {
        ExperimentLabView(
            experimentRepository: PreviewExperimentRepository(),
            whoopRepository: PreviewWhoopRepository(),
            healthKitRepository: PreviewHealthKitRepository(),
            assessmentRepository: PreviewAssessmentRepository(),
            workoutRepository: PreviewWorkoutRepository()
        )
    }
}
