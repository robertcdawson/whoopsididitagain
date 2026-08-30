import SwiftData
import XCTest

@testable import WhoopsApp

final class WorkoutMilestoneTests: XCTestCase {
    private let scoredWorkout =
        "AMRAP 8 minutes\n4 Burpees\n12 Overhead Kettlebell Swings (35#)\nScore: 5 rounds, 3 reps"

    func testDecimalQuantityInputPreservesPartialAndLocalizedValues() {
        let english = Locale(identifier: "en_US")
        for text in ["", ".", "0.", "12.", "12.5", "0.25", "1000.75"] {
            XCTAssertTrue(WorkoutDecimalInput.accepts(text, locale: english), text)
        }
        for text in ["-1", "nan", "inf", "1.2.3", "12 kg", "1,000"] {
            XCTAssertFalse(WorkoutDecimalInput.accepts(text, locale: english), text)
        }
        XCTAssertEqual(WorkoutDecimalInput.number("12.5", locale: english), 12.5)
        XCTAssertEqual(WorkoutDecimalInput.number("0", locale: english), 0)
        XCTAssertNil(WorkoutDecimalInput.number(".", locale: english))
        XCTAssertEqual(WorkoutDecimalInput.text(1_000.75, locale: english), "1000.75")
        let french = Locale(identifier: "fr_FR")
        XCTAssertTrue(WorkoutDecimalInput.accepts("12,", locale: french))
        XCTAssertEqual(WorkoutDecimalInput.number("12,5", locale: french), 12.5)
        XCTAssertEqual(WorkoutDecimalInput.text(12.5, locale: french), "12,5")
    }

    func testCompletedWorkoutTimingCanChangeDateEndAndDecimalDuration() async throws {
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        var workout = CompletedWorkout(plan: plan, now: Date(timeIntervalSince1970: 172_800))
        workout.setDuration(seconds: 3_645.6)
        let start = workout.startedAt
        XCTAssertEqual(workout.durationSeconds, 3_645.6, accuracy: 0.000_001)
        XCTAssertEqual(workout.endedAt, start.addingTimeInterval(3_645.6))

        // Move to just before midnight; elapsed duration crosses into the following day.
        workout.reschedule(startingAt: Date(timeIntervalSince1970: 259_170))
        XCTAssertEqual(workout.startedAt, Date(timeIntervalSince1970: 259_170))
        XCTAssertEqual(workout.durationSeconds, 3_645.6, accuracy: 0.000_001)
        workout.endedAt = workout.startedAt.addingTimeInterval(90.6)
        XCTAssertEqual(workout.durationSeconds, 90.6, accuracy: 0.000_001)
        XCTAssertEqual(
            WorkoutDurationInput.minutesText(
                seconds: workout.durationSeconds, locale: Locale(identifier: "en_US")), "1.51")
        let validEnd = workout.endedAt
        workout.setDuration(seconds: .nan)
        workout.setDuration(seconds: -.infinity)
        workout.setDuration(seconds: -1)
        XCTAssertEqual(workout.endedAt, validEnd)
        workout.endedAt = workout.startedAt
        XCTAssertNotNil(workout.validationMessage)
        workout.endedAt = workout.startedAt.addingTimeInterval(-60)
        XCTAssertNotNil(workout.validationMessage)
    }

    func testCompletedMovementDuplicateCopiesAllFieldsWithNewIdentity() async throws {
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        var original = CompletedWorkout(plan: plan).movements[0]
        original.actualDistanceMeters = 75
        original.actualCalories = 12
        original.actualLoadValue = 9.5
        original.actualLoadUnit = "kg"
        original.actualDurationSeconds = 61.2
        original.modification = "Synthetic modification"
        original.painDuring = 2
        original.notes = "Synthetic notes"
        var duplicate = original.duplicated()
        XCTAssertNotEqual(duplicate.id, original.id)
        duplicate.id = original.id
        XCTAssertEqual(duplicate, original)
    }

    func testStimulusEstimatesAcceptDecimalMinutesAndDecodeLegacyIntegers() throws {
        let legacy = Data(
            #"{"primary":"Synthetic","secondary":[],"estimatedDurationMinimumMinutes":5,"estimatedDurationMaximumMinutes":15}"#
                .utf8)
        var stimulus = try JSONDecoder().decode(WorkoutStimulus.self, from: legacy)
        XCTAssertEqual(stimulus.estimatedDurationMinimumMinutes, 5)
        XCTAssertTrue(stimulus.hasValidDurationRange)
        stimulus.estimatedDurationMinimumMinutes = 5.25
        stimulus.estimatedDurationMaximumMinutes = 15.75
        XCTAssertEqual(
            try JSONDecoder().decode(WorkoutStimulus.self, from: JSONEncoder().encode(stimulus)),
            stimulus)
        stimulus.estimatedDurationMinimumMinutes = .nan
        XCTAssertFalse(stimulus.hasValidDurationRange)
    }

    @MainActor
    func testCompletedWorkoutEditsRoundTripAllFieldsWithoutDuplicatesOrPlanChanges() async throws {
        let container = try workoutContainer()
        let repository = WorkoutPersistence(container: container)
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        plan.status = .planned
        try await repository.savePlan(plan)
        let original = CompletedWorkout(plan: plan, now: Date(timeIntervalSince1970: 100_000))
        try await repository.saveCompletedWorkout(original)
        let plansBefore = try await repository.plans()
        var edited = original
        edited.title = "Corrected synthetic workout"
        edited.reschedule(startingAt: Date(timeIntervalSince1970: 50_000))
        edited.setDuration(seconds: 91.2)
        edited.sessionRPE = 8
        edited.postSessionPain = 3
        edited.notes = "First note\nSecond note"
        edited.reportedResult = .init(completedRounds: 6, additionalRepetitions: 1)
        edited.movements[0].canonicalMovementID = "row"
        edited.movements[0].displayName = "Corrected row"
        edited.movements[0].actualRepetitions = 0
        edited.movements[0].actualDistanceMeters = 1_250
        edited.movements[0].actualCalories = 42
        edited.movements[0].actualLoadValue = 12.5
        edited.movements[0].actualLoadUnit = "kg"
        edited.movements[0].actualDurationSeconds = 90.6
        edited.movements[0].modification = "Changed movement"
        edited.movements[0].painDuring = 4
        edited.movements[0].notes = "Movement-specific context"
        var duplicate = edited.movements[0].duplicated()
        duplicate.displayName = "Another row"
        edited.movements = [duplicate, edited.movements[0]]
        try await repository.saveCompletedWorkout(edited)
        try await repository.saveCompletedWorkout(edited)
        let reopened = WorkoutPersistence(container: container)
        let workouts = try await reopened.completedWorkouts()
        XCTAssertEqual(workouts, [edited])
        XCTAssertEqual(workouts.first?.id, original.id)
        XCTAssertEqual(workouts.first?.plannedWorkoutID, original.plannedWorkoutID)
        let plansAfter = try await reopened.plans()
        XCTAssertEqual(plansAfter, plansBefore)
        let rows = try ModelContext(container).fetch(FetchDescriptor<CompletedMovementRecord>())
        XCTAssertEqual(Set(rows.map(\.id)), Set(edited.movements.map(\.id)))

        // Optional results can be cleared; no plan-derived values may be filled back in on edit.
        edited.reportedResult = nil
        edited.notes = ""
        edited.movements[0].canonicalMovementID = nil
        edited.movements[0].actualRepetitions = nil
        edited.movements[0].actualDistanceMeters = nil
        edited.movements[0].actualCalories = nil
        edited.movements[0].actualLoadValue = nil
        edited.movements[0].actualLoadUnit = nil
        edited.movements[0].actualDurationSeconds = nil
        edited.movements[0].modification = ""
        edited.movements[0].notes = ""
        try await reopened.saveCompletedWorkout(edited)
        let cleared = try await WorkoutPersistence(container: container).completedWorkouts()
        XCTAssertEqual(cleared, [edited])
    }

    @MainActor
    func testInvalidCompletedWorkoutEditsLeaveStoredWorkoutUnchanged() async throws {
        let container = try workoutContainer()
        let repository = WorkoutPersistence(container: container)
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let original = CompletedWorkout(plan: plan)
        try await repository.saveCompletedWorkout(original)
        let invalidEdits: [(inout CompletedWorkout) -> Void] = [
            { $0.title = "  " },
            { $0.endedAt = $0.startedAt.addingTimeInterval(-1) },
            { $0.startedAt = Date(timeIntervalSince1970: .infinity) },
            { $0.sessionRPE = 0 }, { $0.sessionRPE = 11 },
            { $0.postSessionPain = -1 }, { $0.postSessionPain = 11 },
            { $0.reportedResult?.additionalRepetitions = -1 },
            { $0.movements[0].displayName = "" },
            { $0.movements[0].actualLoadValue = .nan },
            { $0.movements[0].actualDurationSeconds = .infinity },
            { $0.movements[0].actualRepetitions = -1 },
            { $0.movements[0].painDuring = 11 },
            { $0.movements.append($0.movements[0]) },
        ]
        for change in invalidEdits {
            var edited = original
            change(&edited)
            XCTAssertNotNil(edited.validationMessage)
            do {
                try await repository.saveCompletedWorkout(edited)
                XCTFail("Invalid completion must not be saved")
            } catch { XCTAssertTrue(error is WorkoutValidationError) }
            let saved = try await WorkoutPersistence(container: container).completedWorkouts()
            XCTAssertEqual(saved, [original])
        }
    }

    @MainActor
    func testCompletedMovementCannotBeMovedToAnotherWorkoutByReusingItsID() async throws {
        let container = try workoutContainer()
        let repository = WorkoutPersistence(container: container)
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let original = CompletedWorkout(plan: plan)
        try await repository.saveCompletedWorkout(original)
        var other = CompletedWorkout(plan: plan)
        other.movements = original.movements
        do {
            try await repository.saveCompletedWorkout(other)
            XCTFail("The source workout's results must not be reassigned")
        } catch { XCTAssertTrue(error is WorkoutValidationError) }
        let saved = try await WorkoutPersistence(container: container).completedWorkouts()
        XCTAssertEqual(saved, [original])
    }

    @MainActor
    func testPlannedDateStimulusEstimatesAndOrderRemainEditable() async throws {
        let container = try workoutContainer()
        let repository = WorkoutPersistence(container: container)
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        try await repository.savePlan(plan)
        plan.scheduledAt = Date(timeIntervalSince1970: 42_000)
        plan.title = "Edited plan"
        plan.format = .rounds
        plan.timeCapSeconds = 91.2
        plan.intendedStimulus = .init(
            primary: "Edited stimulus", secondary: ["Edited target"],
            estimatedDurationMinimumMinutes: 5, estimatedDurationMaximumMinutes: 15)
        plan.segments[0].movements.swapAt(0, 1)
        try await repository.savePlan(plan)
        let saved = try await WorkoutPersistence(container: container).plans()
        XCTAssertEqual(saved, [plan])
        plan.intendedStimulus.estimatedDurationMaximumMinutes = 4
        XCTAssertFalse(plan.intendedStimulus.hasValidDurationRange)
        do {
            try await repository.savePlan(plan)
            XCTFail("Inverted estimate ranges must not save")
        } catch { XCTAssertEqual(error as? WorkoutValidationError, .invalidMovement) }
        let unchanged = try await WorkoutPersistence(container: container).plans()
        XCTAssertEqual(unchanged, saved)
    }

    @MainActor
    private func workoutContainer() throws -> ModelContainer {
        try ModelContainer(
            for: WorkoutPlanRecord.self, WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self, CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testReportedTotalCorrectionsStaySeparateFromScoreAndPrescription() async throws {
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let firstID = plan.movements[0].id
        let secondID = plan.movements[1].id
        plan.reportedRepetitionOverrides[firstID] = 19
        XCTAssertEqual(plan.reportedRepetitionTotals?[firstID], 23)
        XCTAssertEqual(plan.effectiveReportedRepetitionTotals[firstID], 19)
        XCTAssertEqual(plan.effectiveReportedRepetitionTotals[secondID], 60)
        XCTAssertEqual(plan.movements.map(\.repetitions), [4, 12])
        XCTAssertEqual(plan.reportedResult, .init(completedRounds: 5, additionalRepetitions: 3))
        XCTAssertTrue(plan.hasValidReportedRepetitionOverrides)
        plan.reportedResult?.completedRounds = 6
        XCTAssertEqual(plan.reportedRepetitionTotals?[firstID], 27)
        XCTAssertEqual(CompletedWorkout(plan: plan).movements.map(\.actualRepetitions), [19, 72])
        plan.reportedRepetitionOverrides[firstID] = 0
        XCTAssertEqual(CompletedWorkout(plan: plan).movements[0].actualRepetitions, 0)
        plan.reportedRepetitionOverrides[firstID] = nil
        XCTAssertEqual(plan.effectiveReportedRepetitionTotals[firstID], 27)
        XCTAssertEqual(CompletedWorkout(plan: plan).movements[0].actualRepetitions, 27)
    }

    func testManualReportedTotalsWorkWithoutAnInferableScore() async throws {
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let firstID = plan.movements[0].id
        plan.reportedRepetitionOverrides[firstID] = 18
        plan.reportedResult?.additionalRepetitions = 99
        XCTAssertNil(plan.reportedRepetitionTotals)
        XCTAssertEqual(CompletedWorkout(plan: plan).movements.map(\.actualRepetitions), [18, nil])
        plan.reportedResult = nil
        XCTAssertEqual(CompletedWorkout(plan: plan).movements.map(\.actualRepetitions), [18, nil])
        plan.reportedRepetitionOverrides[firstID] = nil
        XCTAssertEqual(CompletedWorkout(plan: plan).movements.map(\.actualRepetitions), [4, 12])
    }

    func testReportedTotalCorrectionsAreValidatedAndStayWithMovementIdentity() async throws {
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let source = plan.movements[0]
        for invalid in [-1, 100_001, Int.max] {
            plan.reportedRepetitionOverrides[source.id] = invalid
            XCTAssertFalse(plan.hasValidReportedRepetitionOverrides)
            XCTAssertEqual(plan.effectiveReportedRepetitionTotals[source.id], 23)
        }
        plan.reportedRepetitionOverrides[source.id] = 19
        let duplicate = source.duplicated()
        plan.segments[0].movements.insert(duplicate, at: 1)
        XCTAssertNil(plan.reportedRepetitionOverrides[duplicate.id])
        XCTAssertEqual(plan.effectiveReportedRepetitionTotals[duplicate.id], 20)
        plan.segments[0].movements.swapAt(0, 2)
        XCTAssertEqual(plan.effectiveReportedRepetitionTotals[source.id], 19)
        plan.segments[0].movements.removeAll { $0.id == source.id }
        plan.discardOrphanedReportedRepetitionOverrides()
        XCTAssertTrue(plan.reportedRepetitionOverrides.isEmpty)
        XCTAssertTrue(plan.hasValidReportedRepetitionOverrides)
    }

    @MainActor
    func testReportedTotalCorrectionsPersistUpdateAndResetWithoutChangingCompletion() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self, WorkoutSegmentRecord.self, MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self, CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = WorkoutPersistence(container: container)
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let id = plan.movements[0].id
        plan.reportedRepetitionOverrides[id] = 19
        try await repository.savePlan(plan)
        let initial = try await repository.plans()
        XCTAssertEqual(initial.first, plan)
        let completed = CompletedWorkout(plan: try XCTUnwrap(initial.first))
        try await repository.saveCompletedWorkout(completed)
        plan.reportedRepetitionOverrides[id] = 0
        try await repository.savePlan(plan)
        let edited = try await repository.plans()
        XCTAssertEqual(edited.first?.effectiveReportedRepetitionTotals[id], 0)
        plan.reportedRepetitionOverrides[id] = nil
        try await repository.savePlan(plan)
        let reset = try await repository.plans()
        XCTAssertEqual(reset.first?.reportedRepetitionOverrides, [:])
        XCTAssertEqual(reset.first?.effectiveReportedRepetitionTotals[id], 23)
        let savedCompletions = try await repository.completedWorkouts()
        XCTAssertEqual(savedCompletions.first?.movements[0].actualRepetitions, 19)
        XCTAssertEqual(savedCompletions.first?.reportedResult, completed.reportedResult)
        plan.reportedRepetitionOverrides[id] = -1
        do {
            try await repository.savePlan(plan)
            XCTFail("Negative reported totals must not be saved")
        } catch {
            XCTAssertEqual(error as? WorkoutValidationError, .invalidMovement)
        }
        let unchanged = try await repository.plans()
        XCTAssertEqual(unchanged.first?.reportedRepetitionOverrides, [:])
    }

    func testReportedScorePopulatesTotalsWithoutChangingPrescription() async throws {
        let parsed = try await VersionedWorkoutParser().parse(rawText: scoredWorkout)
        let plan = WorkoutPlan(parsed: parsed)
        XCTAssertEqual(plan.reportedResult, .init(completedRounds: 5, additionalRepetitions: 3))
        XCTAssertNil(plan.segments[0].rounds)
        XCTAssertEqual(plan.movements.map(\.repetitions), [4, 12])
        XCTAssertEqual(plan.movements.map { plan.reportedRepetitionTotals?[$0.id] }, [23, 60])
        XCTAssertEqual(CompletedWorkout(plan: plan).movements.map(\.actualRepetitions), [23, 60])
        XCTAssertEqual(plan.status, .draft)
        XCTAssertFalse(plan.visibleNotes(plan.segments[0].notes).contains("Score:"))
    }

    func testPartialRoundFollowsMovementOrderAndRejectsAmbiguousTotals() async throws {
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        plan.reportedResult?.additionalRepetitions = 6
        XCTAssertEqual(plan.movements.map { plan.reportedRepetitionTotals?[$0.id] }, [24, 62])
        plan.reportedResult?.additionalRepetitions = 16
        XCTAssertNil(plan.reportedRepetitionTotals)
        XCTAssertTrue(
            CompletedWorkout(plan: plan).movements.allSatisfy { $0.actualRepetitions == nil })
        plan.reportedResult?.additionalRepetitions = 0
        plan.segments[0].movements[0].distanceMeters = 200
        XCTAssertNil(plan.reportedRepetitionTotals)
        XCTAssertNil(CompletedWorkout(plan: plan).movements[0].actualDistanceMeters)
        plan.segments[0].movements[0].distanceMeters = nil
        plan.segments.append(plan.segments[0])
        XCTAssertNil(plan.reportedRepetitionTotals)
    }

    func testReportedScoreParsingIsConservativeAndSupportsZero() {
        XCTAssertEqual(
            WorkoutReportedResult.parse("Score: 0 rounds and 3 reps"),
            .init(completedRounds: 0, additionalRepetitions: 3))
        XCTAssertEqual(
            WorkoutReportedResult.parse("Result: 4 rounds"),
            .init(completedRounds: 4, additionalRepetitions: 0))
        for source in [
            "5 rounds", "Score: 3-5 rounds", "Score: -5 rounds", "Score: 5.5 rounds",
            "Score: 5 rounds\nScore: 6 rounds", "Score: 2 rounds, 99999999999999999999999 reps",
        ] {
            XCTAssertNil(WorkoutReportedResult.parse(source), source)
        }
    }

    func testDecimalMinutesRoundTripAndLocaleWithoutIntegerRounding() async throws {
        let us = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        XCTAssertEqual(WorkoutDurationInput.seconds("6.25", locale: us), 375)
        XCTAssertEqual(WorkoutDurationInput.seconds("0.01", locale: us), 0.6)
        XCTAssertEqual(WorkoutDurationInput.seconds("1,25", locale: de), 75)
        XCTAssertEqual(WorkoutDurationInput.minutesText(seconds: 375, locale: us), "6.25")
        XCTAssertEqual(WorkoutDurationInput.minutesText(seconds: 0.6, locale: us), "0.01")
        XCTAssertEqual(WorkoutDurationInput.minutesText(seconds: 75, locale: de), "1,25")
        XCTAssertTrue(WorkoutDurationInput.accepts("1.", locale: us))
        for invalid in ["1.234", "-1", "nan", "1e2", "1..2"] {
            XCTAssertFalse(WorkoutDurationInput.accepts(invalid, locale: us))
        }
        XCTAssertNil(WorkoutDurationInput.seconds("1441", locale: us))
        let parsed = try await VersionedWorkoutParser().parse(
            rawText: "AMRAP 6.25 minutes\nPlank for 0.01 minutes")
        XCTAssertEqual(parsed.timeCapSeconds, 375)
        XCTAssertEqual(parsed.segments[0].movements[0].durationSeconds, 0.6)
    }

    func testDuplicatedMovementHasIndependentIdentityAndAllPrescriptionFields() async throws {
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        let source = plan.movements[1]
        var copy = source.duplicated()
        XCTAssertNotEqual(copy.id, source.id)
        let newID = copy.id
        copy.id = source.id
        XCTAssertEqual(copy, source)
        copy.id = newID
        copy.repetitions = 9
        copy.loadValue = 20
        copy.loadUnit = "kg"
        XCTAssertEqual(source.repetitions, 12)
        XCTAssertEqual(source.loadValue, 35)
        XCTAssertEqual(source.loadUnit, "lb")
        XCTAssertEqual(copy.canonicalMovementID, source.canonicalMovementID)
    }

    func testLoadPickerUsesOnlyPoundsAndKilogramsAndNormalizesAliases() {
        XCTAssertEqual(WorkoutLoadUnit.allCases.map(\.displayName), ["lbs", "kg"])
        XCTAssertEqual(WorkoutLoadUnit.normalized("lbs")?.rawValue, "lb")
        XCTAssertEqual(WorkoutLoadUnit.normalized("KG")?.rawValue, "kg")
        XCTAssertNil(WorkoutLoadUnit.normalized("oz"))
    }

    @MainActor
    func testPreciseDurationsScoreAndDuplicateOrderPersistIndependently() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self, WorkoutSegmentRecord.self, MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self, CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = WorkoutPersistence(container: container)
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        plan.timeCapSeconds = 375
        plan.segments[0].durationSeconds = 375
        plan.segments[0].restSeconds = 0.6
        var duplicate = plan.movements[0].duplicated()
        duplicate.loadUnit = "kg"
        duplicate.loadValue = 20
        duplicate.durationSeconds = 0.6
        plan.segments[0].movements.insert(duplicate, at: 1)
        try await repository.savePlan(plan)
        let stored = try await repository.plans()
        let reloaded = try XCTUnwrap(stored.first)
        XCTAssertEqual(reloaded, plan)
        var actual = CompletedWorkout(plan: reloaded)
        actual.movements[1].actualDurationSeconds = 0.6
        try await repository.saveCompletedWorkout(actual)
        let completed = try await repository.completedWorkouts()
        XCTAssertEqual(completed.first, actual)
        plan.reportedResult = nil
        plan.segments[0].movements.remove(at: 1)
        try await repository.savePlan(plan)
        let afterDelete = try await repository.plans()
        XCTAssertNil(
            afterDelete.first?.reportedResult,
            "Clearing a saved result must not reparse stale raw text")
        XCTAssertEqual(afterDelete.first?.movements.map(\.id), plan.movements.map(\.id))
        XCTAssertEqual(afterDelete.first?.movements.last?.loadUnit, "lb")
    }

    @MainActor
    func testLegacyWholeSecondRecordsRemainReadable() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self, WorkoutSegmentRecord.self, MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self, CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = WorkoutPersistence(container: container)
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(rawText: scoredWorkout))
        try await repository.savePlan(plan)
        let context = ModelContext(container)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutPlanRecord>()).first)
        record.preciseTimeCapSeconds = nil
        record.reportedResultData = nil
        record.reportedRepetitionOverridesData = nil
        let segment = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSegmentRecord>()).first)
        segment.preciseDurationSeconds = nil
        segment.restSeconds = 1
        segment.preciseRestSeconds = nil
        try context.save()
        let legacy = try await WorkoutPersistence(container: container).plans()
        XCTAssertEqual(legacy.first?.timeCapSeconds, 480)
        XCTAssertEqual(legacy.first?.segments[0].durationSeconds, 480)
        XCTAssertEqual(legacy.first?.segments[0].restSeconds, 1)
        XCTAssertNil(legacy.first?.reportedResult, "Legacy notes are not silently reinterpreted")
        XCTAssertEqual(legacy.first?.reportedRepetitionOverrides, [:])
        XCTAssertEqual(legacy.first?.segments[0].notes, plan.segments[0].notes)
    }

    func testRowPressLadderParsesWithoutInventingValues() async throws {
        let raw = """
            Complete for time

            1500 m Row
            21 Strict Press 95 lb
            1000 m Row
            15 Strict Press 115 lb
            500 m Row
            9 Strict Press 135 lb
            250 m Row
            """

        let result = try await VersionedWorkoutParser().parse(rawText: raw)

        XCTAssertEqual(result.format, .forTime)
        XCTAssertEqual(result.segments.first?.movements.count, 7)
        XCTAssertEqual(result.segments.first?.movements[0].distanceMeters, 1_500)
        XCTAssertEqual(result.segments.first?.movements[1].canonicalMovementID, "strict_press")
        XCTAssertEqual(result.segments.first?.movements[1].repetitions, 21)
        XCTAssertEqual(result.segments.first?.movements[1].loadValue, 95)
        XCTAssertEqual(result.segments.first?.movements[1].loadUnit, "lb")
        XCTAssertTrue(result.ambiguities.isEmpty)
    }

    func testAMRAPAliasesAndDurationParse() async throws {
        let result = try await VersionedWorkoutParser().parse(
            rawText: """
                12 minute AMRAP
                10 Pull-ups
                15 Wall balls 20 lb
                200 m Run
                """
        )

        XCTAssertEqual(result.format, .amrap)
        XCTAssertEqual(result.timeCapSeconds, 720)
        XCTAssertEqual(
            result.segments.first?.movements.compactMap(\.canonicalMovementID),
            ["pull_up", "wall_ball", "run"]
        )
        XCTAssertTrue(result.ambiguities.isEmpty)
    }

    func testSpelledOutAMRAPPreservesBulletQuantitiesAndSeparatesScore() async throws {
        // Synthetic example: exercises the reported syntax without storing personal results.
        let raw = """
            Complete as many rounds as possible in 8 minutes

            •4 Burpees
            •12 Overhead Kettlebell Swings (35#)

            Score: 5 rounds, 3 reps
            """
        let result = try await VersionedWorkoutParser().parse(rawText: raw)
        let segment = try XCTUnwrap(result.segments.first)

        XCTAssertEqual(result.format, .amrap)
        XCTAssertEqual(result.timeCapSeconds, 480)
        XCTAssertEqual(segment.durationSeconds, 480)
        XCTAssertNil(segment.rounds)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(segment.movements.count, 2)
        XCTAssertEqual(
            segment.movements.map(\.canonicalMovementID), ["burpee", "overhead_kettlebell_swing"])
        XCTAssertEqual(segment.movements.map(\.repetitions), [4, 12])
        XCTAssertEqual(segment.movements.last?.loadValue, 35)
        XCTAssertEqual(segment.movements.last?.loadUnit, "lb")
        XCTAssertEqual(
            segment.notes, "Reported result (not a prescription): Score: 5 rounds, 3 reps")
        XCTAssertFalse(result.intendedStimulus.secondary.contains { $0.contains("Score:") })
        XCTAssertTrue(result.ambiguities.isEmpty)
        XCTAssertEqual(result.rawText, raw)
        XCTAssertEqual(result.parserVersion, "deterministic-1.5.0")
        XCTAssertNil(result.modelVersion)
    }

    func testBulletPrefixesDoNotHideRepetitionCounts() async throws {
        for prefix in ["•", "• ", "- ", "* ", "– ", "▪", "◦ "] {
            let result = try await VersionedWorkoutParser().parse(rawText: "\(prefix)8 Burpees")
            XCTAssertEqual(result.segments.first?.movements.first?.repetitions, 8, prefix)
            XCTAssertTrue(result.ambiguities.isEmpty, prefix)
        }
    }

    func testTimeCapRemainsMetadataAndSupportsClockNotation() async throws {
        for (text, cap) in [("12 minutes", 720), ("7:30", 450)] {
            let result = try await VersionedWorkoutParser().parse(
                rawText: "For time\n400 m Row\n6 Strict Press 30 lb\nTime cap: \(text)")
            XCTAssertEqual(result.timeCapSeconds, Double(cap))
            XCTAssertEqual(result.segments.first?.movements.count, 2)
            XCTAssertNil(result.segments.first?.durationSeconds)
            XCTAssertTrue(result.ambiguities.isEmpty)
        }
        let amrap = try await VersionedWorkoutParser().parse(rawText: "AMRAP 7:30\n8 Burpees")
        XCTAssertEqual(amrap.timeCapSeconds, 450)
        XCTAssertEqual(amrap.segments.first?.movements.count, 1)
        XCTAssertTrue(amrap.ambiguities.isEmpty)
        let missing = try await VersionedWorkoutParser().parse(rawText: "AMRAP\nRow for 45 seconds")
        XCTAssertNil(missing.timeCapSeconds, "A movement duration is not a workout time limit")
    }

    func testStrengthSetsAreStructureNotMovements() async throws {
        let result = try await VersionedWorkoutParser().parse(
            rawText: "Strength\n4 sets\n5 Deadlift at 70% 1RM")
        XCTAssertEqual(result.format, .strength)
        XCTAssertEqual(result.segments.first?.rounds, 4)
        XCTAssertEqual(result.segments.first?.movements.count, 1)
        XCTAssertEqual(result.segments.first?.movements.first?.repetitions, 5)
        XCTAssertEqual(result.segments.first?.movements.first?.percentageOfOneRepMax, 70)
        XCTAssertTrue(result.ambiguities.isEmpty)
    }

    func testRestBetweenDifferentMovementsAndTrailingRestRemainExplicit() async throws {
        let different = try await VersionedWorkoutParser().parse(
            rawText: "For time\n400 m Row\nRest 1:30\n10 Burpees")
        XCTAssertEqual(different.segments.map(\.type), [.work, .rest, .work])
        XCTAssertEqual(different.segments[1].durationSeconds, 90)
        XCTAssertTrue(different.segments[1].movements.isEmpty)
        let trailing = try await VersionedWorkoutParser().parse(
            rawText: "400 m Row\nRest 30 seconds\n400 m Row\nRest 30 seconds")
        XCTAssertEqual(trailing.segments.map(\.type), [.work, .rest, .work, .rest])
    }

    func testUnknownMovementRetainsExplicitQuantitiesWithoutInventedMapping() async throws {
        let result = try await VersionedWorkoutParser().parse(rawText: "6 Moon hops at 20 kg")
        let movement = try XCTUnwrap(result.segments.first?.movements.first)
        XCTAssertNil(movement.canonicalMovementID)
        XCTAssertEqual(movement.repetitions, 6)
        XCTAssertEqual(movement.loadValue, 20)
        XCTAssertFalse(result.ambiguities.isEmpty)
    }

    func testPluralGobletSquatsUseAnExplicitCatalogAlias() async throws {
        let result = try await VersionedWorkoutParser().parse(rawText: "13 Goblet Squats at 24 kg")
        XCTAssertEqual(result.segments.first?.movements.first?.canonicalMovementID, "goblet_squat")
        XCTAssertTrue(result.ambiguities.isEmpty)
    }

    func testRangesAlternativesAndNegativeQuantitiesRequireReview() async throws {
        for raw in ["8-10 Burpees", "8–10 Burpees", "-8 Burpees"] {
            let result = try await VersionedWorkoutParser().parse(rawText: raw)
            XCTAssertNil(result.segments.first?.movements.first?.repetitions, raw)
            XCTAssertFalse(result.ambiguities.isEmpty, raw)
        }
        for load in ["30/20 kg", "20-30 kg", "-20 kg"] {
            let result = try await VersionedWorkoutParser().parse(rawText: "8 Strict Press \(load)")
            XCTAssertEqual(result.segments.first?.movements.first?.repetitions, 8)
            XCTAssertNil(result.segments.first?.movements.first?.loadValue, load)
            XCTAssertFalse(result.ambiguities.isEmpty, load)
        }
        let invalid = try await VersionedWorkoutParser().parse(rawText: "8 Burpees\nTime cap: 1:90")
        XCTAssertNil(invalid.timeCapSeconds)
        XCTAssertFalse(invalid.ambiguities.isEmpty)
        let huge = try await VersionedWorkoutParser().parse(
            rawText: "999999999999999999999999999999999999999 Burpees")
        XCTAssertNil(huge.segments.first?.movements.first?.repetitions)
        XCTAssertFalse(huge.ambiguities.isEmpty)
    }

    func testLoadUnitVariantsPreserveWeights() async throws {
        for (source, expectedUnit) in [
            ("(35#)", "lb"), ("35#", "lb"), ("35 #", "lb"),
            ("(35 lb)", "lb"), ("35 lbs", "lb"), ("(35kg)", "kg"), ("35 kgs", "kg"),
        ] {
            let result = try await VersionedWorkoutParser().parse(
                rawText: "8 Strict Press \(source)")
            let movement = try XCTUnwrap(result.segments.first?.movements.first)
            XCTAssertEqual(movement.loadValue, 35, source)
            XCTAssertEqual(movement.loadUnit, expectedUnit, source)
        }
    }

    func testResultMetadataCannotDefineWorkoutStructureOrBecomeMovements() async throws {
        let fixedRounds = try await VersionedWorkoutParser().parse(
            rawText: """
                3 rounds
                8 Burpees
                Result: 9 rounds, 4 reps
                """)
        XCTAssertEqual(fixedRounds.segments.first?.rounds, 3)
        XCTAssertEqual(fixedRounds.segments.first?.movements.count, 1)

        let noDuration = try await VersionedWorkoutParser().parse(
            rawText: """
                AMRAP
                8 Burpees
                Score: 9 rounds in 12 minutes
                """)
        XCTAssertNil(noDuration.timeCapSeconds)
        XCTAssertNil(noDuration.segments.first?.rounds)

        let manual = try await VersionedWorkoutParser().parse(
            rawText: """
                8 Burpees
                Completed: 4 rounds for time in 10 minutes
                """)
        XCTAssertEqual(manual.format, .manual)
        XCTAssertNil(manual.timeCapSeconds)
        XCTAssertNil(manual.segments.first?.rounds)
        XCTAssertEqual(manual.segments.first?.movements.count, 1)

        do {
            _ = try await VersionedWorkoutParser().parse(rawText: "Score: 9 rounds, 4 reps")
            XCTFail("A result alone is not a workout prescription")
        } catch {
            XCTAssertEqual(error as? WorkoutValidationError, .missingSegments)
        }
    }

    func testExplicitSwingAliasesDoNotAssumeGenericSwingsAreOverhead() async throws {
        for alias in ["Overhead KB Swings", "American Kettlebell Swing", "American KB Swings"] {
            let parsed = try await VersionedWorkoutParser().parse(rawText: "8 \(alias) 35 lb")
            XCTAssertEqual(
                parsed.segments.first?.movements.first?.canonicalMovementID,
                "overhead_kettlebell_swing")
        }
        for name in ["KB Swing", "Russian Kettlebell Swing"] {
            let parsed = try await VersionedWorkoutParser().parse(rawText: "8 \(name) 35 lb")
            XCTAssertNil(parsed.segments.first?.movements.first?.canonicalMovementID)
            XCTAssertFalse(parsed.ambiguities.isEmpty)
        }
    }

    func testOverheadSwingAndUnmappedMovementBothReachRestrictionReview() async throws {
        let restriction = RestrictionProfile(
            id: "synthetic-elbow", injuryName: "Test elbow", bodyRegion: "Arm", side: "Right",
            movementTag: "elbow extension", level: .avoid, painThreshold: 2,
            rationale: "Synthetic restriction", isActive: true
        )
        let swing = try await VersionedWorkoutParser().parse(rawText: "8 Overhead KB Swings 35 lb")
        let known = await DeterministicWorkoutScalingEngine().evaluate(
            plan: WorkoutPlan(parsed: swing), restrictions: [restriction]
        )
        XCTAssertEqual(known.recommendation, .modify)
        XCTAssertEqual(known.conflicts.first?.severity, .hard)

        let unknown = try await VersionedWorkoutParser().parse(rawText: "8 Mystery Movements")
        let unreviewed = await DeterministicWorkoutScalingEngine().evaluate(
            plan: WorkoutPlan(parsed: unknown), restrictions: [restriction]
        )
        XCTAssertEqual(unreviewed.recommendation, .proceedWithLimits)
        XCTAssertEqual(unreviewed.conflicts.first?.severity, .caution)
        XCTAssertTrue(
            unreviewed.conflicts.first?.explanation.contains("cannot be evaluated") == true)
        XCTAssertTrue(unreviewed.conflicts.first?.substitutionCandidates.isEmpty == true)
    }

    @MainActor
    func testReportedScorePersistsAsNotesWithoutCreatingCompletedWork() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self, WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self, CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = WorkoutPersistence(container: container)
        let parsed = try await VersionedWorkoutParser().parse(
            rawText: """
                8 minute AMRAP
                4 Burpees
                Score: 5 rounds, 3 reps
                """)
        var plan = WorkoutPlan(parsed: parsed)
        plan.status = .planned
        try await repository.savePlan(plan)
        let saved = try await repository.plans()
        let completed = try await repository.completedWorkouts()
        XCTAssertEqual(saved.first?.segments.first?.notes, parsed.segments.first?.notes)
        XCTAssertNil(saved.first?.segments.first?.rounds)
        XCTAssertTrue(completed.isEmpty)
    }

    func testStylizedEchoBikeIntervalsPreserveStructureAndTargets() async throws {
        let raw = """
            𝗘𝗰𝗵𝗼 𝗕𝗶𝗸𝗲 𝗜𝗻𝘁𝗲𝗿𝘃𝗮𝗹𝘀:
            60 Cal Echo Bike
            𝗥𝗲𝘀𝘁 𝟵𝟬 𝘀𝗲𝗰
            52 Cal Echo Bike
            𝗥𝗲𝘀𝘁 𝟵𝟬 𝘀𝗲𝗰
            45 Cal Echo Bike
            𝗥𝗲𝘀𝘁 𝟵𝟬 𝘀𝗲𝗰
            35 Cal Echo Bike

            𝗛𝗲𝗮𝗿𝘁 𝗥𝗮𝘁𝗲 𝗧𝗮𝗿𝗴𝗲𝘁: 87-94% of Max HR
            𝗜𝗻𝘁𝗲𝗻𝘀𝗶𝘁𝘆: RPE 8-9
            """

        let result = try await VersionedWorkoutParser().parse(rawText: raw)
        let segment = try XCTUnwrap(result.segments.first)

        XCTAssertEqual(result.title, "Echo Bike Intervals")
        XCTAssertEqual(result.format, .intervals)
        XCTAssertEqual(result.parserVersion, "deterministic-1.5.0")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(segment.restSeconds, 90)
        XCTAssertEqual(
            segment.movements.map(\.canonicalMovementID), Array(repeating: "air_bike", count: 4))
        XCTAssertEqual(segment.movements.map(\.calories), [60, 52, 45, 35])
        XCTAssertEqual(
            result.intendedStimulus.secondary,
            ["Heart Rate Target: 87-94% of Max HR", "Intensity: RPE 8-9"]
        )
        XCTAssertTrue(segment.notes.contains("Heart Rate Target: 87-94% of Max HR"))
        XCTAssertTrue(result.ambiguities.isEmpty)
    }

    func testAmbiguityIsExposedInsteadOfInvented() async throws {
        let result = try await VersionedWorkoutParser().parse(
            rawText: """
                Build to a challenging set
                Strict Press
                Then accessory work of choice
                """
        )

        XCTAssertGreaterThanOrEqual(result.ambiguities.count, 2)
        XCTAssertNil(
            result.segments.first?.movements.first(where: {
                $0.canonicalMovementID == "strict_press"
            })?.repetitions
        )
    }

    func testInvalidParserPayloadIsRejected() async throws {
        let parsed = try await VersionedWorkoutParser().parse(rawText: "10 Strict Press 45 lb")
        let encoded = try JSONEncoder().encode(parsed)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["parserConfidence"] = 1.5
        let invalidData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try WorkoutParserPayloadValidator().decode(invalidData)) { error in
            XCTAssertEqual(error as? WorkoutValidationError, .invalidConfidence)
        }
    }

    func testRestSegmentRequiresExclusiveDuration() async throws {
        var parsed = try await VersionedWorkoutParser().parse(
            rawText: "10 Strict Press 45 lb"
        )
        parsed.segments.append(
            WorkoutSegment(
                id: "rest-1",
                sequence: 2,
                type: .rest,
                rounds: nil,
                durationSeconds: 90,
                restSeconds: nil,
                notes: "",
                movements: []
            )
        )

        XCTAssertNoThrow(try parsed.validated())

        var conflicting = parsed
        conflicting.segments[1].restSeconds = 30
        XCTAssertThrowsError(try conflicting.validated()) { error in
            XCTAssertEqual(error as? WorkoutValidationError, .invalidSegment)
        }

        var missingDuration = parsed
        missingDuration.segments[1].durationSeconds = nil
        XCTAssertThrowsError(try missingDuration.validated()) { error in
            XCTAssertEqual(error as? WorkoutValidationError, .invalidSegment)
        }
    }

    func testVariableRecoveryCreatesDedicatedRestSegments() async throws {
        let parsed = try await VersionedWorkoutParser().parse(
            rawText: """
                10 Cal Echo Bike
                Rest 90 sec
                8 Cal Echo Bike
                Rest 60 sec
                6 Cal Echo Bike
                """
        )

        XCTAssertEqual(parsed.segments.map(\.type), [.work, .rest, .work, .rest, .work])
        XCTAssertEqual(parsed.segments[1].durationSeconds, 90)
        XCTAssertEqual(parsed.segments[3].durationSeconds, 60)
        XCTAssertTrue(parsed.segments.filter { $0.type == .rest }.allSatisfy(\.movements.isEmpty))
        XCTAssertTrue(
            parsed.segments.filter { $0.type == .work }.allSatisfy {
                $0.restSeconds == nil
            })
    }

    func testHardRestrictionForcesModificationAndOffersSafeCandidate() async throws {
        let parsed = try await VersionedWorkoutParser().parse(
            rawText: "21 Strict Press 95 lb"
        )
        let plan = WorkoutPlan(parsed: parsed)
        let restriction = RestrictionProfile(
            id: "triceps",
            injuryName: "Right distal triceps",
            bodyRegion: "Upper arm",
            side: "Right",
            movementTag: "ballistic or painful elbow extension",
            level: .avoid,
            painThreshold: 2,
            rationale: "Test",
            isActive: true
        )

        let result = await DeterministicWorkoutScalingEngine().evaluate(
            plan: plan,
            restrictions: [restriction]
        )

        XCTAssertEqual(result.recommendation, .modify)
        XCTAssertEqual(result.conflicts.first?.severity, .hard)
        XCTAssertTrue(
            result.conflicts.first?.substitutionCandidates.contains(where: {
                $0.id == "goblet_squat"
            }) == true
        )
    }

    @MainActor
    func testCompletionDraftCopiesAndPersistsActualCalories() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self,
            WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = WorkoutPersistence(container: container)
        let plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(
                rawText: "20 Cal Echo Bike"
            )
        )
        var completion = CompletedWorkout(
            plan: plan,
            now: Date(timeIntervalSince1970: 3_600)
        )

        XCTAssertEqual(completion.movements.first?.actualCalories, 20)
        completion.movements[0].actualCalories = 18
        try await repository.saveCompletedWorkout(completion)

        let completed = try await repository.completedWorkouts()
        let reloaded = try XCTUnwrap(completed.first)
        XCTAssertEqual(reloaded.movements.first?.actualCalories, 18)
    }

    @MainActor
    func testPersistenceKeepsPlannedAndActualWorkSeparate() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self,
            WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = WorkoutPersistence(container: container)
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(
                rawText: "10 Strict Press 45 lb"
            )
        )
        plan.status = .planned
        try await repository.savePlan(plan)
        let plannedMovement = try XCTUnwrap(plan.movements.first)
        let actual = CompletedWorkout(
            id: "actual-1",
            plannedWorkoutID: plan.id,
            title: plan.title,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 1_000),
            sessionRPE: 7,
            postSessionPain: 2,
            notes: "Reduced the load.",
            movements: [
                CompletedMovement(
                    id: "actual-movement-1",
                    canonicalMovementID: plannedMovement.canonicalMovementID,
                    plannedPrescriptionID: plannedMovement.id,
                    displayName: plannedMovement.displayName,
                    actualRepetitions: 8,
                    actualDistanceMeters: nil,
                    actualCalories: nil,
                    actualLoadValue: 35,
                    actualLoadUnit: "lb",
                    actualDurationSeconds: nil,
                    modification: "Reduced load and repetitions",
                    painDuring: 1,
                    notes: ""
                )
            ]
        )
        try await repository.saveCompletedWorkout(actual)

        let plans = try await repository.plans()
        let completed = try await repository.completedWorkouts()
        let reloadedPlan = try XCTUnwrap(plans.first)
        let reloadedActual = try XCTUnwrap(completed.first)
        XCTAssertEqual(reloadedPlan.movements.first?.repetitions, 10)
        XCTAssertEqual(reloadedPlan.movements.first?.loadValue, 45)
        XCTAssertEqual(reloadedPlan.status, .completed)
        XCTAssertEqual(reloadedActual.movements.first?.actualRepetitions, 8)
        XCTAssertEqual(reloadedActual.movements.first?.actualLoadValue, 35)
        XCTAssertEqual(reloadedActual.sessionRPE, 7)
        XCTAssertEqual(reloadedActual.postSessionPain, 2)

        try await repository.deleteCompletedWorkout(id: actual.id)
        let remainingActuals = try await repository.completedWorkouts()
        let restoredPlans = try await repository.plans()
        XCTAssertTrue(remainingActuals.isEmpty)
        XCTAssertEqual(restoredPlans.first?.status, .planned)
    }

    @MainActor
    func testPersistenceRejectsConflictingRestSegment() async throws {
        let container = try ModelContainer(
            for: WorkoutPlanRecord.self,
            WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = WorkoutPersistence(container: container)
        var plan = WorkoutPlan(
            parsed: try await VersionedWorkoutParser().parse(
                rawText: "10 Strict Press 45 lb"
            )
        )
        plan.segments.append(
            WorkoutSegment(
                id: "rest-1",
                sequence: 2,
                type: .rest,
                rounds: nil,
                durationSeconds: 90,
                restSeconds: 30,
                notes: "",
                movements: []
            )
        )

        do {
            try await repository.savePlan(plan)
            XCTFail("Expected a conflicting Rest segment to be rejected.")
        } catch {
            XCTAssertEqual(error as? WorkoutValidationError, .invalidSegment)
        }

        plan.segments[1].restSeconds = nil
        try await repository.savePlan(plan)
        let plans = try await repository.plans()
        let reloaded = try XCTUnwrap(plans.first)
        XCTAssertEqual(reloaded.segments[1].type, .rest)
        XCTAssertEqual(reloaded.segments[1].durationSeconds, 90)
        XCTAssertTrue(reloaded.segments[1].movements.isEmpty)
    }
}
