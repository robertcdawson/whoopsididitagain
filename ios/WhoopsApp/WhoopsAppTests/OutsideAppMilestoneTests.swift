import XCTest

@testable import WhoopsApp

final class OutsideAppMilestoneTests: XCTestCase {
    func testPendingCompletionIsImmediatelyReflectedInEffectiveSnapshot() throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let item = sharedProtocolItem()
        try store.saveSnapshot(SharedDocketSnapshot(day: "2026-09-01", items: [item]))

        try store.enqueueCompletion(
            for: item,
            day: "2026-09-01",
            at: Date(timeIntervalSince1970: 100)
        )

        let effective = try XCTUnwrap(store.effectiveSnapshot())
        XCTAssertTrue(try XCTUnwrap(effective.items.first).isCompleted)
        XCTAssertEqual(try store.pendingCompletionActions().count, 1)
    }

    func testCoordinatorPersistsThenAcknowledgesOutsideCompletionAfterPublishing() async throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let repository = PreviewDocketRepository()
        let coordinator = OutsideAppDocketCoordinator(repository: repository, store: store)
        let item = sharedProtocolItem()
        try store.saveSnapshot(SharedDocketSnapshot(day: "2026-09-01", items: [item]))
        let action = try store.enqueueCompletion(
            for: item,
            day: "2026-09-01",
            at: Date(timeIntervalSince1970: 100)
        )

        let actionIDs = try await coordinator.reconcilePendingCompletions()
        let completions = try await repository.completions(days: ["2026-09-01"])

        XCTAssertEqual(actionIDs, [action.id])
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.sourceID, "band-work")
        XCTAssertEqual(completions.first?.actual?.sets, 3)
        XCTAssertEqual(completions.first?.actual?.repetitions, 15)
        XCTAssertTrue(completions.first?.actual?.isAsPrescribed == true)
        XCTAssertEqual(try store.pendingCompletionActions().count, 1)

        let completedItem = DocketItem(
            id: item.id,
            kind: .protocolItem,
            sourceID: item.sourceID,
            protocolID: item.protocolID,
            title: item.title,
            tag: item.tag,
            isCompleted: true,
            completionID: completions.first?.id,
            prescribedSets: item.prescribedSets,
            prescribedRepetitions: item.prescribedRepetitions,
            prescribedDurationSeconds: item.prescribedDurationSeconds,
            recordedActual: completions.first?.actual
        )
        try await coordinator.publish(
            DailyDocket(
                day: "2026-09-01",
                rulesetVersion: DeterministicDocketEngine.rulesetVersion,
                items: [completedItem]
            ),
            acknowledging: actionIDs
        )

        XCTAssertTrue(try XCTUnwrap(store.snapshot()).items[0].isCompleted)
        XCTAssertTrue(try store.pendingCompletionActions().isEmpty)
    }

    func testWorkoutCannotBeCompletedThroughOutsideBridge() throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let workout = SharedDocketItem(
            id: "workout:plan",
            kind: "workout",
            sourceID: "plan",
            protocolID: nil,
            title: "evening workout",
            tag: nil,
            isCompleted: false,
            prescribedSets: nil,
            prescribedRepetitions: nil,
            prescribedDurationSeconds: nil
        )

        XCTAssertThrowsError(try store.enqueueCompletion(for: workout, day: "2026-09-01")) {
            XCTAssertEqual($0 as? SharedDocketStoreError, .workoutRequiresApp)
        }
    }

    private func temporaryStore() throws -> (SharedDocketStore, URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoops-outside-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return (SharedDocketStore(rootURL: rootURL), rootURL)
    }

    private func sharedProtocolItem() -> SharedDocketItem {
        SharedDocketItem(
            id: "protocol_item:band-work",
            kind: "protocol_item",
            sourceID: "band-work",
            protocolID: "pt",
            title: "band extensions 3×15",
            tag: "PT",
            isCompleted: false,
            prescribedSets: 3,
            prescribedRepetitions: 15,
            prescribedDurationSeconds: nil
        )
    }
}
