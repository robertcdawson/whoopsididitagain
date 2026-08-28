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
        List {
            Section {
                Label("Experimental feature", systemImage: "flask")
                    .font(.headline)
                Text(
                    "Results are descriptive personal associations. They do not establish causation, treatment efficacy, diagnosis, or medical advice."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            .buttonStyle(.borderedProminent)
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
                                Text(experiment.title).font(.headline)
                                Text(experiment.primaryOutcome.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(experiment.status.displayName)
                                    .font(.caption)
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
    @State private var editingObservation: ExperimentObservation?
    @State private var isEditingExperiment = false
    @State private var isConfirmingExperimentDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        List {
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
                    await load()
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
                ) { updated in
                    try await experimentRepository.saveObservation(updated)
                    await load()
                } onDelete: { deleted in
                    try await experimentRepository.deleteObservation(id: deleted.id)
                    await load()
                }
            }
        }
        .task { await load() }
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
            .font(.caption)
            .foregroundStyle(.secondary)
            LabeledContent("Outcome timing", value: experiment.outcomeTiming.displayName)
            Text(experiment.outcomeTiming.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Log a day")
        }
    }

    private var definitionSection: some View {
        Section("Definition") {
            LabeledContent("Status", value: experiment.status.displayName)
            VStack(alignment: .leading, spacing: 4) {
                Text("Question").font(.caption).foregroundStyle(.secondary)
                Text(experiment.question)
            }
            if !experiment.hypothesis.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hypothesis").font(.caption).foregroundStyle(.secondary)
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
                    value: "\(analysis.interventionCount) of \(experiment.minimumObservations) days"
                )
                LabeledContent(
                    experiment.comparisonCondition,
                    value: "\(analysis.comparisonCount) of \(experiment.minimumObservations) days"
                )
                if analysis.evidenceStatus == .insufficientData {
                    Text(remainingText(analysis))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(analysis.summary)
                if analysis.missingOutcomeCount > 0 {
                    Label(
                        "\(analysis.missingOutcomeCount) included days are missing the selected outcome",
                        systemImage: "questionmark.circle"
                    )
                    .foregroundStyle(.orange)
                }
                Text(analysis.caveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(analysis.version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView("Resolving local outcomes…")
            }
        }
    }

    private var observationSection: some View {
        Section {
            if observations.isEmpty {
                Text("No condition days recorded yet.").foregroundStyle(.secondary)
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
            "Still needed: \(interventionRemaining) \(experiment.intervention) days and \(comparisonRemaining) \(experiment.comparisonCondition) days."
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
            async let savedObservations = experimentRepository.observations(
                experimentID: experiment.id
            )
            async let whoop = whoopRepository.history()
            async let health = healthKitRepository.history()
            async let workouts = workoutRepository.completedWorkouts()
            async let plans = workoutRepository.plans()
            async let checkIns = assessmentRepository.checkIns()
            async let assessments = assessmentRepository.assessments()
            async let restrictions = assessmentRepository.restrictions()
            async let injuries = assessmentRepository.injuryTimeline()
            let input = try await TrendsInput(
                generatedAt: .now,
                whoop: whoop,
                healthKit: health,
                workouts: workouts,
                plans: plans,
                checkIns: checkIns,
                assessments: assessments,
                restrictions: restrictions,
                injuries: injuries
            )
            let currentObservations = try await savedObservations
            let trends = DeterministicTrendsEngine().analyze(input)
            let currentAnalysisInput = ExperimentAnalysisInput(
                trends: trends,
                checkIns: input.checkIns
            )
            observations = currentObservations
            analysisInput = currentAnalysisInput
            analysis = DeterministicExperimentEngine().analyze(
                experiment: experiment,
                observations: currentObservations,
                input: currentAnalysisInput
            )
        } catch {
            errorMessage = error.localizedDescription
        }
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
                .font(.caption)
                .foregroundStyle(.secondary)
                if let outcomeDay = resolved?.outcomeDay {
                    Text("\(experiment.primaryOutcome.displayName): \(outcomeDay)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if observation?.included == false {
                    Label("Excluded", systemImage: "nosign")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let value = resolved?.outcomeValue {
                Text(
                    "\(value.formatted(.number.precision(.fractionLength(1)))) \(experiment.primaryOutcome.unit)"
                )
            } else {
                Text("No outcome").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ExperimentEditorView: View {
    @Environment(\.dismiss) private var dismiss
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
        Form {
            Section("Question") {
                TextField("Short title", text: $experiment.title)
                    .accessibilityIdentifier("experiment-title")
                TextField(
                    "What are you trying to learn?", text: $experiment.question, axis: .vertical
                )
                .lineLimit(2...5)
                TextField("Hypothesis (optional)", text: $experiment.hypothesis, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section("Conditions") {
                TextField("Condition A", text: $experiment.intervention, axis: .vertical)
                TextField(
                    "Condition B", text: $experiment.comparisonCondition, axis: .vertical)
                Text(
                    "At the end of a day, choose the condition that actually happened. These labels do not schedule a future action."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("Outcomes") {
                Picker("Primary outcome", selection: $experiment.primaryOutcome) {
                    ForEach(ExperimentOutcome.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Measure outcome", selection: $experiment.outcomeTiming) {
                    ForEach(ExperimentOutcomeTiming.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                Text(experiment.outcomeTiming.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(experiment.analysisMethod)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Criteria and context") {
                TextField("Inclusion criteria, one per line", text: $inclusionText, axis: .vertical)
                    .lineLimit(2...6)
                TextField("Exclusion criteria, one per line", text: $exclusionText, axis: .vertical)
                    .lineLimit(2...6)
                TextField(
                    "Potential confounders, one per line", text: $confounderText, axis: .vertical
                )
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(experiment.title.isEmpty ? "New Experiment" : "Edit Experiment")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: experiment.primaryOutcome) { _, outcome in
            experiment.outcomeTiming = outcome.recommendedTiming
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
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
        Form {
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Text(
                            "\(selection.experiment.primaryOutcome.displayName): \(selection.experiment.outcomeTiming.displayName.lowercased())."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    @State var observation: ExperimentObservation
    let experiment: ExperimentDefinition
    let existingObservations: [ExperimentObservation]
    let analysisInput: ExperimentAnalysisInput?
    let onSave: (ExperimentObservation) async throws -> Void
    let onDelete: (ExperimentObservation) async throws -> Void

    @State private var date: Date
    @State private var confounderText: String
    @State private var errorMessage: String?
    @State private var isConfirmingDeletion = false

    init(
        observation: ExperimentObservation,
        experiment: ExperimentDefinition,
        existingObservations: [ExperimentObservation],
        analysisInput: ExperimentAnalysisInput?,
        onSave: @escaping (ExperimentObservation) async throws -> Void,
        onDelete: @escaping (ExperimentObservation) async throws -> Void
    ) {
        let initialObservation =
            existingObservations.first { $0.day == observation.day } ?? observation
        _observation = State(initialValue: initialObservation)
        self.experiment = experiment
        self.existingObservations = existingObservations
        self.analysisInput = analysisInput
        self.onSave = onSave
        self.onDelete = onDelete
        _date = State(initialValue: Self.date(initialObservation.day) ?? .now)
        _confounderText = State(
            initialValue: initialObservation.confounders.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("What actually happened") {
                Text(
                    "Choose the condition that was true on this day. This records what happened; it does not schedule a future action."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                DatePicker("Local day", selection: $date, displayedComponents: .date)
                Picker("Condition", selection: $observation.condition) {
                    Text(experiment.intervention).tag(ExperimentCondition.intervention)
                    Text(experiment.comparisonCondition).tag(ExperimentCondition.comparison)
                }
                if isUpdatingExistingDay {
                    Label(
                        "Saving will update this date's existing entry.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Toggle("Include in analysis", isOn: $observation.included)
                if !observation.included {
                    TextField(
                        "Exclusion reason", text: $observation.exclusionReason, axis: .vertical)
                }
            }
            Section("Automatic outcome") {
                LabeledContent(experiment.primaryOutcome.displayName) {
                    if let formattedResolvedValue {
                        Text(formattedResolvedValue)
                    } else {
                        Text("Not available yet").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Condition day", value: Self.dayKey(date))
                LabeledContent("Outcome day", value: outcomeDay)
                Text(experiment.outcomeTiming.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if resolvedValue == nil {
                    Text("Synchronize the source if this outcome should already be available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Confounders, one per line", text: $confounderText, axis: .vertical)
                TextField("Notes", text: $observation.notes, axis: .vertical)
            } header: {
                Text("Optional context")
            } footer: {
                Text("Changing the selected date never deletes another date's entry.")
            }
            if isUpdatingExistingDay {
                Section {
                    Button("Delete this day", role: .destructive) {
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(
                        !observation.included
                            && observation.exclusionReason.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
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
            for: Self.dayKey(date),
            timing: experiment.outcomeTiming
        )
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
        existingObservations.contains { $0.day == Self.dayKey(date) }
    }

    private func loadSelectedDay() {
        let selectedDay = Self.dayKey(date)
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
        observation.day = Self.dayKey(date)
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
            try await onSave(observation)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteSelectedDay() async {
        guard let existing = existingObservations.first(where: { $0.day == Self.dayKey(date) })
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
