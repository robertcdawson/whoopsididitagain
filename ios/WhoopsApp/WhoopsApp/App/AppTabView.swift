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

    var body: some View {
        TabView {
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
                experimentRepository: experimentRepository
            )
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }

            TrainingView(
                parser: workoutParser,
                scalingEngine: workoutScalingEngine,
                workoutRepository: workoutRepository,
                assessmentRepository: assessmentRepository,
                movementLibrary: movementLibrary,
                protocolParser: protocolParser,
                protocolRepository: protocolRepository
            )
            .tabItem {
                Label("Train", systemImage: "figure.cross.training")
            }

            TrendsView(
                whoopRepository: whoopRepository,
                healthKitRepository: healthKitRepository,
                assessmentRepository: assessmentRepository,
                workoutRepository: workoutRepository,
                experimentRepository: experimentRepository
            )
            .tabItem {
                Label("Trends", systemImage: "chart.xyaxis.line")
            }

            SettingsView(
                whoopRepository: whoopRepository,
                healthKitRepository: healthKitRepository,
                assessmentRepository: assessmentRepository
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(.accentColor)
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
        experimentRepository: PreviewExperimentRepository()
    )
}
