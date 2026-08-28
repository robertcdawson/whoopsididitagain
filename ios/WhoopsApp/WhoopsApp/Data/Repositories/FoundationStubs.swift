import Foundation

struct UnavailableWhoopRepository: WhoopRepository {
    func authorizationURL() async throws -> URL { throw AppError.notImplemented }
    func completeAuthorization(callbackURL: URL) async throws { throw AppError.notImplemented }
    func connectionStatus() async throws -> WhoopConnectionStatus {
        WhoopConnectionStatus(connected: false, whoopUserId: nil, tokenExpiresAt: nil)
    }
    func synchronize() async throws -> WhoopSyncSummary { throw AppError.notImplemented }
    func history() async throws -> WhoopHistorySnapshot {
        WhoopHistorySnapshot(recoveries: [], sleeps: [], lastSyncAt: nil)
    }
    func disconnect(deleteLocalHistory: Bool) async throws { throw AppError.notImplemented }
}

struct PreviewWhoopRepository: WhoopRepository {
    func authorizationURL() async throws -> URL { URL(string: "https://example.com")! }
    func completeAuthorization(callbackURL: URL) async throws {}
    func connectionStatus() async throws -> WhoopConnectionStatus {
        WhoopConnectionStatus(connected: false, whoopUserId: nil, tokenExpiresAt: nil)
    }
    func synchronize() async throws -> WhoopSyncSummary {
        WhoopSyncSummary(syncedAt: .now, recordCount: 0, mode: "preview")
    }
    func history() async throws -> WhoopHistorySnapshot {
        WhoopHistorySnapshot(recoveries: [], sleeps: [], lastSyncAt: nil)
    }
    func disconnect(deleteLocalHistory: Bool) async throws {}
}

struct UnavailableHealthKitRepository: HealthKitRepository {
    func authorizationState() async -> HealthKitAuthorizationState { .unavailable }
    func requestReadAuthorization() async throws { throw AppError.notImplemented }
    func synchronize() async throws -> HealthKitSyncSummary { throw AppError.notImplemented }
    func history() async throws -> HealthKitHistorySnapshot {
        HealthKitHistorySnapshot(days: [], lastSyncAt: nil, recordCount: 0, linkedWorkoutCount: 0)
    }
    func history(metrics _: [HealthMetric]) async throws -> HealthKitHistorySnapshot {
        try await history()
    }
    func startObserving() async {}
}

struct PreviewHealthKitRepository: HealthKitRepository {
    func authorizationState() async -> HealthKitAuthorizationState { .requested }
    func requestReadAuthorization() async throws {}
    func synchronize() async throws -> HealthKitSyncSummary {
        HealthKitSyncSummary(
            syncedAt: .now,
            recordCount: 0,
            deletedCount: 0,
            linkedWorkoutCount: 0
        )
    }
    func history() async throws -> HealthKitHistorySnapshot {
        HealthKitHistorySnapshot(days: [], lastSyncAt: nil, recordCount: 0, linkedWorkoutCount: 0)
    }
    func history(metrics _: [HealthMetric]) async throws -> HealthKitHistorySnapshot {
        try await history()
    }
    func startObserving() async {}
}

struct UnavailableReadinessEngine: ReadinessEngine {
    func assess(_ input: ReadinessInput) async throws -> ReadinessAssessment {
        throw AppError.notImplemented
    }
}

actor PreviewWorkoutRepository: WorkoutRepository {
    private var savedPlans: [WorkoutPlan] = []
    private var savedWorkouts: [CompletedWorkout] = []

    func plans() async throws -> [WorkoutPlan] { savedPlans }
    func savePlan(_ plan: WorkoutPlan) async throws {
        savedPlans.removeAll { $0.id == plan.id }
        savedPlans.append(plan)
    }
    func deletePlan(id: String) async throws { savedPlans.removeAll { $0.id == id } }
    func completedWorkouts() async throws -> [CompletedWorkout] { savedWorkouts }
    func saveCompletedWorkout(_ workout: CompletedWorkout) async throws {
        savedWorkouts.removeAll { $0.id == workout.id }
        savedWorkouts.append(workout)
    }
    func deleteCompletedWorkout(id: String) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }
}

actor PreviewMovementLibraryRepository: MovementLibraryRepository {
    private var definitions = MovementDefinition.bundled

    func prepareDefaults() async throws {}

    func movements(includeArchived: Bool) async throws -> [MovementDefinition] {
        definitions.filter { includeArchived || !$0.isArchived }
    }

    func usageSummaries() async throws -> [MovementUsageSummary] {
        definitions.filter { !$0.isArchived }.map {
            MovementUsageSummary(movement: $0, appearanceCount: 0, lastUsedAt: nil)
        }
    }

    func saveMovement(_ movement: MovementDefinition) async throws {
        definitions.removeAll { $0.id == movement.id }
        definitions.append(movement)
    }

    func setArchived(_ archived: Bool, movementID: String) async throws {
        guard let index = definitions.firstIndex(where: { $0.id == movementID }) else { return }
        definitions[index].isArchived = archived
    }

    func reconcile(_ plan: WorkoutPlan) async throws -> WorkoutPlan { plan }

    func previewWODLabImport(_ data: Data) async throws -> MovementLibraryImportPreview {
        let parsed = try WODLabMovementImporter().importMovements(from: data)
        let existingNames = Set(definitions.map { $0.canonicalName.lowercased() })
        let additions = parsed.candidates.filter {
            !existingNames.contains($0.name.lowercased())
        }.map { candidate in
            MovementDefinition.custom(name: candidate.name, aliases: candidate.aliases)
        }
        return MovementLibraryImportPreview(
            data: data,
            additions: additions,
            matchedCount: parsed.candidates.count - additions.count,
            skippedCount: parsed.skippedCount,
            issues: parsed.issues.map(\.message)
        )
    }

    func importWODLab(_ data: Data) async throws -> MovementLibraryImportResult {
        let preview = try await previewWODLabImport(data)
        definitions.append(contentsOf: preview.additions)
        return MovementLibraryImportResult(
            addedCount: preview.additions.count,
            matchedCount: preview.matchedCount,
            skippedCount: preview.skippedCount,
            issues: preview.issues
        )
    }
}

actor PreviewAssessmentRepository: AssessmentRepository {
    private var checkIns: [String: MorningCheckIn] = [:]
    private var profiles: [RestrictionProfile] = []
    private var settings = SleepScheduleSettings.standard
    private var assessments: [String: ReadinessAssessment] = [:]

    func prepareDefaults() async throws {}
    func checkIn(for day: String) async throws -> MorningCheckIn? { checkIns[day] }
    func checkIns() async throws -> [MorningCheckIn] {
        checkIns.values.sorted { $0.timestamp > $1.timestamp }
    }
    func saveCheckIn(_ checkIn: MorningCheckIn) async throws { checkIns[checkIn.day] = checkIn }
    func deleteCheckIn(day: String) async throws { checkIns[day] = nil }
    func restrictions() async throws -> [RestrictionProfile] { profiles }
    func saveRestriction(_ restriction: RestrictionProfile) async throws {
        profiles.removeAll { $0.id == restriction.id }
        profiles.append(restriction)
    }
    func deleteRestriction(id: String) async throws { profiles.removeAll { $0.id == id } }
    func sleepSettings() async throws -> SleepScheduleSettings { settings }
    func saveSleepSettings(_ settings: SleepScheduleSettings) async throws {
        self.settings = settings
    }
    func assessment(for day: String) async throws -> ReadinessAssessment? { assessments[day] }
    func assessments() async throws -> [ReadinessAssessment] {
        assessments.values.sorted { $0.computedAt > $1.computedAt }
    }
    func injuryTimeline() async throws -> [InjuryTimelineItem] { [] }
    func saveAssessment(_ assessment: ReadinessAssessment) async throws {
        assessments[assessment.day] = assessment
    }
    func saveOverride(
        assessmentID: String,
        recommendation: ReadinessAssessment.Recommendation?,
        note: String?
    ) async throws {
        guard var assessment = assessments.values.first(where: { $0.id == assessmentID }) else {
            return
        }
        assessment.userOverride = recommendation
        assessment.overrideNote = note
        assessments[assessment.day] = assessment
    }
}

actor PreviewExperimentRepository: ExperimentRepository {
    private var definitions: [ExperimentDefinition] = []
    private var savedObservations: [ExperimentObservation] = []

    func experiments(includeArchived: Bool) async throws -> [ExperimentDefinition] {
        definitions.filter { includeArchived || $0.status != .archived }
    }

    func saveExperiment(_ experiment: ExperimentDefinition) async throws {
        definitions.removeAll { $0.id == experiment.id }
        definitions.append(experiment)
    }

    func deleteExperiment(id: String) async throws {
        definitions.removeAll { $0.id == id }
        savedObservations.removeAll { $0.experimentID == id }
    }

    func observations(experimentID: String) async throws -> [ExperimentObservation] {
        savedObservations.filter { $0.experimentID == experimentID }
    }

    func saveObservation(_ observation: ExperimentObservation) async throws {
        try await saveObservations([observation])
    }

    func replaceObservation(id originalID: String, with observation: ExperimentObservation)
        async throws
    {
        if savedObservations.contains(where: {
            $0.id != originalID
                && $0.experimentID == observation.experimentID
                && $0.day == observation.day
        }) {
            throw ExperimentValidationError.observationDayConflict
        }
        savedObservations.removeAll { $0.id == originalID }
        try await saveObservations([observation])
    }

    func saveObservations(_ observations: [ExperimentObservation]) async throws {
        for observation in observations {
            savedObservations.removeAll {
                $0.id == observation.id
                    || ($0.experimentID == observation.experimentID && $0.day == observation.day)
            }
            savedObservations.append(observation)
        }
    }

    func deleteObservation(id: String) async throws {
        savedObservations.removeAll { $0.id == id }
    }
}

struct TemplateInsightNarrator: InsightNarrator {
    func narrate(_ context: InsightContext) async throws -> String {
        "Not enough synchronized data is available to generate an insight."
    }
}

actor InMemoryLocalStore: LocalStore {
    private var values: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save<Value: Encodable & Sendable>(_ value: Value, forKey key: String) throws {
        values[key] = try encoder.encode(value)
    }

    func load<Value: Decodable & Sendable>(_ type: Value.Type, forKey key: String) throws -> Value?
    {
        guard let data = values[key] else { return nil }
        return try decoder.decode(type, from: data)
    }

    func deleteAll() {
        values.removeAll()
    }
}

struct PreviewHealthChecker: BackendHealthChecking {
    func health() async throws -> BackendHealth {
        BackendHealth(
            status: "ok",
            service: "whoops-backend",
            version: "0.1.0",
            timestamp: .now
        )
    }
}
