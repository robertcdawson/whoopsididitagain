import SwiftData
import XCTest

@testable import WhoopsApp

final class FoundationBoundariesTests: XCTestCase {
    func testWorkoutParserPreservesOriginalText() async throws {
        let rawText = "3 rounds: 500 m row, 10 front squats"

        let result = try await VersionedWorkoutParser().parse(rawText: rawText)

        XCTAssertEqual(result.rawText, rawText)
        XCTAssertFalse(result.segments.isEmpty)
    }

    func testInMemoryStoreRoundTripsCodableValue() async throws {
        struct Example: Codable, Equatable, Sendable {
            let value: Int
        }

        let store = InMemoryLocalStore()
        try await store.save(Example(value: 42), forKey: "example")
        let loaded = try await store.load(Example.self, forKey: "example")

        XCTAssertEqual(loaded, Example(value: 42))
    }

    @MainActor
    func testWhoopPersistenceUpsertsSourceRecordsIdempotently() throws {
        let container = try ModelContainer(
            for: WhoopSourceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = WhoopPersistence(container: container)
        let response = WhoopSyncResponse(
            mode: .initial,
            startedAt: Date(timeIntervalSince1970: 1_000),
            completedAt: Date(timeIntervalSince1970: 1_001),
            resources: [
                WhoopSyncResource(
                    resourceType: .recovery,
                    records: [
                        .object([
                            "cycle_id": .number(42),
                            "updated_at": .string("2026-08-15T12:00:00.000Z"),
                            "score": .object([
                                "recovery_score": .number(81),
                                "resting_heart_rate": .number(55),
                            ]),
                        ])
                    ],
                    pageCount: 1,
                    windowStart: Date(timeIntervalSince1970: 0)
                )
            ]
        )

        _ = try persistence.upsert(response)
        _ = try persistence.upsert(response)
        let history = try persistence.history()

        XCTAssertEqual(history.recoveries.count, 1)
        XCTAssertEqual(history.recoveries.first?.recoveryScore, 81)
    }
}
