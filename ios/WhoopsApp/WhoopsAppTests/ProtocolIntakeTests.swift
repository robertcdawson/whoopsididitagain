import SwiftData
import XCTest

@testable import WhoopsApp

@MainActor
final class ProtocolIntakeTests: XCTestCase {
    private let ptCatalog = MovementCatalog(items: [
        MovementCatalogItem(
            id: "band_extension",
            canonicalName: "Band extensions",
            aliases: ["banded tricep extension"],
            movementFamily: "press",
            tags: [.elbowExtension],
            substitutionCandidates: []
        ),
        MovementCatalogItem(
            id: "isometric_tricep_hold",
            canonicalName: "Isometric tricep hold",
            aliases: [],
            movementFamily: "press",
            tags: [.isometric],
            substitutionCandidates: []
        ),
        MovementCatalogItem(
            id: "overhead_tricep_extension",
            canonicalName: "Overhead tricep extension",
            aliases: [],
            movementFamily: "press",
            tags: [.elbowExtension, .overhead],
            substitutionCandidates: []
        ),
    ])

    func testMatchedItemParsesSetsRepsAndInlineCadence() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: "Band extensions 3×15 daily",
            source: .photo
        )

        XCTAssertEqual(parsed.items.count, 1)
        let item = try XCTUnwrap(parsed.items.first)
        XCTAssertEqual(
            item.resolution,
            .matched(movementID: "band_extension", name: "Band extensions")
        )
        XCTAssertEqual(item.sets, 3)
        XCTAssertEqual(item.repetitions, 15)
        XCTAssertNil(item.durationSeconds)
        XCTAssertEqual(item.cadence, .daily)
        XCTAssertEqual(parsed.parserConfidence, 1)
    }

    func testAbbreviatedMovementSurfacesCandidatesWithoutGuessing() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: "tricep ext. 5×30s",
            source: .photo
        )

        let item = try XCTUnwrap(parsed.items.first)
        XCTAssertEqual(item.sets, 5)
        XCTAssertEqual(item.durationSeconds, 30)
        XCTAssertNil(item.repetitions)
        guard case .ambiguous(let candidateIDs) = item.resolution else {
            return XCTFail("Expected candidates, got \(item.resolution)")
        }
        XCTAssertTrue(candidateIDs.contains("isometric_tricep_hold"))
        XCTAssertTrue(candidateIDs.contains("overhead_tricep_extension"))
    }

    func testUnknownMovementIsMarkedNewInsteadOfInvented() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: "Scap wall slides 2×10",
            source: .paste
        )

        let item = try XCTUnwrap(parsed.items.first)
        XCTAssertEqual(item.resolution, .unknown)
        XCTAssertEqual(item.movementText, "Scap wall slides")
        XCTAssertEqual(item.sets, 2)
        XCTAssertEqual(item.repetitions, 10)
    }

    func testTitlePhaseMilestoneAndSheetCadenceAreExtracted() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: """
                Home exercise program:
                Phase 2 of 5 until full extension unlocks
                3x/week
                Band extensions 3×15
                """,
            source: .dictation
        )

        XCTAssertEqual(parsed.title, "Home exercise program")
        XCTAssertEqual(parsed.phaseNumber, 2)
        XCTAssertEqual(parsed.phaseCount, 5)
        XCTAssertEqual(parsed.unlockMilestone, "full extension")
        XCTAssertEqual(parsed.defaultCadence, .timesPerWeek(3))
        XCTAssertEqual(parsed.items.count, 1)
    }

    func testStylizedUnicodeIsNormalizedBeforeParsing() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: "𝗕𝗮𝗻𝗱 𝗲𝘅𝘁𝗲𝗻𝘀𝗶𝗼𝗻𝘀 𝟯×𝟭𝟱",
            source: .photo
        )

        let item = try XCTUnwrap(parsed.items.first)
        XCTAssertEqual(
            item.resolution,
            .matched(movementID: "band_extension", name: "Band extensions")
        )
        XCTAssertEqual(item.sets, 3)
        XCTAssertEqual(item.repetitions, 15)
    }

    func testEmptyAndItemFreeTextThrowExplicitErrors() async throws {
        let parser = DeterministicProtocolParser(catalog: ptCatalog)
        do {
            _ = try await parser.parse(rawText: "   \n ", source: .paste)
            XCTFail("Expected emptyText")
        } catch let error as ProtocolParseError {
            XCTAssertEqual(error, .emptyText)
        }
        do {
            _ = try await parser.parse(rawText: "Daily\nPhase 1", source: .paste)
            XCTFail("Expected noItemsFound")
        } catch let error as ProtocolParseError {
            XCTAssertEqual(error, .noItemsFound)
        }
    }

    func testReviewItemMustBeResolvedAndCadenceValidBeforeSave() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: "tricep ext. 5×30s",
            source: .photo
        )
        var review = ProtocolReviewItem(
            parsed: try XCTUnwrap(parsed.items.first),
            defaultCadence: .daily
        )

        XCTAssertFalse(review.isResolved)
        XCTAssertNil(review.savedItem(order: 1))

        review.resolve(toMovementID: "overhead_tricep_extension", name: "Overhead tricep extension")
        let saved = try XCTUnwrap(review.savedItem(order: 1))
        XCTAssertEqual(saved.canonicalMovementID, "overhead_tricep_extension")
        XCTAssertEqual(saved.displayName, "Overhead tricep extension")
        XCTAssertEqual(saved.cadence, .daily)

        review.cadence = .daysOfWeek([])
        XCTAssertNil(review.savedItem(order: 1))
        review.cadence = .daysOfWeek([2, 4, 6])
        XCTAssertNotNil(review.savedItem(order: 1))
    }

    func testRestrictionCheckFlagsElbowConflictThroughSharedEngine() async throws {
        let parsed = try await DeterministicProtocolParser().parse(
            rawText: "Push-ups 3×10",
            source: .paste
        )
        let review = ProtocolReviewItem(
            parsed: try XCTUnwrap(parsed.items.first),
            defaultCadence: .daily
        )
        XCTAssertTrue(review.isResolved)
        let plan = try XCTUnwrap(
            ProtocolRestrictionCheck.evaluationPlan(title: "PT protocol", items: [review])
        )
        let restriction = RestrictionProfile(
            id: "triceps",
            injuryName: "Right triceps repair",
            bodyRegion: "Right arm",
            side: "Right",
            movementTag: "elbow extension",
            level: .avoid,
            painThreshold: 2,
            rationale: "Post-surgical protection",
            isActive: true
        )

        let evaluation = await DeterministicWorkoutScalingEngine().evaluate(
            plan: plan,
            restrictions: [restriction]
        )

        XCTAssertEqual(evaluation.recommendation, .modify)
        XCTAssertTrue(evaluation.conflicts.contains { $0.severity == .hard })
    }

    func testTimedProtocolPreservesDurationThroughWorkoutRestrictionBridge() async throws {
        let parsed = try await DeterministicProtocolParser(catalog: ptCatalog).parse(
            rawText: "Isometric tricep hold 5×30s daily", source: .paste
        )
        let review = ProtocolReviewItem(
            parsed: try XCTUnwrap(parsed.items.first), defaultCadence: .daily
        )
        let saved = try XCTUnwrap(review.savedItem(order: 1))
        let plan = try XCTUnwrap(
            ProtocolRestrictionCheck.evaluationPlan(title: "Timed protocol", items: [review])
        )
        XCTAssertEqual(saved.sets, 5)
        XCTAssertEqual(saved.durationSeconds, 30)
        XCTAssertEqual(plan.movements.first?.durationSeconds, 30.0)
        XCTAssertNil(plan.movements.first?.repetitions)
        XCTAssertNil(plan.reportedResult)
    }

    func testCadenceCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let cadences: [ProtocolCadence] = [.daily, .timesPerWeek(3), .daysOfWeek([1, 3, 5])]
        for cadence in cadences {
            let data = try encoder.encode(cadence)
            XCTAssertEqual(try decoder.decode(ProtocolCadence.self, from: data), cadence)
        }
    }

    func testProtocolPersistenceRoundTripAndDelete() async throws {
        let container = try makeContainer()
        let repository = ProtocolPersistence(container: container)
        let therapyProtocol = TherapyProtocol(
            id: "proto-1",
            title: "Tricep protocol",
            source: .photo,
            rawText: "Band extensions 3×15\nIsometric holds 5×30s",
            phaseNumber: 2,
            phaseCount: 5,
            unlockMilestone: "full extension",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endsAt: nil,
            parserVersion: DeterministicProtocolParser.parserVersion,
            confidence: 1,
            isArchived: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: [
                TherapyProtocolItem(
                    id: "item-1",
                    order: 1,
                    canonicalMovementID: "band_extension",
                    displayName: "Band extensions",
                    originalText: "Band extensions 3×15",
                    sets: 3,
                    repetitions: 15,
                    durationSeconds: nil,
                    loadValue: nil,
                    loadUnit: nil,
                    cadence: .daily,
                    notes: ""
                ),
                TherapyProtocolItem(
                    id: "item-2",
                    order: 2,
                    canonicalMovementID: "isometric_tricep_hold",
                    displayName: "Isometric tricep hold",
                    originalText: "Isometric holds 5×30s",
                    sets: 5,
                    repetitions: nil,
                    durationSeconds: 30,
                    loadValue: nil,
                    loadUnit: nil,
                    cadence: .timesPerWeek(3),
                    notes: "Each side"
                ),
            ]
        )

        try await repository.saveProtocol(therapyProtocol)
        let second = ProtocolPersistence(container: container)
        let loaded = try await second.protocols(includeArchived: false)

        XCTAssertEqual(loaded, [therapyProtocol])

        try await second.deleteProtocol(id: "proto-1")
        let remaining = try await second.protocols(includeArchived: true)
        XCTAssertTrue(remaining.isEmpty)
        let orphanItems = try container.mainContext.fetch(
            FetchDescriptor<TherapyProtocolItemRecord>()
        )
        XCTAssertTrue(orphanItems.isEmpty)
    }

    func testPersistenceRejectsUnresolvedOrInvalidProtocols() async throws {
        let repository = ProtocolPersistence(container: try makeContainer())
        let invalid = TherapyProtocol(
            id: "proto-invalid",
            title: "Tricep protocol",
            source: .paste,
            rawText: "raw",
            phaseNumber: nil,
            phaseCount: nil,
            unlockMilestone: nil,
            startedAt: .now,
            endsAt: nil,
            parserVersion: DeterministicProtocolParser.parserVersion,
            confidence: 1,
            isArchived: false,
            createdAt: .now,
            items: [
                TherapyProtocolItem(
                    id: "item-1",
                    order: 1,
                    canonicalMovementID: "",
                    displayName: "Band extensions",
                    originalText: "Band extensions 3×15",
                    sets: 3,
                    repetitions: 15,
                    durationSeconds: nil,
                    loadValue: nil,
                    loadUnit: nil,
                    cadence: .daily,
                    notes: ""
                )
            ]
        )

        do {
            try await repository.saveProtocol(invalid)
            XCTFail("Expected invalidItem")
        } catch let error as ProtocolValidationError {
            XCTAssertEqual(error, .invalidItem)
        }
        let empty = try await repository.protocols(includeArchived: true)
        XCTAssertTrue(empty.isEmpty)
    }

    func testLibraryProtocolParserResolvesPersonalMovements() async throws {
        let container = try ModelContainer(
            for: MovementDefinitionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let library = MovementLibraryPersistence(container: container)
        try await library.prepareDefaults()
        try await library.saveMovement(MovementDefinition.custom(name: "Scap wall slides"))

        let parsed = try await LibraryProtocolParser(library: library).parse(
            rawText: "Scap wall slides 2×10",
            source: .photo
        )

        guard case .matched(_, let name) = try XCTUnwrap(parsed.items.first).resolution else {
            return XCTFail("Expected the personal movement to match")
        }
        XCTAssertEqual(name, "Scap wall slides")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: TherapyProtocolRecord.self,
            TherapyProtocolItemRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
