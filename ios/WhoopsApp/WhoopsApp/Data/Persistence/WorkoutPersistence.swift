import Foundation
import SwiftData

@Model
final class WorkoutPlanRecord {
    @Attribute(.unique) var id: String
    var title: String
    var rawText: String
    var parsedAt: Date
    var scheduledAt: Date
    var status: String
    var format: String
    var intendedStimulusData: Data
    var timeCapSeconds: Int?
    var parserVersion: String
    var modelVersion: String?
    var confidence: Double
    var ambiguitiesData: Data
    var updatedAt: Date

    init(plan: WorkoutPlan, stimulusData: Data, ambiguitiesData: Data, updatedAt: Date) {
        id = plan.id
        title = plan.title
        rawText = plan.rawText
        parsedAt = plan.parsedAt
        scheduledAt = plan.scheduledAt
        status = plan.status.rawValue
        format = plan.format.rawValue
        intendedStimulusData = stimulusData
        timeCapSeconds = plan.timeCapSeconds
        parserVersion = plan.parserVersion
        modelVersion = plan.modelVersion
        confidence = plan.confidence
        self.ambiguitiesData = ambiguitiesData
        self.updatedAt = updatedAt
    }
}

@Model
final class WorkoutSegmentRecord {
    @Attribute(.unique) var id: String
    var workoutPlanID: String
    var sequence: Int
    var type: String
    var rounds: Int?
    var durationSeconds: Int?
    var restSeconds: Int?
    var notes: String

    init(segment: WorkoutSegment, workoutPlanID: String) {
        id = segment.id
        self.workoutPlanID = workoutPlanID
        sequence = segment.sequence
        type = segment.type.rawValue
        rounds = segment.rounds
        durationSeconds = segment.durationSeconds
        restSeconds = segment.restSeconds
        notes = segment.notes
    }
}

@Model
final class MovementPrescriptionRecord {
    @Attribute(.unique) var id: String
    var segmentID: String
    var canonicalMovementID: String?
    var displayName: String
    var originalText: String
    var repetitions: Int?
    var distanceMeters: Int?
    var calories: Int?
    var loadValue: Double?
    var loadUnit: String?
    var percentageOfOneRepMax: Double?
    var durationSeconds: Int?
    var tempo: String?
    var notes: String

    init(movement: MovementPrescription, segmentID: String) {
        id = movement.id
        self.segmentID = segmentID
        canonicalMovementID = movement.canonicalMovementID
        displayName = movement.displayName
        originalText = movement.originalText
        repetitions = movement.repetitions
        distanceMeters = movement.distanceMeters
        calories = movement.calories
        loadValue = movement.loadValue
        loadUnit = movement.loadUnit
        percentageOfOneRepMax = movement.percentageOfOneRepMax
        durationSeconds = movement.durationSeconds
        tempo = movement.tempo
        notes = movement.notes
    }
}

@Model
final class CompletedWorkoutRecord {
    @Attribute(.unique) var id: String
    var plannedWorkoutID: String?
    var title: String
    var startedAt: Date
    var endedAt: Date
    var sessionRPE: Int
    var postSessionPain: Int
    var notes: String

    init(workout: CompletedWorkout) {
        id = workout.id
        plannedWorkoutID = workout.plannedWorkoutID
        title = workout.title
        startedAt = workout.startedAt
        endedAt = workout.endedAt
        sessionRPE = workout.sessionRPE
        postSessionPain = workout.postSessionPain
        notes = workout.notes
    }
}

@Model
final class CompletedMovementRecord {
    @Attribute(.unique) var id: String
    var workoutRecordID: String
    var canonicalMovementID: String?
    var plannedPrescriptionID: String?
    var displayName: String
    var actualRepetitions: Int?
    var actualDistanceMeters: Int?
    var actualCalories: Int?
    var actualLoadValue: Double?
    var actualLoadUnit: String?
    var actualDurationSeconds: Int?
    var modification: String
    var painDuring: Int
    var notes: String

    init(movement: CompletedMovement, workoutRecordID: String) {
        id = movement.id
        self.workoutRecordID = workoutRecordID
        canonicalMovementID = movement.canonicalMovementID
        plannedPrescriptionID = movement.plannedPrescriptionID
        displayName = movement.displayName
        actualRepetitions = movement.actualRepetitions
        actualDistanceMeters = movement.actualDistanceMeters
        actualCalories = movement.actualCalories
        actualLoadValue = movement.actualLoadValue
        actualLoadUnit = movement.actualLoadUnit
        actualDurationSeconds = movement.actualDurationSeconds
        modification = movement.modification
        painDuring = movement.painDuring
        notes = movement.notes
    }
}

@MainActor
final class WorkoutPersistence: WorkoutRepository, @unchecked Sendable {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func plans() async throws -> [WorkoutPlan] {
        let planRecords = try context.fetch(FetchDescriptor<WorkoutPlanRecord>())
        let segmentRecords = try context.fetch(FetchDescriptor<WorkoutSegmentRecord>())
        let movementRecords = try context.fetch(FetchDescriptor<MovementPrescriptionRecord>())
        return planRecords.compactMap { record in
            Self.plan(
                record,
                segments: segmentRecords.filter { $0.workoutPlanID == record.id },
                movements: movementRecords,
                decoder: decoder
            )
        }.sorted { $0.scheduledAt > $1.scheduledAt }
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        guard !plan.segments.isEmpty, plan.segments.allSatisfy(\.hasValidStructure) else {
            throw WorkoutValidationError.invalidSegment
        }
        let stimulusData = try encoder.encode(plan.intendedStimulus)
        let ambiguitiesData = try encoder.encode(plan.ambiguities)
        let now = Date.now
        let planRecords = try context.fetch(FetchDescriptor<WorkoutPlanRecord>())
        if let record = planRecords.first(where: { $0.id == plan.id }) {
            record.title = plan.title
            record.rawText = plan.rawText
            record.parsedAt = plan.parsedAt
            record.scheduledAt = plan.scheduledAt
            record.status = plan.status.rawValue
            record.format = plan.format.rawValue
            record.intendedStimulusData = stimulusData
            record.timeCapSeconds = plan.timeCapSeconds
            record.parserVersion = plan.parserVersion
            record.modelVersion = plan.modelVersion
            record.confidence = plan.confidence
            record.ambiguitiesData = ambiguitiesData
            record.updatedAt = now
        } else {
            context.insert(
                WorkoutPlanRecord(
                    plan: plan,
                    stimulusData: stimulusData,
                    ambiguitiesData: ambiguitiesData,
                    updatedAt: now
                )
            )
        }

        let segmentRecords = try context.fetch(FetchDescriptor<WorkoutSegmentRecord>())
        let movementRecords = try context.fetch(FetchDescriptor<MovementPrescriptionRecord>())
        let oldSegments = segmentRecords.filter { $0.workoutPlanID == plan.id }
        let oldSegmentIDs = Set(oldSegments.map(\.id))
        let newSegmentIDs = Set(plan.segments.map(\.id))
        let newMovementIDs = Set(plan.movements.map(\.id))
        for record in movementRecords
        where oldSegmentIDs.contains(record.segmentID) && !newMovementIDs.contains(record.id) {
            context.delete(record)
        }
        for record in oldSegments where !newSegmentIDs.contains(record.id) {
            context.delete(record)
        }

        for segment in plan.segments {
            if let record = segmentRecords.first(where: { $0.id == segment.id }) {
                Self.update(record, from: segment, workoutPlanID: plan.id)
            } else {
                context.insert(WorkoutSegmentRecord(segment: segment, workoutPlanID: plan.id))
            }
            for movement in segment.movements {
                if let record = movementRecords.first(where: { $0.id == movement.id }) {
                    Self.update(record, from: movement, segmentID: segment.id)
                } else {
                    context.insert(
                        MovementPrescriptionRecord(movement: movement, segmentID: segment.id)
                    )
                }
            }
        }
        try context.save()
    }

    func deletePlan(id: String) async throws {
        let segments = try context.fetch(FetchDescriptor<WorkoutSegmentRecord>())
            .filter { $0.workoutPlanID == id }
        let segmentIDs = Set(segments.map(\.id))
        for movement in try context.fetch(FetchDescriptor<MovementPrescriptionRecord>())
        where segmentIDs.contains(movement.segmentID) {
            context.delete(movement)
        }
        for segment in segments { context.delete(segment) }
        if let plan = try context.fetch(FetchDescriptor<WorkoutPlanRecord>())
            .first(where: { $0.id == id })
        {
            context.delete(plan)
        }
        try context.save()
    }

    func completedWorkouts() async throws -> [CompletedWorkout] {
        let workouts = try context.fetch(FetchDescriptor<CompletedWorkoutRecord>())
        let movements = try context.fetch(FetchDescriptor<CompletedMovementRecord>())
        return workouts.map { record in
            CompletedWorkout(
                id: record.id,
                plannedWorkoutID: record.plannedWorkoutID,
                title: record.title,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                sessionRPE: record.sessionRPE,
                postSessionPain: record.postSessionPain,
                notes: record.notes,
                movements: movements.filter { $0.workoutRecordID == record.id }.map(Self.movement)
            )
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func saveCompletedWorkout(_ workout: CompletedWorkout) async throws {
        let workoutRecords = try context.fetch(FetchDescriptor<CompletedWorkoutRecord>())
        if let record = workoutRecords.first(where: { $0.id == workout.id }) {
            record.plannedWorkoutID = workout.plannedWorkoutID
            record.title = workout.title
            record.startedAt = workout.startedAt
            record.endedAt = workout.endedAt
            record.sessionRPE = workout.sessionRPE
            record.postSessionPain = workout.postSessionPain
            record.notes = workout.notes
        } else {
            context.insert(CompletedWorkoutRecord(workout: workout))
        }

        let movementRecords = try context.fetch(FetchDescriptor<CompletedMovementRecord>())
        let existing = movementRecords.filter { $0.workoutRecordID == workout.id }
        let newIDs = Set(workout.movements.map(\.id))
        for record in existing where !newIDs.contains(record.id) { context.delete(record) }
        for movement in workout.movements {
            if let record = movementRecords.first(where: { $0.id == movement.id }) {
                Self.update(record, from: movement, workoutRecordID: workout.id)
            } else {
                context.insert(
                    CompletedMovementRecord(movement: movement, workoutRecordID: workout.id)
                )
            }
        }
        if let planID = workout.plannedWorkoutID,
            let plan = try context.fetch(FetchDescriptor<WorkoutPlanRecord>())
                .first(where: { $0.id == planID })
        {
            plan.status = WorkoutPlanStatus.completed.rawValue
            plan.updatedAt = .now
        }
        try context.save()
    }

    func deleteCompletedWorkout(id: String) async throws {
        for movement in try context.fetch(FetchDescriptor<CompletedMovementRecord>())
        where movement.workoutRecordID == id {
            context.delete(movement)
        }
        let records = try context.fetch(FetchDescriptor<CompletedWorkoutRecord>())
        guard let workout = records.first(where: { $0.id == id }) else {
            try context.save()
            return
        }
        let linkedPlanID = workout.plannedWorkoutID
        context.delete(workout)
        if let linkedPlanID,
            !records.contains(where: { $0.id != id && $0.plannedWorkoutID == linkedPlanID }),
            let plan = try context.fetch(FetchDescriptor<WorkoutPlanRecord>())
                .first(where: { $0.id == linkedPlanID })
        {
            plan.status = WorkoutPlanStatus.planned.rawValue
            plan.updatedAt = .now
        }
        try context.save()
    }

    private static func plan(
        _ record: WorkoutPlanRecord,
        segments: [WorkoutSegmentRecord],
        movements: [MovementPrescriptionRecord],
        decoder: JSONDecoder
    ) -> WorkoutPlan? {
        guard let status = WorkoutPlanStatus(rawValue: record.status),
            let format = WorkoutFormat(rawValue: record.format),
            let stimulus = try? decoder.decode(
                WorkoutStimulus.self,
                from: record.intendedStimulusData
            ),
            let ambiguities = try? decoder.decode(
                [WorkoutAmbiguity].self,
                from: record.ambiguitiesData
            )
        else { return nil }
        return WorkoutPlan(
            id: record.id,
            title: record.title,
            rawText: record.rawText,
            parsedAt: record.parsedAt,
            scheduledAt: record.scheduledAt,
            status: status,
            format: format,
            intendedStimulus: stimulus,
            timeCapSeconds: record.timeCapSeconds,
            parserVersion: record.parserVersion,
            modelVersion: record.modelVersion,
            confidence: record.confidence,
            ambiguities: ambiguities,
            segments: segments.compactMap { segment in
                guard let type = WorkoutSegmentType(rawValue: segment.type) else { return nil }
                return WorkoutSegment(
                    id: segment.id,
                    sequence: segment.sequence,
                    type: type,
                    rounds: segment.rounds,
                    durationSeconds: segment.durationSeconds,
                    restSeconds: segment.restSeconds,
                    notes: segment.notes,
                    movements: movements.filter { $0.segmentID == segment.id }
                        .map(Self.movement)
                )
            }.sorted { $0.sequence < $1.sequence }
        )
    }

    private static func movement(_ record: MovementPrescriptionRecord) -> MovementPrescription {
        MovementPrescription(
            id: record.id,
            canonicalMovementID: record.canonicalMovementID,
            displayName: record.displayName,
            originalText: record.originalText,
            repetitions: record.repetitions,
            distanceMeters: record.distanceMeters,
            calories: record.calories,
            loadValue: record.loadValue,
            loadUnit: record.loadUnit,
            percentageOfOneRepMax: record.percentageOfOneRepMax,
            durationSeconds: record.durationSeconds,
            tempo: record.tempo,
            notes: record.notes
        )
    }

    private static func movement(_ record: CompletedMovementRecord) -> CompletedMovement {
        CompletedMovement(
            id: record.id,
            canonicalMovementID: record.canonicalMovementID,
            plannedPrescriptionID: record.plannedPrescriptionID,
            displayName: record.displayName,
            actualRepetitions: record.actualRepetitions,
            actualDistanceMeters: record.actualDistanceMeters,
            actualCalories: record.actualCalories,
            actualLoadValue: record.actualLoadValue,
            actualLoadUnit: record.actualLoadUnit,
            actualDurationSeconds: record.actualDurationSeconds,
            modification: record.modification,
            painDuring: record.painDuring,
            notes: record.notes
        )
    }

    private static func update(
        _ record: WorkoutSegmentRecord,
        from segment: WorkoutSegment,
        workoutPlanID: String
    ) {
        record.workoutPlanID = workoutPlanID
        record.sequence = segment.sequence
        record.type = segment.type.rawValue
        record.rounds = segment.rounds
        record.durationSeconds = segment.durationSeconds
        record.restSeconds = segment.restSeconds
        record.notes = segment.notes
    }

    private static func update(
        _ record: MovementPrescriptionRecord,
        from movement: MovementPrescription,
        segmentID: String
    ) {
        record.segmentID = segmentID
        record.canonicalMovementID = movement.canonicalMovementID
        record.displayName = movement.displayName
        record.originalText = movement.originalText
        record.repetitions = movement.repetitions
        record.distanceMeters = movement.distanceMeters
        record.calories = movement.calories
        record.loadValue = movement.loadValue
        record.loadUnit = movement.loadUnit
        record.percentageOfOneRepMax = movement.percentageOfOneRepMax
        record.durationSeconds = movement.durationSeconds
        record.tempo = movement.tempo
        record.notes = movement.notes
    }

    private static func update(
        _ record: CompletedMovementRecord,
        from movement: CompletedMovement,
        workoutRecordID: String
    ) {
        record.workoutRecordID = workoutRecordID
        record.canonicalMovementID = movement.canonicalMovementID
        record.plannedPrescriptionID = movement.plannedPrescriptionID
        record.displayName = movement.displayName
        record.actualRepetitions = movement.actualRepetitions
        record.actualDistanceMeters = movement.actualDistanceMeters
        record.actualCalories = movement.actualCalories
        record.actualLoadValue = movement.actualLoadValue
        record.actualLoadUnit = movement.actualLoadUnit
        record.actualDurationSeconds = movement.actualDurationSeconds
        record.modification = movement.modification
        record.painDuring = movement.painDuring
        record.notes = movement.notes
    }
}
