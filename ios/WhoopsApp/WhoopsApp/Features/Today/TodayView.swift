import SwiftUI

struct TodayView: View {
    let healthChecker: any BackendHealthChecking
    let whoopRepository: any WhoopRepository
    let healthKitRepository: any HealthKitRepository
    let assessmentRepository: any AssessmentRepository
    let readinessEngine: any ReadinessEngine
    let workoutRepository: any WorkoutRepository
    let protocolRepository: any ProtocolRepository
    let docketRepository: any DocketRepository
    let experimentRepository: any ExperimentRepository

    @AppStorage(FeatureFlags.experimentLabKey) private var experimentLabEnabled = false
    @State private var backendState = "Not checked"
    @State private var isCheckingBackend = false
    @State private var isSyncing = false
    @State private var syncState = "Connect WHOOP in Settings"
    @State private var latestRecovery: RecoveryHistoryItem?
    @State private var latestWhoopSleep: SleepHistoryItem?
    @State private var whoopHistory = WhoopHistorySnapshot(
        recoveries: [], sleeps: [], lastSyncAt: nil
    )
    @State private var healthHistory = HealthKitHistorySnapshot(
        days: [], lastSyncAt: nil, recordCount: 0, linkedWorkoutCount: 0
    )
    @State private var includedHealthMetrics = Set(HealthMetric.allCases)
    @State private var assessment: ReadinessAssessment?
    @State private var checkIn: MorningCheckIn?
    @State private var sleepSettings = SleepScheduleSettings.standard
    @State private var sleepDeadline: SleepDeadline?
    @State private var isShowingCheckIn = false
    @State private var isShowingOverride = false
    @State private var isShowingExperimentLog = false
    @State private var activeExperiments: [ExperimentDefinition] = []
    @State private var assessmentError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FoundationCard(title: "Should I Send It?") {
                        if let assessment {
                            Label(
                                assessment.effectiveRecommendation.displayName,
                                systemImage: assessment.effectiveRecommendation.symbolName
                            )
                            .font(.title3.weight(.semibold))

                            if assessment.userOverride != nil {
                                Text(
                                    "Your override is active; the calculated recommendation was \(assessment.recommendation.displayName.lowercased())."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            assessmentRow("Systemic readiness", score: assessment.systemicScore)
                            assessmentRow("Sleep sufficiency", score: assessment.sleepScore)
                            tissueReadinessRow(assessment)
                            LabeledContent("Confidence", value: assessment.confidence.displayName)

                            Divider()
                            ForEach(assessment.reasons.prefix(3)) { reason in
                                Label(reason.message, systemImage: reasonSymbol(reason.direction))
                                    .font(.subheadline)
                            }

                            Button("Override or annotate") {
                                isShowingOverride = true
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Label("Not enough context yet", systemImage: "questionmark.circle")
                                .font(.title3.weight(.semibold))
                            Text("Complete the morning check-in to calculate tissue readiness.")
                                .foregroundStyle(.secondary)
                        }

                        Button(
                            checkIn == nil ? "Complete morning check-in" : "Edit morning check-in"
                        ) {
                            isShowingCheckIn = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("morning-check-in")
                    }

                    DocketView(
                        protocolRepository: protocolRepository,
                        workoutRepository: workoutRepository,
                        docketRepository: docketRepository,
                        sleepDeadline: sleepDeadline
                    )

                    if FeatureFlags.experimentLabEnabled(storedValue: experimentLabEnabled),
                        !activeExperiments.isEmpty
                    {
                        FoundationCard(title: "Experiment Check-in") {
                            Text(
                                "Once today, record what actually happened across your active experiments."
                            )
                            .foregroundStyle(.secondary)
                            Button("Log experiment day") {
                                isShowingExperimentLog = true
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("today-experiment-check-in")
                        }
                    }

                    FoundationCard(title: "Daily Physiology") {
                        metricRow(
                            "Recovery",
                            value: latestRecovery?.recoveryScore.map { "\($0)%" } ?? "—",
                            source: "WHOOP"
                        )
                        metricRow(
                            "Resting heart rate",
                            value: latestHealthDay?.restingHeartRate.map {
                                "\($0.formatted(.number.precision(.fractionLength(0)))) bpm"
                            } ?? latestRecovery?.restingHeartRate.map { "\($0) bpm" } ?? "—",
                            source: latestHealthDay?.restingHeartRate == nil
                                ? "WHOOP" : "Apple Health"
                        )
                        metricRow(
                            "HRV RMSSD",
                            value: latestRecovery?.hrvRMSSD.map {
                                "\($0.formatted(.number.precision(.fractionLength(1)))) ms"
                            } ?? "—",
                            source: "WHOOP"
                        )
                        metricRow(
                            "HRV SDNN",
                            value: latestHealthDay?.hrvSDNNMilliseconds.map {
                                "\($0.formatted(.number.precision(.fractionLength(1)))) ms"
                            } ?? "—",
                            source: includedHealthMetrics.contains(.hrvSDNN)
                                ? "Apple Health" : "Excluded in Settings"
                        )
                        metricRow(
                            "Respiratory rate",
                            value: latestHealthDay?.respiratoryRate.map {
                                "\($0.formatted(.number.precision(.fractionLength(1)))) /min"
                            } ?? "—",
                            source: includedHealthMetrics.contains(.respiratoryRate)
                                ? "Apple Health" : "Excluded in Settings"
                        )
                        metricRow(
                            "Sleep",
                            value: latestWhoopSleep?.sleepMinutes.map(Self.duration)
                                ?? latestHealthDay?.sleepMinutes.map(Self.duration) ?? "—",
                            source: latestWhoopSleep?.sleepMinutes != nil
                                ? "WHOOP"
                                : latestHealthDay?.sleepMinutes != nil
                                    ? "Apple Health" : "WHOOP / Apple Health"
                        )
                        if let sources = latestHealthDay?.sources, !sources.isEmpty {
                            Text("Apple Health sources: \(sources.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    FoundationCard(title: "Sleep Deadline") {
                        if let sleepDeadline {
                            statusRow(
                                "Begin wind-down",
                                value: sleepDeadline.windDownAt.formatted(
                                    date: .omitted, time: .shortened)
                            )
                            statusRow(
                                "Lights out",
                                value: sleepDeadline.lightsOutAt.formatted(
                                    date: .omitted, time: .shortened)
                            )
                            statusRow(
                                "Required wake time",
                                value: sleepDeadline.wakeAt.formatted(
                                    date: .abbreviated, time: .shortened)
                            )
                            Text(
                                "Target \(Self.duration(sleepSettings.targetSleepMinutes)) plus \(sleepSettings.sleepLatencyMinutes) minutes to fall asleep."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    FoundationCard(title: "Data Sync") {
                        Text(syncState)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await synchronizeSources() }
                        } label: {
                            if isSyncing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Synchronize connected sources")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSyncing)
                    }

                    FoundationCard(title: "Backend") {
                        Text(backendState)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("backend-status")

                        Button {
                            Task { await checkBackend() }
                        } label: {
                            if isCheckingBackend {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Check connection")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCheckingBackend)
                        .accessibilityIdentifier("check-backend")
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .task { await refreshOnLaunch() }
            .onReceive(
                NotificationCenter.default.publisher(for: .healthMetricInclusionDidChange)
            ) { _ in
                Task { await loadHistory() }
            }
            .sheet(isPresented: $isShowingCheckIn) {
                MorningCheckInView(
                    checkIn: checkIn ?? MorningCheckIn.empty(day: currentDay),
                    isExisting: checkIn != nil,
                    onSave: { value in await saveCheckIn(value) },
                    onDelete: { day in await deleteCheckIn(day: day) }
                )
            }
            .sheet(isPresented: $isShowingOverride) {
                if let assessment {
                    AssessmentOverrideView(assessment: assessment) { recommendation, note in
                        await saveOverride(recommendation: recommendation, note: note)
                    }
                }
            }
            .sheet(isPresented: $isShowingExperimentLog) {
                NavigationStack {
                    DailyExperimentLogView(
                        experiments: activeExperiments,
                        experimentRepository: experimentRepository
                    ) {
                        await loadActiveExperiments()
                    }
                }
            }
            .alert("Couldn’t calculate readiness", isPresented: assessmentErrorIsPresented) {
                Button("OK", role: .cancel) { assessmentError = nil }
            } message: {
                Text(assessmentError ?? "Unknown error")
            }
        }
    }

    private var latestHealthDay: HealthKitDailySummary? {
        healthHistory.days.first
    }

    private var currentDay: String {
        HealthDayKey.day(containing: .now, timeZone: .autoupdatingCurrent)
    }

    private var assessmentErrorIsPresented: Binding<Bool> {
        Binding(
            get: { assessmentError != nil },
            set: { if !$0 { assessmentError = nil } }
        )
    }

    private func assessmentRow(_ title: String, score: Int?) -> some View {
        LabeledContent(title, value: score.map { "\($0)/100" } ?? "Unavailable")
    }

    @ViewBuilder
    private func tissueReadinessRow(_ assessment: ReadinessAssessment) -> some View {
        if assessment.reasons.contains(where: { reason in
            if case .restriction = reason.direction { return true }
            return false
        }) {
            LabeledContent("Tissue readiness") {
                Label("Restricted", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tissue readiness")
            .accessibilityValue("Restricted because an active Avoid restriction applies")
        } else {
            assessmentRow("Tissue readiness", score: assessment.tissueScore)
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func reasonSymbol(_ direction: ReadinessReason.Direction) -> String {
        switch direction {
        case .positive: "checkmark.circle"
        case .caution: "exclamationmark.triangle"
        case .restriction: "hand.raised.fill"
        case .missing: "questionmark.circle"
        }
    }

    private func metricRow(_ title: String, value: String, source: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private static func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    @MainActor
    private func checkBackend() async {
        isCheckingBackend = true
        defer { isCheckingBackend = false }

        do {
            let health = try await healthChecker.health()
            backendState = "Connected to \(health.service) v\(health.version)"
        } catch {
            backendState = error.localizedDescription
        }
    }

    @MainActor
    private func synchronizeSources() async {
        isSyncing = true
        defer { isSyncing = false }

        var details: [String] = []
        var issues: [String] = []
        do {
            let whoopStatus = try await whoopRepository.connectionStatus()
            if whoopStatus.connected {
                let summary = try await whoopRepository.synchronize()
                details.append("WHOOP \(summary.recordCount)")
            }
        } catch {
            issues.append("WHOOP: \(error.localizedDescription)")
        }

        if await healthKitRepository.authorizationState() == .requested {
            do {
                let summary = try await healthKitRepository.synchronize()
                details.append("Apple Health \(summary.recordCount)")
            } catch {
                issues.append("Apple Health: \(error.localizedDescription)")
            }
        }

        await loadHistory()
        if !issues.isEmpty {
            syncState = issues.joined(separator: " ")
        } else {
            syncState =
                details.isEmpty
                ? "Connect a source in Settings"
                : "Imported changes: \(details.joined(separator: ", "))"
        }
    }

    @MainActor
    private func loadHistory() async {
        do {
            let history = try await whoopRepository.history()
            whoopHistory = history
            latestRecovery = history.recoveries.first
            latestWhoopSleep = TodaySleepSelector.primarySleep(
                for: currentDay,
                in: history.sleeps,
                timeZone: .autoupdatingCurrent
            )
            healthHistory = try await healthKitRepository.history()
            includedHealthMetrics = await healthKitRepository.includedMetrics()
            let lastSyncAt = [history.lastSyncAt, healthHistory.lastSyncAt].compactMap { $0 }.max()
            if let lastSyncAt {
                syncState =
                    "Last synchronized \(lastSyncAt.formatted(.relative(presentation: .named)))"
            }
            await calculateAssessment()
        } catch {
            syncState = error.localizedDescription
        }
    }

    @MainActor
    private func refreshOnLaunch() async {
        do {
            try await assessmentRepository.prepareDefaults()
        } catch {
            assessmentError = error.localizedDescription
        }
        await loadHistory()
        await loadActiveExperiments()
        let status = try? await whoopRepository.connectionStatus()
        let healthState = await healthKitRepository.authorizationState()
        if status?.connected == true || healthState == .requested {
            await synchronizeSources()
        }
    }

    @MainActor
    private func loadActiveExperiments() async {
        guard FeatureFlags.experimentLabEnabled(storedValue: experimentLabEnabled) else {
            activeExperiments = []
            return
        }
        do {
            activeExperiments = try await experimentRepository.experiments(includeArchived: false)
                .filter { $0.status == .active }
        } catch {
            assessmentError = error.localizedDescription
        }
    }

    @MainActor
    private func calculateAssessment() async {
        do {
            checkIn = try await assessmentRepository.checkIn(for: currentDay)
            let restrictions = try await assessmentRepository.restrictions().filter { $0.isActive }
            sleepSettings = try await assessmentRepository.sleepSettings()
            sleepDeadline = SleepDeadlineCalculator.calculate(
                now: .now,
                settings: sleepSettings
            )

            let appleRestingHeartRates = healthHistory.days.compactMap(\.restingHeartRate)
            let whoopRestingHeartRates = whoopHistory.recoveries.compactMap {
                $0.restingHeartRate.map(Double.init)
            }
            let usesAppleRestingHeartRate = latestHealthDay?.restingHeartRate != nil
            let input = ReadinessInput(
                date: .now,
                day: currentDay,
                physiology: PhysiologyReadinessInput(
                    whoopRecovery: latestRecovery?.recoveryScore,
                    whoopHRVRMSSD: latestRecovery?.hrvRMSSD,
                    whoopHRVHistory: Array(
                        whoopHistory.recoveries.dropFirst().compactMap(\.hrvRMSSD).reversed()
                    ),
                    appleHRVSDNN: latestHealthDay?.hrvSDNNMilliseconds,
                    appleHRVHistory: Array(
                        healthHistory.days.dropFirst().compactMap(\.hrvSDNNMilliseconds).reversed()
                    ),
                    restingHeartRate: latestHealthDay?.restingHeartRate
                        ?? latestRecovery?.restingHeartRate.map(Double.init),
                    restingHeartRateHistory: Array(
                        (usesAppleRestingHeartRate
                            ? appleRestingHeartRates.dropFirst()
                            : whoopRestingHeartRates.dropFirst()).reversed()
                    ),
                    sleepMinutes: latestWhoopSleep?.sleepMinutes ?? latestHealthDay?.sleepMinutes
                ),
                checkIn: checkIn,
                activeRestrictions: restrictions,
                sleepSettings: sleepSettings
            )
            let calculated = try await readinessEngine.assess(input)
            try await assessmentRepository.saveAssessment(calculated)
            assessment = try await assessmentRepository.assessment(for: currentDay) ?? calculated
        } catch {
            assessmentError = error.localizedDescription
        }
    }

    @MainActor
    private func saveCheckIn(_ value: MorningCheckIn) async -> Bool {
        do {
            try await assessmentRepository.saveCheckIn(value)
            await calculateAssessment()
            return true
        } catch {
            assessmentError = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func deleteCheckIn(day: String) async -> Bool {
        do {
            try await assessmentRepository.deleteCheckIn(day: day)
            checkIn = nil
            await calculateAssessment()
            return true
        } catch {
            assessmentError = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func saveOverride(
        recommendation: ReadinessAssessment.Recommendation?,
        note: String?
    ) async -> Bool {
        guard let assessment else { return false }
        do {
            try await assessmentRepository.saveOverride(
                assessmentID: assessment.id,
                recommendation: recommendation,
                note: note
            )
            self.assessment = try await assessmentRepository.assessment(for: currentDay)
            return true
        } catch {
            assessmentError = error.localizedDescription
            return false
        }
    }
}

enum TodaySleepSelector {
    static func primarySleep(
        for day: String,
        in sleeps: [SleepHistoryItem],
        timeZone: TimeZone
    ) -> SleepHistoryItem? {
        sleeps.first {
            !$0.isNap
                && HealthDayKey.day(containing: $0.end ?? $0.start, timeZone: timeZone) == day
        }
    }
}

#Preview {
    TodayView(
        healthChecker: PreviewHealthChecker(),
        whoopRepository: PreviewWhoopRepository(),
        healthKitRepository: PreviewHealthKitRepository(),
        assessmentRepository: PreviewAssessmentRepository(),
        readinessEngine: VersionedReadinessEngine(),
        workoutRepository: PreviewWorkoutRepository(),
        protocolRepository: PreviewProtocolRepository(),
        docketRepository: PreviewDocketRepository(),
        experimentRepository: PreviewExperimentRepository()
    )
}
