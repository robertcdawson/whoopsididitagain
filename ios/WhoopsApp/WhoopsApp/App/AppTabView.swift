import SwiftUI

struct AppTabView: View {
    let healthChecker: any BackendHealthChecking
    let whoopRepository: any WhoopRepository
    let healthKitRepository: any HealthKitRepository
    let assessmentRepository: any AssessmentRepository
    let readinessEngine: any ReadinessEngine
    let workoutParser: any WorkoutParser
    let workoutScalingEngine: any WorkoutScalingEngine
    let workoutRepository: any WorkoutRepository
    let movementLibrary: any MovementLibraryRepository
    let protocolParser: any ProtocolParser
    let protocolRepository: any ProtocolRepository
    let docketRepository: any DocketRepository
    let experimentRepository: any ExperimentRepository
    let reminderService: LocalReminderService
    @State private var selectedZone = "Today"
    @State private var showingSettings = false
    @State private var morningCheckInRequest = 0
    @AppStorage("journalLeftHanded") private var leftHanded = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedZone) {
                TodayView(
                    healthChecker: healthChecker,
                    whoopRepository: whoopRepository,
                    healthKitRepository: healthKitRepository,
                    assessmentRepository: assessmentRepository,
                    readinessEngine: readinessEngine,
                    workoutRepository: workoutRepository,
                    protocolRepository: protocolRepository,
                    docketRepository: docketRepository,
                    movementLibrary: movementLibrary,
                    experimentRepository: experimentRepository,
                    morningCheckInRequest: morningCheckInRequest
                )
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag("Today")

                TrainingView(
                    parser: workoutParser,
                    scalingEngine: workoutScalingEngine,
                    workoutRepository: workoutRepository,
                    assessmentRepository: assessmentRepository,
                    movementLibrary: movementLibrary,
                    protocolParser: protocolParser,
                    protocolRepository: protocolRepository,
                    docketRepository: docketRepository
                )
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label("Work", systemImage: "figure.cross.training")
                }
                .tag("Work")

                TrendsView(
                    whoopRepository: whoopRepository,
                    healthKitRepository: healthKitRepository,
                    assessmentRepository: assessmentRepository,
                    workoutRepository: workoutRepository,
                    experimentRepository: experimentRepository
                )
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label("Body", systemImage: "chart.xyaxis.line")
                }
                .tag("Body")
            }
            .toolbar(.hidden, for: .tabBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            journalNavigation
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color.journalPaper.ignoresSafeArea())
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                whoopRepository: whoopRepository,
                healthKitRepository: healthKitRepository,
                assessmentRepository: assessmentRepository,
                reminderService: reminderService
            )
        }
        .font(.journal())
        .tint(.journalInk)
        // DESIGN.md explicitly permits a light-only journal until dark artwork is designed.
        .preferredColorScheme(.light)
        .onOpenURL { url in
            guard url.scheme == "whoops" else { return }
            switch url.host?.lowercased() {
            case "work": selectedZone = "Work"
            case "body": selectedZone = "Body"
            case "settings": showingSettings = true
            default: selectedZone = "Today"
            }
        }
        .task { consumePendingRoute() }
        .onReceive(
            NotificationCenter.default.publisher(for: PendingAppRouteStore.routeRequested)
        ) { _ in
            consumePendingRoute()
        }
    }

    private func consumePendingRoute() {
        guard let route = PendingAppRouteStore().consume() else { return }
        selectedZone = "Today"
        if route == .morningCheckIn {
            morningCheckInRequest += 1
        }
    }

    private var journalNavigation: some View {
        VStack(spacing: 8) {
            JournalRule()
            HStack(spacing: 8) {
                if leftHanded { settingsButton }
                ForEach(["Today", "Work", "Body"], id: \.self) { zone in
                    Button {
                        selectedZone = zone
                    } label: {
                        Text(zone.lowercased())
                            .font(
                                .journal(
                                    .subheadline, weight: selectedZone == zone ? .bold : .regular)
                            )
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(
                                Color.journalInk.opacity(selectedZone == zone ? 1 : 0.65)
                            )
                            .padding(.horizontal, 8)
                            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .overlay {
                                if selectedZone == zone {
                                    JournalTabOutline().stroke(Color.journalInk, lineWidth: 2.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(zone)
                    .accessibilityIdentifier("zone-\(zone.lowercased())")
                    .accessibilityAddTraits(selectedZone == zone ? .isSelected : [])
                }
                if !leftHanded { settingsButton }
            }
        }
        .padding(.leading, leftHanded ? 24 : 56)
        .padding(.trailing, leftHanded ? 56 : 24)
        .padding(.bottom, 6)
        .background { JournalPaperBackground() }
        .accessibilityElement(children: .contain)
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20))
                .foregroundStyle(Color.journalInk.opacity(0.7))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("journal-settings")
    }
}

#Preview {
    AppTabView(
        healthChecker: PreviewHealthChecker(),
        whoopRepository: PreviewWhoopRepository(),
        healthKitRepository: PreviewHealthKitRepository(),
        assessmentRepository: PreviewAssessmentRepository(),
        readinessEngine: VersionedReadinessEngine(),
        workoutParser: VersionedWorkoutParser(),
        workoutScalingEngine: DeterministicWorkoutScalingEngine(),
        workoutRepository: PreviewWorkoutRepository(),
        movementLibrary: PreviewMovementLibraryRepository(),
        protocolParser: DeterministicProtocolParser(),
        protocolRepository: PreviewProtocolRepository(),
        docketRepository: PreviewDocketRepository(),
        experimentRepository: PreviewExperimentRepository(),
        reminderService: .live()
    )
}
