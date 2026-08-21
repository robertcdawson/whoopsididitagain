import XCTest

@testable import WhoopsApp

final class WODLabMovementImporterTests: XCTestCase {
    func testImportsStableMovementFieldsAndIgnoresUnrelatedStores() throws {
        let data = Data(
            """
            {
              "version": 1,
              "exported_at": "2026-08-16T20:00:00.000Z",
              "stores": {
                "movements": [
                  {
                    "id": "movement-1",
                    "name": "  Toes-to-Bar  ",
                    "category": "gymnastics",
                    "aliases": ["T2B", " toes to bar "],
                    "technique": { "personal_cues": "Stay tight" }
                  }
                ],
                "workout_movements": [
                  {
                    "movement_id": "movement-1",
                    "prescription": {
                      "load": "20 lb",
                      "reps": "15",
                      "distance": "400 m",
                      "calories": "12",
                      "variation": "strict"
                    }
                  }
                ],
                "future_store": [{ "anything": true }]
              }
            }
            """.utf8
        )

        let result = try WODLabMovementImporter().importMovements(from: data)

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(
            result.candidates,
            [
                WODLabMovementImportCandidate(
                    id: "movement-1",
                    name: "Toes-to-Bar",
                    category: .gymnastics,
                    aliases: ["T2B", "toes to bar"]
                )
            ]
        )
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMapsEveryWODLabMovementCategory() throws {
        let rawCategories = [
            "weightlifting", "power", "gymnastics", "machine", "running", "jumping", "carry",
            "odd_object", "crossfit",
        ]
        let movements = rawCategories.enumerated().map { index, category in
            ["id": "movement-\(index)", "name": "Movement \(index)", "category": category]
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["version": 1, "stores": ["movements": movements]]
        )

        let result = try WODLabMovementImporter().importMovements(from: data)

        XCTAssertEqual(result.importedCount, 9)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(Set(result.candidates.map(\.category)), Set(WODLabMovementCategory.allCases))
    }

    func testSkipsDeletedAndInvalidRecordsWithPerRecordIssues() throws {
        let data = Data(
            """
            {
              "version": 1,
              "stores": {
                "movements": [
                  {"id":"deleted","name":"Run","category":"running","deleted":true},
                  {"id":" ","name":" ","category":"crossfit"},
                  {"id":"unknown","name":"Unknown","category":"mobility"},
                  "not an object",
                  {"id":"valid","name":"Row","category":"machine","aliases":["Erg", "", 42]}
                ]
              }
            }
            """.utf8
        )

        let result = try WODLabMovementImporter().importMovements(from: data)

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.skippedCount, 4)
        XCTAssertEqual(result.candidates.first?.aliases, ["Erg"])
        XCTAssertTrue(
            result.issues.contains { $0.kind == .deletedRecord && $0.sourceID == "deleted" })
        XCTAssertTrue(result.issues.contains { $0.kind == .missingID && $0.recordIndex == 1 })
        XCTAssertTrue(result.issues.contains { $0.kind == .missingName && $0.recordIndex == 1 })
        XCTAssertTrue(result.issues.contains { $0.kind == .unsupportedCategory })
        XCTAssertTrue(result.issues.contains { $0.kind == .invalidRecord })
        XCTAssertTrue(
            result.issues.contains { $0.kind == .invalidAliases && $0.sourceID == "valid" })
    }

    func testPreservesUniqueNonblankAliasesWithoutRepeatingName() throws {
        let data = Data(
            """
            {
              "version": 1,
              "stores": {
                "movements": [
                  {
                    "id": "wall-ball",
                    "name": "Wall Ball",
                    "category": "crossfit",
                    "aliases": ["WB", "wb", "Wall Ball", " wallball "]
                  }
                ]
              }
            }
            """.utf8
        )

        let result = try WODLabMovementImporter().importMovements(from: data)

        XCTAssertEqual(result.candidates.first?.aliases, ["WB", "wallball"])
    }

    func testRejectsUnsupportedOrStructurallyInvalidExports() throws {
        let unsupported = Data("{\"version\":2,\"stores\":{\"movements\":[]}}".utf8)
        XCTAssertThrowsError(try WODLabMovementImporter().importMovements(from: unsupported)) {
            XCTAssertEqual($0 as? WODLabMovementImportError, .unsupportedVersion(2))
        }

        let missingMovements = Data("{\"version\":1,\"stores\":{\"workouts\":[]}}".utf8)
        XCTAssertThrowsError(try WODLabMovementImporter().importMovements(from: missingMovements)) {
            XCTAssertEqual($0 as? WODLabMovementImportError, .missingMovementsStore)
        }

        let malformed = Data("not-json".utf8)
        XCTAssertThrowsError(try WODLabMovementImporter().importMovements(from: malformed)) {
            XCTAssertEqual($0 as? WODLabMovementImportError, .malformedJSON)
        }
    }
}
