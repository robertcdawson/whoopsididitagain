import Foundation

protocol BackendHealthChecking: Sendable {
    func health() async throws -> BackendHealth
}

protocol WhoopRepository: Sendable {
    func authorizationURL() async throws -> URL
    func completeAuthorization(callbackURL: URL) async throws
    func connectionStatus() async throws -> WhoopConnectionStatus
    func synchronize() async throws -> WhoopSyncSummary
    func history() async throws -> WhoopHistorySnapshot
    func disconnect(deleteLocalHistory: Bool) async throws
}

protocol SessionStoring: Sendable {
    func installationId() throws -> String
    func session() throws -> AppSessionPair?
    func save(session: AppSessionPair) throws
    func deleteSession() throws
}

protocol HealthKitRepository: Sendable {
    func authorizationState() async -> HealthKitAuthorizationState
    func requestReadAuthorization() async throws
    func synchronize() async throws -> HealthKitSyncSummary
    func history() async throws -> HealthKitHistorySnapshot
    func startObserving() async
}

protocol HealthKitReading: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestReadAuthorization() async throws
    func anchoredChanges(for metric: HealthMetric, anchorData: Data?) async throws
        -> HealthKitChangeBatch
    func startObserving(
        onChange: @escaping @Sendable (HealthMetric) async -> Void
    ) async
}

protocol HealthKitAnchorStoring: Sendable {
    func authorizationWasRequested() -> Bool
    func markAuthorizationRequested()
    func anchorData(for metric: HealthMetric) -> Data?
    func saveAnchorData(_ data: Data, for metric: HealthMetric)
}

protocol WorkoutParser: Sendable {
    func parse(rawText: String) async throws -> ParsedWorkout
}

protocol WorkoutScalingEngine: Sendable {
    func evaluate(
        plan: WorkoutPlan,
        restrictions: [RestrictionProfile]
    ) async -> WorkoutEvaluation
}

protocol WorkoutRepository: Sendable {
    func plans() async throws -> [WorkoutPlan]
    func savePlan(_ plan: WorkoutPlan) async throws
    func deletePlan(id: String) async throws
    func completedWorkouts() async throws -> [CompletedWorkout]
    func saveCompletedWorkout(_ workout: CompletedWorkout) async throws
}

protocol MovementLibraryRepository: Sendable {
    func prepareDefaults() async throws
    func movements(includeArchived: Bool) async throws -> [MovementDefinition]
    func usageSummaries() async throws -> [MovementUsageSummary]
    func saveMovement(_ movement: MovementDefinition) async throws
    func setArchived(_ archived: Bool, movementID: String) async throws
    func reconcile(_ plan: WorkoutPlan) async throws -> WorkoutPlan
    func previewWODLabImport(_ data: Data) async throws -> MovementLibraryImportPreview
    func importWODLab(_ data: Data) async throws -> MovementLibraryImportResult
}

protocol ProtocolParser: Sendable {
    func parse(rawText: String, source: ProtocolSource) async throws -> ParsedProtocol
}

protocol ProtocolRepository: Sendable {
    func protocols(includeArchived: Bool) async throws -> [TherapyProtocol]
    func saveProtocol(_ therapyProtocol: TherapyProtocol) async throws
    func deleteProtocol(id: String) async throws
}

protocol DocketRepository: Sendable {
    func completions(days: [String]) async throws -> [DocketCompletion]
    func saveCompletion(_ completion: DocketCompletion) async throws
    func deleteCompletion(id: String) async throws
}

protocol ReadinessEngine: Sendable {
    func assess(_ input: ReadinessInput) async throws -> ReadinessAssessment
}

protocol AssessmentRepository: Sendable {
    func prepareDefaults() async throws
    func checkIn(for day: String) async throws -> MorningCheckIn?
    func checkIns() async throws -> [MorningCheckIn]
    func saveCheckIn(_ checkIn: MorningCheckIn) async throws
    func restrictions() async throws -> [RestrictionProfile]
    func saveRestriction(_ restriction: RestrictionProfile) async throws
    func deleteRestriction(id: String) async throws
    func sleepSettings() async throws -> SleepScheduleSettings
    func saveSleepSettings(_ settings: SleepScheduleSettings) async throws
    func assessment(for day: String) async throws -> ReadinessAssessment?
    func assessments() async throws -> [ReadinessAssessment]
    func injuryTimeline() async throws -> [InjuryTimelineItem]
    func saveAssessment(_ assessment: ReadinessAssessment) async throws
    func saveOverride(
        assessmentID: String,
        recommendation: ReadinessAssessment.Recommendation?,
        note: String?
    ) async throws
}

protocol InsightNarrator: Sendable {
    func narrate(_ context: InsightContext) async throws -> String
}

protocol LocalStore: Sendable {
    func save<Value: Encodable & Sendable>(_ value: Value, forKey key: String) async throws
    func load<Value: Decodable & Sendable>(_ type: Value.Type, forKey key: String) async throws
        -> Value?
    func deleteAll() async throws
}
