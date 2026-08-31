import XCTest

@testable import WhoopsApp

final class RecordActualTests: XCTestCase {
    private func makeItem(
        id: String = "band",
        sets: Int? = 3,
        repetitions: Int? = 15,
        durationSeconds: Int? = nil
    ) -> DocketItem {
        DocketItem(
            id: id,
            kind: .protocolItem,
            sourceID: id,
            protocolID: "protocol-1",
            title: "band extensions",
            tag: "PT",
            isCompleted: false,
            completionID: nil,
            prescribedSets: sets,
            prescribedRepetitions: repetitions,
            prescribedDurationSeconds: durationSeconds,
            recordedActual: nil
        )
    }

    func testDraftSeedsFromPrescriptionWithoutInventingMissingValues() {
        let draft = RecordActualDraft(item: makeItem(sets: 3, repetitions: 15))

        XCTAssertEqual(draft.sets, 3)
        XCTAssertEqual(draft.repetitions, 15)
        XCTAssertEqual(draft.holdSeconds, 0)
        XCTAssertNil(draft.painDuring)
        XCTAssertEqual(draft.note, "")
        XCTAssertTrue(draft.isAsPrescribed)

        // Untouched, the "as prescribed" path never invents a sets/reps value the
        // prescription never made — nothing was prescribed for hold-seconds here, and
        // it stays absent from the saved actual rather than surfacing as an explicit 0.
        let completion = draft.completion(
            item: makeItem(sets: 3, repetitions: 15), day: "2026-08-30")
        XCTAssertEqual(completion.actual?.sets, 3)
        XCTAssertEqual(completion.actual?.repetitions, 15)
        XCTAssertNil(completion.actual?.durationSeconds)
        XCTAssertNil(completion.actual?.painDuring)
        XCTAssertTrue(completion.actual?.isAsPrescribed ?? false)
    }

    func testSetsAndRepsStepperClampToBounds() {
        var draft = RecordActualDraft(item: makeItem(sets: 0, repetitions: 0))

        draft.decrementSets()
        XCTAssertEqual(draft.sets, 0, "sets must not clamp below 0")

        for _ in 0..<25 { draft.incrementSets() }
        XCTAssertEqual(draft.sets, RecordActualDraft.setsRange.upperBound)

        draft.decrementRepetitions()
        XCTAssertEqual(draft.repetitions, 0, "reps must not clamp below 0")

        for _ in 0..<250 { draft.incrementRepetitions() }
        XCTAssertEqual(draft.repetitions, RecordActualDraft.repetitionsRange.upperBound)
    }

    func testPainIsUnsetUntilTappedAndClearsOnRetap() {
        var draft = RecordActualDraft(item: makeItem())
        XCTAssertNil(draft.painDuring, "pain must never default to 0 — it starts unasked")

        draft.selectPain(2)
        XCTAssertEqual(draft.painDuring, 2)

        draft.selectPain(2)
        XCTAssertNil(draft.painDuring, "re-tapping the selected chip clears it back to nil")

        draft.selectPain(5)
        XCTAssertEqual(draft.painDuring, 5)
    }

    func testDraftReportsDeviationWhenAnyValueDiffersFromPrescription() {
        var draft = RecordActualDraft(item: makeItem(sets: 3, repetitions: 15))
        XCTAssertTrue(draft.isAsPrescribed)

        draft.incrementSets()
        XCTAssertFalse(draft.isAsPrescribed)
        draft.decrementSets()
        XCTAssertTrue(draft.isAsPrescribed, "returning to the seeded value is as-prescribed again")

        draft.selectPain(1)
        XCTAssertFalse(draft.isAsPrescribed, "recording any pain is a deviation on its own")
        draft.selectPain(1)
        XCTAssertTrue(draft.isAsPrescribed)

        draft.note = "swapped the yellow band for red"
        XCTAssertFalse(draft.isAsPrescribed, "a dictated note is a deviation on its own")
    }

    func testCompletionReusesExistingCompletionIdentityWhenEditing() {
        let item = makeItem(sets: 3, repetitions: 15)
        var draft = RecordActualDraft(item: item)
        draft.decrementSets()

        let firstSave = draft.completion(item: item, day: "2026-08-30")
        XCTAssertNotEqual(firstSave.id, "", "a fresh save mints its own identifier")

        let secondSave = draft.completion(
            item: item, day: "2026-08-30", existingID: firstSave.id)
        XCTAssertEqual(
            secondSave.id, firstSave.id,
            "editing an existing completion reuses its id rather than minting a second row")

        let edited = draft.completion(
            item: item, day: "2026-08-30", existingID: "existing-completion-id")
        XCTAssertEqual(edited.id, "existing-completion-id")
    }

    func testDurationBasedItemStepsHoldSecondsInsteadOfReps() {
        let item = makeItem(sets: 2, repetitions: nil, durationSeconds: 30)
        var draft = RecordActualDraft(item: item)

        XCTAssertTrue(draft.isDurationBased)
        XCTAssertEqual(draft.holdSeconds, 30)
        XCTAssertEqual(draft.repetitions, 0)

        draft.incrementHoldSeconds()
        XCTAssertEqual(draft.holdSeconds, 35, "hold-seconds steps by 5")
        XCTAssertFalse(draft.isAsPrescribed)

        let completion = draft.completion(item: item, day: "2026-08-30")
        XCTAssertEqual(completion.actual?.durationSeconds, 35)
        XCTAssertNil(
            completion.actual?.repetitions,
            "a duration-based item never invents a reps value")
    }
}
