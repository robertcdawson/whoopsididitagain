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
    @State private var exportFiles: TrendsExportFiles?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var includedHealthMetrics = Set(HealthMetric.allCases)

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    List {
                        weeklySection(snapshot.weeklyReview)
                        recoverySection(snapshot)
                        sleepSection(snapshot.sleep)
                        trainingSection(snapshot)
                        painSection(snapshot.painByMovement)
                        injurySection(snapshot.injuries)
                        if FeatureFlags.experimentLabEnabled(storedValue: experimentLabEnabled) {
                            experimentSection
                        }
                        exportSection
                    }
                } else if isLoading {
                    ProgressView("Building trends…")
                } else {
                    ContentUnavailableView {
                        Label("No trends yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Synchronize health history or record a workout to begin.")
                    }
                }
            }
            .navigationTitle("Trends")
            .task { await load() }
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .font(.caption)
            }
        }
    }

    private func reportItem(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
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
            .font(.caption)
            .foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(
                        "Volumes stay separated by movement and unit; unlike units are never combined."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Text("This is a record of reported pain, not evidence that a movement caused it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(injury.status == "active" ? .orange : .secondary)
                        }
                        Text("\(injury.side) · \(injury.bodyRegion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            "Updated \(injury.updatedAt.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.caption2)
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func unavailableRow(_ text: String) -> some View {
        Label(text, systemImage: "questionmark.circle").foregroundStyle(.secondary)
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
                    Text("—").foregroundStyle(.secondary)
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct MetricDetailView: View {
    let metric: MetricTrendSummary

    var body: some View {
        List {
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
