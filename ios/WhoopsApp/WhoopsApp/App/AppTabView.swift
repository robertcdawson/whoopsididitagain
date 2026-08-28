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
    let experimentRepository: any ExperimentRepository

    var body: some View {
        TabView {
            TodayView(
                healthChecker: healthChecker,
                whoopRepository: whoopRepository,
                healthKitRepository: healthKitRepository,
                assessmentRepository: assessmentRepository,
                readinessEngine: readinessEngine,
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
                movementLibrary: movementLibrary
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
        experimentRepository: PreviewExperimentRepository()
    )
}
