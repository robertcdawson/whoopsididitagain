import AppIntents
import SwiftData
import SwiftUI

@main
struct WhoopsApp: App {
    @UIApplicationDelegateAdaptor(ReminderNotificationDelegate.self)
    private var notificationDelegate

    private let healthChecker: any BackendHealthChecking
    private let whoopRepository: any WhoopRepository
    private let healthKitRepository: any HealthKitRepository
    private let assessmentRepository: any AssessmentRepository
    private let readinessEngine: any ReadinessEngine
    private let workoutParser: any WorkoutParser
    private let workoutScalingEngine: any WorkoutScalingEngine
    private let workoutRepository: any WorkoutRepository
    private let movementLibrary: any MovementLibraryRepository
    private let protocolParser: any ProtocolParser
    private let protocolRepository: any ProtocolRepository
    private let docketRepository: any DocketRepository
    private let experimentRepository: any ExperimentRepository
    private let reminderService: LocalReminderService
    private let modelContainer: ModelContainer

    init() {
        WhoopsAppShortcuts.updateAppShortcutParameters()

        let configuredURL = ProcessInfo.processInfo.environment["WHOOPS_BACKEND_URL"]
        let baseURL = URL(
            string: configuredURL ?? "https://whoopsididitagain-backend.vercel.app"
        )!
        let sessionStore = KeychainSessionStore()
        let container = try! ModelContainer(
            for: WhoopSourceRecord.self,
            HealthKitSourceRecord.self,
            WorkoutSourceLink.self,
            InjuryRecord.self,
            RestrictionRecord.self,
            SymptomCheckInRecord.self,
            PainLogRecord.self,
            ReadinessAssessmentRecord.self,
            SleepScheduleRecord.self,
            WorkoutPlanRecord.self,
            WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            MovementDefinitionRecord.self,
            TherapyProtocolRecord.self,
            TherapyProtocolItemRecord.self,
            DocketCompletionRecord.self,
            ExperimentRecord.self,
            ExperimentObservationRecord.self
        )
        let client = BackendClient(baseURL: baseURL, sessionStore: sessionStore)
        let healthKitClient = HealthKitClient()

        modelContainer = container
        healthChecker = client
        whoopRepository = LiveWhoopRepository(
            client: client,
            persistence: WhoopPersistence(container: container)
        )
        healthKitRepository = LiveHealthKitRepository(
            client: healthKitClient,
            persistence: HealthKitPersistence(container: container),
            anchors: HealthKitAnchorStore()
        )
        assessmentRepository = AssessmentPersistence(container: container)
        readinessEngine = VersionedReadinessEngine()
        let library = MovementLibraryPersistence(container: container)
        movementLibrary = library
        workoutParser = LibraryWorkoutParser(
            library: library,
            model: FeatureFlags.appleWorkoutParserTestModeEnabled()
                ? AppleWorkoutModelClient() : nil,
            isAIEnabled: {
                UserDefaults.standard.bool(forKey: "appleWorkoutParsingEnabled")
            }
        )
        workoutScalingEngine = LibraryWorkoutScalingEngine(library: library)
        workoutRepository = WorkoutPersistence(container: container)
        protocolParser = LibraryProtocolParser(library: library)
        protocolRepository = ProtocolPersistence(container: container)
        docketRepository = DocketPersistence(container: container)
        experimentRepository = ExperimentPersistence(container: container)
        reminderService = .live()
    }

    var body: some Scene {
        WindowGroup {
            AppTabView(
                healthChecker: healthChecker,
                whoopRepository: whoopRepository,
                healthKitRepository: healthKitRepository,
                assessmentRepository: assessmentRepository,
                readinessEngine: readinessEngine,
                workoutParser: workoutParser,
                workoutScalingEngine: workoutScalingEngine,
                workoutRepository: workoutRepository,
                movementLibrary: movementLibrary,
                protocolParser: protocolParser,
                protocolRepository: protocolRepository,
                docketRepository: docketRepository,
                experimentRepository: experimentRepository,
                reminderService: reminderService
            )
            .modelContainer(modelContainer)
            .task {
                await healthKitRepository.startObserving()
                if let settings = try? await assessmentRepository.sleepSettings() {
                    await reminderService.refreshEnabledSchedules(settings: settings)
                }
            }
        }
    }
}
