import Charts
import SwiftUI

struct TrendsView: View {
    let whoopRepository: any WhoopRepository
    let healthKitRepository: any HealthKitRepository
    let assessmentRepository: any AssessmentRepository
    let workoutRepository: any WorkoutRepository
    let experimentRepository: any ExperimentRepository

    @AppStorage(FeatureFlags.experimentLabKey) private var experimentLabEnabled = false
    @State private var snapshot: TrendsSnapshot?
    @State private var selectedInjuryID: String?
    @State private var bodyRestrictions: [RestrictionProfile] = []
    @State private var bodyMapView: BodyMapView = .front
    @State private var editingBodyRestriction: RestrictionProfile?
    @State private var editingBodyFocus: BodyMapFocus?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var exportFiles: TrendsExportFiles?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var includedHealthMetrics = Set(HealthMetric.allCases)

    var body: some View {
        NavigationStack {
            JournalPage(title: "Body") {
                if let snapshot {
                    bodyOverview(snapshot)
                    JournalRule()
                    if let injury = selectedInjury(in: snapshot) {
                        JournalSection(title: "\(injury.name) · the story") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(
                                    "Recorded \(injury.startedAt.formatted(date: .abbreviated, time: .omitted))"
                                )
                                Text(
                                    "Updated \(injury.updatedAt.formatted(date: .abbreviated, time: .omitted))"
                                )
                                ForEach(bodyRestrictions.filter { $0.injuryName == injury.name }) {
                                    restriction in
                                    Text(
                                        "\(restriction.isActive ? restriction.level.displayName : "Inactive"): \(restriction.rationale)"
                                    )
                                    .foregroundStyle(
                                        restriction.isActive
                                            ? Color.journalRedPen : Color.journalInk.opacity(0.7))
                                }
                            }
                            .font(.journal(.subheadline))
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color.journalRedPen.opacity(0.25)).frame(width: 1)
                            }
                            Text("Dates describe your records, not a healing timeline.")
                                .font(.journal(.caption)).italic().foregroundStyle(
                                    Color.journalInk.opacity(0.7))
                        }
                        JournalRule()
                    }
                    NavigationLink {
                        JournalList { painSection(snapshot.painByMovement) }
                            .navigationTitle("Pain by movement")
                    } label: {
                        Label("pain by movement →", systemImage: "waveform.path")
                            .font(.journal(.subheadline)).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("body-pain-history")
                    if let recovery = snapshot.recoveryMetrics.first(where: {
                        $0.id == "whoop-recovery"
                    }) {
                        MetricRow(metric: recovery).font(.journal(.subheadline))
                    }
                    Text("association, not causation. as always.")
                        .font(.journal(.footnote)).italic().foregroundStyle(
                            Color.journalInk.opacity(0.7))
                    Spacer(minLength: 12)
                    NavigationLink {
                        JournalList { weeklySection(snapshot.weeklyReview) }
                            .navigationTitle("Weekly review")
                    } label: {
                        Text("this week's review →").underline().frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("weekly-review-link")
                    NavigationLink {
                        JournalList {
                            recoverySection(snapshot)
                            sleepSection(snapshot.sleep)
                            trainingSection(snapshot)
                            injurySection(snapshot.injuries)
                            exportSection
                        }
                        .navigationTitle("Trends & export")
                    } label: {
                        Text("all trends & export →").font(.journal(.subheadline)).frame(
                            minHeight: 44)
                    }
                    .accessibilityIdentifier("all-trends-link")
                    if FeatureFlags.experimentLabEnabled(storedValue: experimentLabEnabled) {
                        experimentSection
                    }
                } else if isLoading {
                    ProgressView("Building your body story…")
                } else {
                    Text("Your story starts with a check-in.")
                    Text("Synchronize health history or record a workout to begin.")
                        .font(.journal(.subheadline))
                }
            }
            .task { await load() }
            .sheet(item: $editingBodyRestriction) { profile in
                BodyAreaPicker(
                    initialAreaIDs: profile.affectedAreaIDs,
                    initialFocus: editingBodyFocus
                ) { ids in
                    Task { await saveAffectedAreas(ids, for: profile) }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .healthMetricInclusionDidChange)
            ) { _ in
                Task { await load() }
            }
            .refreshable { await synchronizeAndLoad() }
            .alert("Couldn’t build trends", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func weeklySection(_ review: WeeklyReview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                reportItem(
                    "Most important change", review.importantChange, symbol: "arrow.up.arrow.down")
                reportItem("What coincided", review.plausibleExplanation, symbol: "link")
                reportItem("Next action", review.nextAction, symbol: "checklist")
                Text(review.caveat)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
            .padding(.vertical, 6)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly review")
                Text(
                    review.periodStart..<review.periodEnd,
                    format: .interval.day().month(.abbreviated)
                )
                .textCase(nil)
                .font(.journal(.caption))
            }
        }
    }

    private func selectedInjury(in snapshot: TrendsSnapshot) -> InjuryTimelineItem? {
        snapshot.injuries.first { $0.id == selectedInjuryID }
            ?? snapshot.injuries.first { injury in
                bodyRestrictions.contains {
                    injury.id == injuryTimelineID(for: $0) && $0.isActive
                }
            } ?? snapshot.injuries.first
    }

    private func bodyOverview(_ snapshot: TrendsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            bodyOverviewLayout {
                BodyMapFigure(
                    view: bodyMapView,
                    selectedAreaIDs: Set(
                        selectedBodyRestriction(in: snapshot)?.affectedAreaIDs ?? [])
                ) { focus in
                    guard let profile = selectedBodyRestriction(in: snapshot) else { return }
                    editingBodyFocus = focus
                    editingBodyRestriction = profile
                }
                .frame(width: 126, height: 210)
                VStack(alignment: .leading, spacing: 12) {
                    if let injury = selectedInjury(in: snapshot) {
                        Text(injury.name).font(.journal(.headline, weight: .bold))
                            .foregroundStyle(Color.journalAmber)
                        Text("\(injury.side) · \(injury.bodyRegion)").font(.journal(.subheadline))
                        Text(injury.status.capitalized).font(.journal(.subheadline))
                        if let profile = selectedBodyRestriction(in: snapshot) {
                            Text(
                                profile.affectedAreaIDs.isEmpty
                                    ? "No mapped areas yet"
                                    : "\(profile.affectedAreaIDs.count) mapped area\(profile.affectedAreaIDs.count == 1 ? "" : "s")"
                            )
                            .font(.journal(.footnote))
                            .foregroundStyle(Color.journalInk.opacity(0.68))
                        }
                    } else {
                        Text("No body-part history yet.").font(.journal(.subheadline))
                    }
                }.padding(.top, 14)
            }
            Picker("Body view", selection: $bodyMapView) {
                ForEach(BodyMapView.allCases) { view in
                    Text(view.displayName).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("body-overview-view")
            if !bodyRestrictions.isEmpty {
                Menu {
                    ForEach(bodyRestrictions) { restriction in
                        Button(restriction.injuryName) {
                            selectedInjuryID = injuryTimelineID(for: restriction)
                            bodyMapView = preferredBodyMapView(for: restriction)
                        }
                    }
                } label: {
                    Label("Choose restriction", systemImage: "chevron.down")
                        .font(.journal(.subheadline)).frame(minHeight: 44)
                }
                .accessibilityIdentifier("choose-restriction")
            }
            if let profile = selectedBodyRestriction(in: snapshot) {
                Button {
                    editingBodyFocus = nil
                    editingBodyRestriction = profile
                } label: {
                    Label(
                        profile.affectedAreaIDs.isEmpty
                            ? "choose affected areas →" : "edit affected areas →",
                        systemImage: "figure.stand"
                    )
                    .font(.journal(.subheadline))
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("body-edit-affected-areas")
            }
            NavigationLink {
                RestrictionManagementView(repository: assessmentRepository)
            } label: {
                Text("manage restrictions →").font(.journal(.footnote)).frame(minHeight: 44)
            }
        }
    }

    private var bodyOverviewLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
    }

    private func selectedBodyRestriction(in snapshot: TrendsSnapshot) -> RestrictionProfile? {
        guard let injury = selectedInjury(in: snapshot) else { return nil }
        return bodyRestrictions.first { injuryTimelineID(for: $0) == injury.id }
    }

    private func preferredBodyMapView(for restriction: RestrictionProfile) -> BodyMapView {
        BodyAreaCatalog.definitions(for: restriction.affectedAreaIDs)
            .compactMap(\.view)
            .first ?? .front
    }

    private func injuryTimelineID(for restriction: RestrictionProfile) -> String {
        "injury:\(restriction.id)"
    }

    private func reportItem(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.journal(.headline))
                Text(text).foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
    }

    private func recoverySection(_ snapshot: TrendsSnapshot) -> some View {
        Section("Recovery decomposition") {
            ForEach(snapshot.recoveryMetrics.filter(isIncluded)) { metric in
                NavigationLink {
                    MetricDetailView(metric: metric)
                } label: {
                    MetricRow(metric: metric)
                }
            }
            Text(
                "WHOOP RMSSD and Apple Health SDNN are shown separately because they are different HRV measurements."
            )
            .font(.journal(.caption))
            .foregroundStyle(Color.journalInk.opacity(0.7))
        }
    }

    private func isIncluded(_ metric: MetricTrendSummary) -> Bool {
        switch metric.id {
        case "apple-hrv-sdnn": includedHealthMetrics.contains(.hrvSDNN)
        case "apple-resting-heart-rate": includedHealthMetrics.contains(.restingHeartRate)
        case "apple-respiratory-rate": includedHealthMetrics.contains(.respiratoryRate)
        case "apple-oxygen-saturation": includedHealthMetrics.contains(.oxygenSaturation)
        default: true
        }
    }

    private func sleepSection(_ metric: MetricTrendSummary) -> some View {
        Section("Sleep duration") {
            if metric.points.isEmpty {
                unavailableRow("No sleep observations")
            } else {
                Chart(metric.points.suffix(14)) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Minutes", point.value))
                    PointMark(x: .value("Date", point.date), y: .value("Minutes", point.value))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) { Text("\(Int(minutes / 60))h") }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 170)
                MetricRow(metric: metric)
            }
        }
    }

    private func trainingSection(_ snapshot: TrendsSnapshot) -> some View {
        Section("Training load") {
            if snapshot.dailyTrainingLoads.isEmpty {
                unavailableRow("No completed workouts")
            } else {
                Chart(snapshot.dailyTrainingLoads.suffix(14)) { day in
                    BarMark(x: .value("Day", day.day), y: .value("Load", day.load))
                }
                .frame(height: 170)
                LabeledContent(
                    "Current 7 days",
                    value: snapshot.currentTrainingLoad.formatted(
                        .number.precision(.fractionLength(0))))
                LabeledContent(
                    "Previous 7 days",
                    value: snapshot.priorTrainingLoad.formatted(
                        .number.precision(.fractionLength(0))))
                Text(
                    "Session load = completed minutes × session RPE. It is a descriptive workload estimate, not a medical score."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            }

            if !snapshot.strengthVolumes.isEmpty {
                DisclosureGroup("Strength volume") {
                    ForEach(snapshot.strengthVolumes) { item in
                        LabeledContent {
                            Text(
                                "\(item.volume.formatted(.number.precision(.fractionLength(0)))) \(item.unit)"
                            )
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.movement)
                                Text("n=\(item.entryCount) recorded entries")
                                    .font(.journal(.caption))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
                            }
                        }
                    }
                    Text(
                        "Volumes stay separated by movement and unit; unlike units are never combined."
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                }
            }
        }
    }

    private func painSection(_ summaries: [PainByMovementSummary]) -> some View {
        Section("Pain by movement") {
            if summaries.isEmpty {
                unavailableRow("No movement pain observations")
            } else {
                ForEach(summaries) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        LabeledContent(
                            item.movement,
                            value:
                                "\(item.averagePain.formatted(.number.precision(.fractionLength(1)))) / 10"
                        )
                        Text(
                            "n=\(item.observationCount) · highest \(item.maximumPain)/10 · latest \(item.latestAt.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                    }
                }
                Text("This is a record of reported pain, not evidence that a movement caused it.")
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
    }

    private func injurySection(_ injuries: [InjuryTimelineItem]) -> some View {
        Section("Injury timeline") {
            if injuries.isEmpty {
                unavailableRow("No injury records")
            } else {
                ForEach(injuries) { injury in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(injury.name)
                            Spacer()
                            Text(injury.status.capitalized)
                                .foregroundStyle(
                                    injury.status == "active"
                                        ? Color.journalAmberText : .journalInk.opacity(0.7))
                        }
                        Text("\(injury.side) · \(injury.bodyRegion)")
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                        Text(
                            "Updated \(injury.updatedAt.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.journal(.caption2))
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var experimentSection: some View {
        Section("Advanced analytics") {
            NavigationLink {
                ExperimentLabView(
                    experimentRepository: experimentRepository,
                    whoopRepository: whoopRepository,
                    healthKitRepository: healthKitRepository,
                    assessmentRepository: assessmentRepository,
                    workoutRepository: workoutRepository
                )
            } label: {
                Label("Experiment Lab", systemImage: "flask")
            }
            .accessibilityIdentifier("experiment-lab-link")
            Text("Experimental and descriptive. Results do not establish causation.")
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
        }
    }

    private var exportSection: some View {
        Section("Export local data") {
            if let exportFiles {
                ShareLink(item: exportFiles.jsonURL) {
                    Label("Share JSON", systemImage: "doc.text")
                }
                ShareLink(item: exportFiles.csvURL) {
                    Label("Share CSV", systemImage: "tablecells")
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Preparing export…")
                }
            }
            Text(
                "Exports include normalized records visible to the app. They exclude OAuth tokens, API keys, Keychain values, and raw WHOOP payloads."
            )
            .font(.journal(.caption))
            .foregroundStyle(Color.journalInk.opacity(0.7))
        }
    }

    private func unavailableRow(_ text: String) -> some View {
        Label(text, systemImage: "questionmark.circle").foregroundStyle(
            Color.journalInk.opacity(0.7))
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let whoop = whoopRepository.history()
            async let health = healthKitRepository.history()
            async let includedMetrics = healthKitRepository.includedMetrics()
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
            let result = DeterministicTrendsEngine().analyze(input)
            includedHealthMetrics = await includedMetrics
            snapshot = result
            bodyRestrictions = input.restrictions
            if let restriction = selectedBodyRestriction(in: result) {
                bodyMapView = preferredBodyMapView(for: restriction)
            }
            exportFiles = try TrendsExporter.write(input: input, snapshot: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func synchronizeAndLoad() async {
        do {
            let status = try await whoopRepository.connectionStatus()
            if status.connected { _ = try await whoopRepository.synchronize() }
            if await healthKitRepository.authorizationState() == .requested {
                _ = try await healthKitRepository.synchronize()
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveAffectedAreas(_ ids: [String], for profile: RestrictionProfile) async {
        var updated = profile
        updated.affectedAreaIDs = BodyAreaCatalog.validIDs(ids)
        do {
            try await assessmentRepository.saveRestriction(updated)
            bodyRestrictions = try await assessmentRepository.restrictions()
            bodyMapView =
                BodyAreaCatalog.definitions(for: updated.affectedAreaIDs)
                .compactMap(\.view)
                .first ?? bodyMapView
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MetricRow: View {
    let metric: MetricTrendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent {
                if let value = metric.latestValue {
                    Text(
                        "\(value.formatted(.number.precision(.fractionLength(metric.unit == "%" || metric.unit == "bpm" ? 0 : 1)))) \(metric.unit)"
                    )
                } else {
                    Text("—").foregroundStyle(Color.journalInk.opacity(0.7))
                }
            } label: {
                Text(metric.title)
            }
            HStack {
                Text(metric.source)
                Spacer()
                if metric.hasEnoughData, let change = metric.changeFromBaseline {
                    Text(
                        "\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) from baseline · n=\(metric.observationCount)"
                    )
                } else {
                    Text("Insufficient baseline · n=\(metric.observationCount)")
                }
            }
            .font(.journal(.caption))
            .foregroundStyle(Color.journalInk.opacity(0.7))
        }
    }
}

private struct MetricDetailView: View {
    let metric: MetricTrendSummary

    var body: some View {
        JournalList {
            Section {
                if metric.points.isEmpty {
                    ContentUnavailableView("No observations", systemImage: "chart.xyaxis.line")
                } else {
                    Chart(metric.points.suffix(28)) { point in
                        LineMark(
                            x: .value("Date", point.date), y: .value(metric.title, point.value))
                        PointMark(
                            x: .value("Date", point.date), y: .value(metric.title, point.value))
                    }
                    .frame(height: 220)
                }
            }
            Section("Summary") {
                LabeledContent("Source", value: metric.source)
                LabeledContent("Observations", value: String(metric.observationCount))
                if let baseline = metric.baselineMedian {
                    LabeledContent(
                        "Baseline median",
                        value:
                            "\(baseline.formatted(.number.precision(.fractionLength(1)))) \(metric.unit)"
                    )
                }
                if let deviation = metric.robustDeviation {
                    LabeledContent(
                        "Robust deviation",
                        value: deviation.formatted(.number.precision(.fractionLength(2))))
                }
                Text(
                    "The baseline uses up to 28 preceding local observations. This view is descriptive and does not establish a cause."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
        .navigationTitle(metric.title)
    }
}

#Preview {
    TrendsView(
        whoopRepository: PreviewWhoopRepository(),
        healthKitRepository: PreviewHealthKitRepository(),
        assessmentRepository: PreviewAssessmentRepository(),
        workoutRepository: PreviewWorkoutRepository(),
        experimentRepository: PreviewExperimentRepository()
    )
}
