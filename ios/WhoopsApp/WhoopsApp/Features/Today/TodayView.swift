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
    let movementLibrary: any MovementLibraryRepository
    let experimentRepository: any ExperimentRepository
    let morningCheckInRequest: Int

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
    @State private var showingReadinessDetails = false

    var body: some View {
        NavigationStack {
            JournalPage(title: "Today") {
                verdict
                if let assessment {
                    Text(assessment.reasons.first?.message ?? "Your daily assessment is ready.")
                        .font(.journal(.title3)).italic()
                        .foregroundStyle(Color.journalRedPen)
                    JournalReadinessRows(assessment: assessment)
                } else {
                    Text("A little context first.").font(.journal(.title3)).italic()
                    Text("Complete a morning check-in to calculate tissue readiness.")
                        .font(.journal(.subheadline))
                }
                Button(checkIn == nil ? "Complete morning check-in" : "Edit morning check-in") {
                    isShowingCheckIn = true
                }
                .font(.journal(.subheadline))
                .frame(minHeight: 44)
                .accessibilityIdentifier("morning-check-in")

                JournalRule()
                DocketView(
                    protocolRepository: protocolRepository,
                    workoutRepository: workoutRepository,
                    docketRepository: docketRepository,
                    movementLibrary: movementLibrary,
                    sleepDeadline: sleepDeadline
                )
                if FeatureFlags.experimentLabEnabled(storedValue: experimentLabEnabled),
                    !activeExperiments.isEmpty
                {
                    Button("Log experiment day") { isShowingExperimentLog = true }
                        .font(.journal(.subheadline))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("today-experiment-check-in")
                }
                Spacer(minLength: 12)
                Button {
                    showingReadinessDetails.toggle()
                } label: {
                    HStack {
                        Text("Readiness & source details")
                        Spacer()
                        Image(
                            systemName: showingReadinessDetails ? "chevron.down" : "chevron.right")
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(JournalLinkButtonStyle())
                .font(.journal(.footnote))
                .accessibilityValue(showingReadinessDetails ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("readiness-details")
                if showingReadinessDetails {
                    VStack(alignment: .leading, spacing: 14) {
                        if let assessment {
                            assessmentRow("Systemic readiness", score: assessment.systemicScore)
                            assessmentRow("Sleep sufficiency", score: assessment.sleepScore)
                            tissueReadinessRow(assessment)
                            LabeledContent("Confidence", value: assessment.confidence.displayName)
                            if assessment.userOverride != nil {
                                Text(
                                    "Your override is active. Calculated: \(assessment.recommendation.displayName)."
                                )
                            }
                            ForEach(assessment.reasons) { reason in
                                Label(reason.message, systemImage: reasonSymbol(reason.direction))
                            }
                            Button("Override or annotate") { isShowingOverride = true }
                                .frame(minHeight: 44)
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
                                    .font(.journal(.caption))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
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
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                            }
                        }

                        FoundationCard(title: "Data Sync") {
                            Text(syncState)
                                .foregroundStyle(Color.journalInk.opacity(0.7))
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
                            .buttonStyle(JournalPrimaryButtonStyle())
                            .disabled(isSyncing)
                        }

                        FoundationCard(title: "Backend") {
                            Text(backendState)
                                .foregroundStyle(Color.journalInk.opacity(0.7))
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
                            .buttonStyle(JournalPrimaryButtonStyle())
                            .disabled(isCheckingBackend)
                            .accessibilityIdentifier("check-backend")
                        }
                    }
                    .font(.journal(.subheadline))
                    .padding(.top, 12)
                }
                Text(syncState)
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.65))
            }
            .refreshable { await synchronizeSources() }
            .task { await refreshOnLaunch() }
            .onChange(of: morningCheckInRequest) { _, request in
                guard request > 0 else { return }
                isShowingCheckIn = true
            }
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

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verdictText)
                .font(.custom("Caveat-Regular", size: 66, relativeTo: .largeTitle).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today-verdict")
            SquiggleDivider()
                .stroke(Color.journalInk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 180, height: 12)
                .accessibilityHidden(true)
        }
    }

    private var verdictText: String {
        guard let assessment else { return "Check in." }
        switch assessment.effectiveRecommendation {
        case .proceed: return "Send it."
        case .proceedWithLimits: return "Easy does it."
        case .modify: return "Modify."
        case .recoveryFocused: return "Take it easy."
        }
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
                    .foregroundStyle(Color.journalInk.opacity(0.7))
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
                .foregroundStyle(Color.journalInk.opacity(0.7))
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
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
            Spacer()
            Text(value)
                .foregroundStyle(Color.journalInk.opacity(0.7))
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
        movementLibrary: PreviewMovementLibraryRepository(),
        experimentRepository: PreviewExperimentRepository(),
        morningCheckInRequest: 0
    )
}
