import SwiftData
import XCTest

@testable import WhoopsApp

@MainActor
final class MovementLibraryMilestoneTests: XCTestCase {
    func testPersonalMovementPersistsAcrossRepositoryInstances() async throws {
        let container = try makeContainer()
        let first = MovementLibraryPersistence(container: container)
        try await first.prepareDefaults()
        let movement = MovementDefinition.custom(
            name: "Sandbag bear-hug carry",
            aliases: ["Bear-hug carry"],
            category: .carry,
            equipment: ["Sandbag"],
            supportedMeasurements: [.distance, .load]
        )

        try await first.saveMovement(movement)
        let second = MovementLibraryPersistence(container: container)
        let saved = try await second.movements(includeArchived: false)
        let persisted = try XCTUnwrap(saved.first(where: { $0.id == movement.id }))

        XCTAssertEqual(persisted.canonicalName, movement.canonicalName)
        XCTAssertEqual(persisted.aliases, movement.aliases)
        XCTAssertEqual(persisted.equipment, ["Sandbag"])
        XCTAssertEqual(persisted.supportedMeasurements, [.distance, .load])
    }

    func testReconcileRemembersCleanUnmappedMovementAndParserReusesIt() async throws {
        let container = try makeContainer()
        let library = MovementLibraryPersistence(container: container)
        try await library.prepareDefaults()
        let plan = makePlan(
            movement: MovementPrescription(
                id: "prescription",
                canonicalMovementID: nil,
                displayName: "Sandbag bear-hug carry",
                originalText: "Sandbag bear-hug carry",
                repetitions: nil,
                distanceMeters: 100,
                calories: nil,
                loadValue: nil,
                loadUnit: nil,
                percentageOfOneRepMax: nil,
                durationSeconds: nil,
                tempo: nil,
                notes: ""
            )
        )

        let reconciled = try await library.reconcile(plan)
        let learnedID = try XCTUnwrap(reconciled.movements.first?.canonicalMovementID)
        let parsed = try await LibraryWorkoutParser(library: library).parse(
            rawText: "100 m Sandbag bear-hug carry"
        )
        let saved = try await library.movements(includeArchived: false)

        XCTAssertEqual(parsed.segments.first?.movements.first?.canonicalMovementID, learnedID)
        XCTAssertEqual(saved.filter { $0.canonicalName == "Sandbag bear-hug carry" }.count, 1)
    }

    func testCorrectedMappedNameBecomesReusableAlias() async throws {
        let library = MovementLibraryPersistence(container: try makeContainer())
        try await library.prepareDefaults()
        let plan = makePlan(
            movement: MovementPrescription(
                id: "row-alias",
                canonicalMovementID: "row",
                displayName: "Concept2 erg effort",
                originalText: "20 cal Concept2 erg effort",
                repetitions: nil,
                distanceMeters: nil,
                calories: 20,
                loadValue: nil,
                loadUnit: nil,
                percentageOfOneRepMax: nil,
                durationSeconds: nil,
                tempo: nil,
                notes: ""
            )
        )

        _ = try await library.reconcile(plan)
        let parsed = try await LibraryWorkoutParser(library: library).parse(
            rawText: "20 cal Concept2 erg effort"
        )

        XCTAssertEqual(parsed.segments.first?.movements.first?.canonicalMovementID, "row")
    }

    func testWODLabImportIsPreviewedAndIdempotent() async throws {
        let library = MovementLibraryPersistence(container: try makeContainer())
        try await library.prepareDefaults()
        let data = Data(
            """
            {"version":1,"stores":{"movements":[
              {"id":"existing-row","name":"Row","category":"machine","aliases":["Erg"]},
              {"id":"zercher-march","name":"Zercher March","category":"carry"}
            ]}}
            """.utf8
        )

        let preview = try await library.previewWODLabImport(data)
        let first = try await library.importWODLab(data)
        let second = try await library.importWODLab(data)
        let saved = try await library.movements(includeArchived: true)

        XCTAssertEqual(preview.additions.map(\.canonicalName), ["Zercher March"])
        XCTAssertEqual(preview.matchedCount, 1)
        XCTAssertEqual(first.addedCount, 1)
        XCTAssertEqual(second.addedCount, 0)
        XCTAssertEqual(second.matchedCount, 2)
        XCTAssertEqual(saved.filter { $0.canonicalName == "Zercher March" }.count, 1)
    }

    func testUsageIsDerivedFromSavedWorkoutHistory() async throws {
        let container = try makeContainer()
        let library = MovementLibraryPersistence(container: container)
        let workouts = WorkoutPersistence(container: container)
        try await library.prepareDefaults()
        let scheduledAt = Date(timeIntervalSince1970: 1_800_000_000)
        var plan = makePlan(
            movement: MovementPrescription(
                id: "row-prescription",
                canonicalMovementID: "row",
                displayName: "Row",
                originalText: "20 cal row",
                repetitions: nil,
                distanceMeters: nil,
                calories: 20,
                loadValue: nil,
                loadUnit: nil,
                percentageOfOneRepMax: nil,
                durationSeconds: nil,
                tempo: nil,
                notes: ""
            )
        )
        plan.scheduledAt = scheduledAt
        try await workouts.savePlan(plan)

        let summaries = try await library.usageSummaries()
        let row = try XCTUnwrap(summaries.first { $0.movement.id == "row" })

        XCTAssertEqual(row.appearanceCount, 1)
        XCTAssertEqual(row.lastUsedAt, scheduledAt)

        try await library.setArchived(true, movementID: "row")
        let active = try await library.movements(includeArchived: false)
        let withArchived = try await library.movements(includeArchived: true)
        let savedPlans = try await workouts.plans()

        XCTAssertFalse(active.contains { $0.id == "row" })
        XCTAssertTrue(withArchived.contains { $0.id == "row" && $0.isArchived })
        XCTAssertEqual(savedPlans.first?.movements.first?.canonicalMovementID, "row")
    }

    func testUntaggedPersonalMovementRequiresManualRestrictionReview() async throws {
        let movement = MovementDefinition.custom(name: "Novel press")
        let plan = makePlan(
            movement: MovementPrescription(
                id: "novel",
                canonicalMovementID: movement.id,
                displayName: movement.canonicalName,
                originalText: movement.canonicalName,
                repetitions: 10,
                distanceMeters: nil,
                calories: nil,
                loadValue: nil,
                loadUnit: nil,
                percentageOfOneRepMax: nil,
                durationSeconds: nil,
                tempo: nil,
                notes: ""
            )
        )
        let restriction = RestrictionProfile(
            id: "restriction",
            injuryName: "Elbow",
            bodyRegion: "elbow",
            side: "right",
            movementTag: "elbow extension",
            level: .avoid,
            painThreshold: 2,
            rationale: "Avoid aggravation",
            isActive: true
        )

        let result = await DeterministicWorkoutScalingEngine(
            catalog: MovementCatalog(items: [movement.catalogItem])
        ).evaluate(plan: plan, restrictions: [restriction])

        XCTAssertEqual(
            result.recommendation,
            ReadinessAssessment.Recommendation.proceedWithLimits
        )
        XCTAssertEqual(result.conflicts.first?.severity, .caution)
        XCTAssertTrue(result.conflicts.first?.explanation.contains("has not been reviewed") == true)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: MovementDefinitionRecord.self,
            WorkoutPlanRecord.self,
            WorkoutSegmentRecord.self,
            MovementPrescriptionRecord.self,
            CompletedWorkoutRecord.self,
            CompletedMovementRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makePlan(movement: MovementPrescription) -> WorkoutPlan {
        WorkoutPlan(
            id: UUID().uuidString,
            title: "Test workout",
            rawText: movement.originalText,
            parsedAt: .now,
            scheduledAt: .now,
            status: .planned,
            format: .manual,
            intendedStimulus: .unknown,
            timeCapSeconds: nil,
            parserVersion: "test",
            modelVersion: nil,
            confidence: 1,
            ambiguities: [],
            segments: [
                WorkoutSegment(
                    id: UUID().uuidString,
                    sequence: 1,
                    type: .work,
                    rounds: nil,
                    durationSeconds: nil,
                    restSeconds: nil,
                    notes: "",
                    movements: [movement]
                )
            ]
        )
    }
}
