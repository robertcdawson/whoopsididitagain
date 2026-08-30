import SwiftData
import XCTest

@testable import WhoopsApp

final class WorkoutMilestoneTests: XCTestCase {
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
        XCTAssertEqual(result.parserVersion, "deterministic-1.4.0")
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
            XCTAssertEqual(result.timeCapSeconds, cap)
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
        XCTAssertEqual(result.parserVersion, "deterministic-1.4.0")
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
