import XCTest

final class WhoopsAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompletedWorkoutFieldsCanBeEditedCancelledAndReopened() throws {
        let app = makeApp()
        let workoutTitle =
            "Burpee and overhead kettlebell swing — editable workout " + UUID().uuidString.prefix(6)
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("AMRAP 8 minutes\n4 Burpees\nScore: 5 rounds, 3 reps")
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        app.buttons["review-and-save-workout"].tap()
        app.buttons["Save reviewed plan"].tap()
        let actual = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "record-actual-workout-")
        ).firstMatch
        for _ in 0..<8 where !actual.isHittable { app.swipeUp() }
        actual.tap()
        XCTAssertTrue(app.navigationBars["Record Actual Work"].waitForExistence(timeout: 5))
        replaceWholeField(
            app.textFields["Workout title"], with: workoutTitle, in: app)
        app.buttons["save-actual-workout"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        let detailLink = app.buttons["View completed workout: \(workoutTitle)"]
        for _ in 0..<10 where !detailLink.isHittable { app.swipeUp() }
        detailLink.tap()
        XCTAssertTrue(app.buttons["edit-completed-workout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["completed-workout-title"].label, workoutTitle)
        captureJournal("CompletedWorkout", app: app)
        app.buttons["edit-completed-workout"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.textFields["Workout title"].value as? String, workoutTitle)
        captureJournal("EditWorkout", app: app)
        XCTAssertTrue(app.datePickers["workout-started-at"].exists)
        XCTAssertTrue(app.datePickers["workout-ended-at"].exists)
        let duration = app.textFields["Session duration in minutes"]
        for _ in 0..<6 where !duration.isHittable { app.swipeUp() }
        replaceText(duration, with: "30.25")
        captureJournal("EditWorkout-Focused", app: app)
        app.buttons["dismiss-workout-keyboard"].tap()
        XCTAssertEqual(duration.value as? String, "30.25")
        let rpeChip = app.buttons["session-rpe-chip-7"]
        for _ in 0..<6 where !rpeChip.isHittable { app.swipeUp() }
        for _ in 0..<4 where !rpeChip.isHittable { app.swipeLeft() }
        rpeChip.tap()
        let painChip = app.buttons["post-session-pain-chip-2"]
        for _ in 0..<6 where !painChip.isHittable { app.swipeUp() }
        painChip.tap()
        let rounds = app.textFields["Completed rounds"]
        for _ in 0..<12 where !rounds.isHittable { app.swipeUp() }
        replaceText(rounds, with: "6")
        app.buttons["dismiss-workout-keyboard"].tap()
        let repsPlus = app.buttons["actual-reps-plus-0"]
        for _ in 0..<14 where !repsPlus.isHittable { app.swipeUp() }
        let repsMinus = app.buttons["actual-reps-minus-0"]
        // The stepper is seeded from the plan's reported score, not zero, and a stepper (unlike
        // the old text field) can't be set to an absolute value directly. Floor it first so the
        // following taps land on a known, deterministic total.
        for _ in 0..<60 { repsMinus.tap() }
        for _ in 0..<17 { repsPlus.tap() }
        // A burst of rapid taps leaves the form mid-relayout for a moment; let it settle before
        // the next interaction rather than racing a stale hit-test coordinate.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let load = app.textFields["Actual load"].firstMatch
        for _ in 0..<10 where !load.isHittable { app.swipeUp() }
        replaceWholeField(load, with: "12.5", in: app)
        app.buttons["save-actual-workout"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[workoutTitle].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        XCTAssertTrue(app.staticTexts["Duration, 30.25 min"].exists)
        XCTAssertTrue(app.staticTexts["Session RPE, 7/10"].exists)
        XCTAssertTrue(app.staticTexts["Post-session pain, 2/10"].exists)

        // Reopen the saved values, then cancel a new edit without persisting it.
        app.buttons["edit-completed-workout"].tap()
        XCTAssertEqual(duration.value as? String, "30.25")
        replaceWholeField(
            app.textFields["Workout title"], with: "Cancelled edit", in: app)
        app.navigationBars["Edit Workout"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars[workoutTitle].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        app.terminate()
        app.launch()
        openWork(in: app)
        for _ in 0..<10 where !detailLink.isHittable { app.swipeUp() }
        XCTAssertEqual(
            app.buttons.matching(identifier: "View completed workout: \(workoutTitle)").count, 1)
        detailLink.tap()
        app.buttons["edit-completed-workout"].tap()
        XCTAssertEqual(duration.value as? String, "30.25")
        for _ in 0..<12 where !rounds.isHittable { app.swipeUp() }
        XCTAssertEqual(rounds.value as? String, "6")
        let repsValue = app.staticTexts["17"]
        for _ in 0..<14 where !repsValue.isHittable { app.swipeUp() }
        XCTAssertTrue(repsValue.exists)
        for _ in 0..<10 where !load.isHittable { app.swipeUp() }
        XCTAssertEqual(load.value as? String, "12.5")
    }

    @MainActor
    func testSavedPlanHasAnEditActionAndEditableScheduleAndEstimates() throws {
        let app = makeApp()
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("AMRAP 8 minutes\n4 Burpees")
        tapParseWorkout(in: app)
        app.buttons["review-and-save-workout"].tap()
        app.buttons["Save reviewed plan"].tap()
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workout-plan-details-")
        ).firstMatch
        for _ in 0..<8 where !card.isHittable { app.swipeUp() }
        card.tap()
        app.buttons["edit-planned-workout"].tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let scheduled = app.datePickers["workout-scheduled-at"]
        for _ in 0..<6 where !scheduled.isHittable { app.swipeUp() }
        XCTAssertTrue(scheduled.isEnabled)
        let details = app.buttons.containing(.staticText, identifier: "Workout details").firstMatch
        for _ in 0..<6 where !details.isHittable { app.swipeUp() }
        details.tap()
        XCTAssertTrue(app.navigationBars["Workout Details"].waitForExistence(timeout: 5))
        let targets = app.textFields["Targets and context"]
        replaceWholeField(targets, with: "Synthetic target one\nSynthetic target two", in: app)
        app.buttons["dismiss-workout-keyboard"].tap()
        let minimum = app.textFields["Estimated minimum minutes"]
        let maximum = app.textFields["Estimated maximum minutes"]
        replaceWholeField(minimum, with: "5.25", in: app)
        // Reject a third decimal without an onChange rollback loop or losing focus.
        minimum.typeText("9")
        XCTAssertEqual(minimum.value as? String, "5.25")
        app.buttons["dismiss-workout-keyboard"].tap()
        replaceWholeField(maximum, with: "15.75", in: app)
        app.navigationBars["Workout Details"].buttons.element(boundBy: 0).tap()
        app.buttons["review-and-save-workout"].tap()
        app.buttons["Save reviewed plan"].tap()
        XCTAssertTrue(app.staticTexts["Estimated minimum, 5.25 min"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Estimated maximum, 15.75 min"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic target one"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic target two"].exists)
        assertKeyboardHidden(in: app)
    }

    @MainActor
    private func replaceWholeField(_ field: XCUIElement, with text: String, in app: XCUIApplication)
    {
        // Hittable can mean only a sliver of the input is visible. Reach the entire bordered
        // control before tapping. Select all instead of inferring caret position from the
        // field's frame: right-aligned values and wrapped titles use different text bounds.
        for _ in 0..<12 {
            if !field.exists || field.frame.maxY > app.frame.maxY - 44 {
                app.swipeUp()
            } else if field.frame.minY < app.navigationBars.firstMatch.frame.maxY + 12 {
                app.swipeDown()
            } else {
                break
            }
        }
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let existing = (field.value as? String) ?? ""
        if !existing.isEmpty && existing != field.placeholderValue {
            field.press(forDuration: 1.1)
            let menuItem = app.menuItems["Select All"]
            let button = app.buttons["Select All"]
            if menuItem.waitForExistence(timeout: 1) {
                menuItem.tap()
            } else if button.waitForExistence(timeout: 1) {
                button.tap()
            } else {
                captureJournal("FieldSelection", app: app)
                XCTFail("Select All must be available before replacing the complete field")
            }
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    @MainActor
    func testSharedKeyboardDismissalPreservesMultilineNotes() throws {
        let app = makeApp()
        app.launch()
        app.buttons["morning-check-in"].tap()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))
        let notes = app.descendants(matching: .any).matching(identifier: "check-in-notes")
            .firstMatch
        let save = app.buttons["check-in-save"]
        // A scroll-view field can be reported hittable under the pinned save action.
        // Bring the whole field above that action before attempting text entry.
        for _ in 0..<10
        where !notes.isHittable || notes.frame.maxY > save.frame.minY - 8 { app.swipeUp() }
        captureJournal("CheckIn-Notes", app: app)
        notes.tap()
        notes.typeText("Synthetic first line\nSynthetic second line")
        XCTAssertTrue((notes.value as? String)?.contains("first line\nSynthetic second") == true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["dismiss-form-keyboard"].tap()
        assertKeyboardHidden(in: app)
        notes.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(
            CGVector(dx: 12, dy: app.navigationBars.firstMatch.frame.maxY + 30))
        let end = origin.withOffset(CGVector(dx: 12, dy: app.frame.maxY - 24))
        start.press(forDuration: 0.1, thenDragTo: end)
        assertKeyboardHidden(in: app)
        for _ in 0..<10
        where !notes.isHittable || notes.frame.maxY > save.frame.minY - 8 { app.swipeUp() }
        notes.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        app.navigationBars["Morning Check-In"].buttons["Cancel"].tap()
        XCTAssertTrue(app.otherElements["journal-page-today"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
    }

    @MainActor
    func testWorkoutKeyboardDismissesOnSubmitCancelSaveAndTabChanges() throws {
        let app = makeApp()
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("AMRAP 8 minutes\n4 Burpees\nScore: 5 rounds, 3 reps")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        let title = app.textFields["Title"]
        for _ in 0..<6 where !title.isHittable { app.swipeUp() }
        title.tap()
        title.typeText(" A")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.keyboards.buttons["Done"].tap()
        assertKeyboardHidden(in: app)
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "dismiss-workout-keyboard").count, 1)
        app.buttons["dismiss-workout-keyboard"].tap()
        assertKeyboardHidden(in: app)
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.navigationBars["Review Workout"].buttons["Cancel"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)

        for _ in 0..<6
        where entry.frame.minY < app.otherElements["journal-page-work"].frame.minY + 30 {
            app.swipeDown()
        }
        entry.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        // The software keyboard covers the tab bar; finish editing before tapping a tab.
        app.buttons["dismiss-workout-keyboard"].tap()
        assertKeyboardHidden(in: app)
        app.buttons["zone-today"].tap()
        XCTAssertTrue(app.otherElements["journal-page-today"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        openWork(in: app)
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !title.isHittable { app.swipeUp() }
        title.tap()
        title.typeText(" B")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["review-and-save-workout"].tap()
        XCTAssertTrue(app.buttons["Save reviewed plan"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        app.buttons["Save reviewed plan"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)

        let edit = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "edit-workout-plan-")
        ).firstMatch
        for _ in 0..<8 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !title.isHittable { app.swipeUp() }
        title.tap()
        title.typeText(" C")
        app.buttons["review-and-save-workout"].tap()
        app.buttons["Save reviewed plan"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)

        let actual = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "record-actual-workout-")
        ).firstMatch
        for _ in 0..<8 where !actual.isHittable { app.swipeUp() }
        actual.tap()
        XCTAssertTrue(app.navigationBars["Record Actual Work"].waitForExistence(timeout: 5))
        let load = app.textFields["Actual load"].firstMatch
        for _ in 0..<10 where !load.isHittable { app.swipeUp() }
        replaceText(load, with: "18")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["save-actual-workout"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
    }

    @MainActor
    private func assertKeyboardHidden(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        let result = XCTWaiter.wait(for: [hidden], timeout: 4)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Keyboard dismissal failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(
            result, .completed,
            "Keyboard must not remain visible or return after leaving a field", file: file,
            line: line)
    }

    @MainActor
    private func tapParseWorkout(in app: XCUIApplication) {
        let parse = app.buttons["parse-workout"]
        let keyboard = app.keyboards.firstMatch
        let done = app.buttons["dismiss-workout-keyboard"]
        // Use the actual footer boundary, not an estimated distance from the keyboard.
        // Predictive text and journal navigation can put Done well above the key frame.
        if keyboard.exists {
            let bottom = done.exists ? done.frame.minY : keyboard.frame.minY
            if !parse.isHittable || parse.frame.isEmpty || parse.frame.minY < 100
                || parse.frame.maxY > bottom - 8
            {
                done.tap()
                assertKeyboardHidden(in: app)
            }
        }
        if !keyboard.exists {
            scrollAboveJournalNavigation(parse, in: app)
        }
        XCTAssertTrue(parse.isEnabled)
        // Do not let XCTest auto-scroll and tap a stale position beneath a pinned footer.
        parse.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    func testReportedMovementTotalsCanBeCorrectedResetAndReopened() throws {
        let app = makeApp()
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(
            "AMRAP 8 minutes\n4 Burpees\n12 Overhead Kettlebell Swings (35#)\nScore: 5 rounds, 3 reps"
        )
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let burpee = app.buttons["movement-editor-0-0"]
        for _ in 0..<6 where !burpee.isHittable { app.swipeUp() }
        XCTAssertTrue(burpee.label.contains("Reported total: 23 reps"))
        burpee.tap()
        let total = app.textFields["Reported total reps"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.value as? String, "23")
        replaceText(total, with: "19")
        app.navigationBars["Movement"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(burpee.waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        XCTAssertTrue(burpee.label.contains("Reported total: 19 reps (edited)"))
        XCTAssertTrue(burpee.label.contains("4 reps"), "Prescribed reps must not change")

        let rounds = app.textFields["Completed rounds"]
        for _ in 0..<6
        where !rounds.isHittable
            || rounds.frame.minY < app.navigationBars["Review Workout"].frame.maxY + 16
        { app.swipeDown() }
        XCTAssertEqual(rounds.value as? String, "5")
        XCTAssertEqual(app.textFields["Additional reps"].value as? String, "3")
        replaceText(rounds, with: "6")
        app.buttons["dismiss-workout-keyboard"].tap()
        for _ in 0..<6 where !burpee.isHittable { app.swipeUp() }
        XCTAssertTrue(burpee.label.contains("Reported total: 19 reps (edited)"))
        let swing = app.buttons["movement-editor-0-1"]
        for _ in 0..<6 where !swing.isHittable { app.swipeUp() }
        XCTAssertTrue(swing.label.contains("Reported total: 72 reps"))
        for _ in 0..<6 where !burpee.isHittable { app.swipeDown() }
        burpee.tap()
        XCTAssertEqual(total.value as? String, "19")
        app.buttons["reset-reported-total"].tap()
        XCTAssertEqual(total.value as? String, "27")
        XCTAssertFalse(app.buttons["reset-reported-total"].exists)
        replaceText(total, with: "0")
        app.navigationBars["Movement"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(burpee.label.contains("Reported total: 0 reps (edited)"))
        app.buttons["review-and-save-workout"].tap()
        app.buttons["Save reviewed plan"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        openWork(in: app)
        let details = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workout-plan-details-")
        ).firstMatch
        for _ in 0..<6 where !details.isHittable { app.swipeUp() }
        details.tap()
        let corrected = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Reported total: 0 reps (edited)")
        ).firstMatch
        for _ in 0..<8 where !corrected.exists { app.swipeUp() }
        XCTAssertTrue(corrected.exists, "A corrected zero must survive saving and relaunching")
    }

    @MainActor
    func testDecimalMinutesResultsDuplicationAndLoadOptions() throws {
        let app = makeApp()
        app.launchEnvironment.removeValue(forKey: "WHOOPS_TEST_WORKOUT_MODEL")
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(
            "AMRAP 8 minutes\n4 Burpees\n12 Overhead Kettlebell Swings (35#)\nScore: 5 rounds, 3 reps"
        )
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let completedRounds = app.textFields["Completed rounds"]
        bringIntoInteractionZone(completedRounds, in: app)
        XCTAssertEqual(completedRounds.value as? String, "5")
        replaceText(completedRounds, with: "6")
        XCTAssertEqual(completedRounds.value as? String, "6")
        app.buttons["dismiss-workout-keyboard"].tap()
        let additionalReps = app.textFields["Additional reps"]
        bringIntoInteractionZone(additionalReps, in: app)
        XCTAssertTrue(additionalReps.waitForExistence(timeout: 5))
        XCTAssertEqual(additionalReps.value as? String, "3")

        let setup = app.buttons["segment-setup-0"]
        for _ in 0..<6 where !setup.isHittable { app.swipeUp() }
        setup.tap()
        XCTAssertTrue(app.navigationBars["Segment Setup"].waitForExistence(timeout: 5))
        let duration = app.textFields["Duration in minutes"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertEqual(duration.value as? String, "8")
        replaceText(duration, with: "6.25")
        XCTAssertEqual(duration.value as? String, "6.25")
        duration.typeText("9")
        XCTAssertEqual(duration.value as? String, "6.25", "Reject a third decimal place")
        app.navigationBars["Segment Setup"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        XCTAssertTrue(setup.label.contains("6.25 min"))

        let swing = app.buttons["movement-editor-0-1"]
        for _ in 0..<6 where !swing.isHittable { app.swipeUp() }
        XCTAssertTrue(swing.label.contains("Reported total: 72 reps"))
        swing.tap()
        let units = app.buttons["load-unit-picker"]
        for _ in 0..<6 where !units.isHittable { app.swipeUp() }
        XCTAssertTrue(units.waitForExistence(timeout: 5))
        units.tap()
        XCTAssertTrue(app.buttons["lbs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kg"].exists)
        app.buttons["kg"].tap()
        let duplicate = app.buttons["duplicate-movement"]
        for _ in 0..<6 where !duplicate.isHittable { app.swipeUp() }
        duplicate.tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        let copied = app.buttons["movement-editor-0-2"]
        for _ in 0..<6 where !copied.isHittable { app.swipeUp() }
        XCTAssertTrue(copied.waitForExistence(timeout: 5))
        XCTAssertTrue(copied.label.contains("12 reps · 35 kg"))
        copied.tap()
        let reps = app.textFields["Repetitions"]
        for _ in 0..<6 where !reps.isHittable { app.swipeUp() }
        replaceText(reps, with: "9")
        app.navigationBars["Movement"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        XCTAssertTrue(app.buttons["movement-editor-0-1"].label.contains("12 reps"))
        XCTAssertTrue(app.buttons["movement-editor-0-2"].label.contains("9 reps"))
        app.buttons["review-and-save-workout"].tap()
        XCTAssertTrue(app.buttons["Save reviewed plan"].waitForExistence(timeout: 5))
        app.buttons["Save reviewed plan"].tap()
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        let details = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workout-plan-details-")
        ).firstMatch
        for _ in 0..<6 where !details.isHittable { app.swipeUp() }
        details.tap()
        XCTAssertTrue(app.staticTexts["Reported result"].waitForExistence(timeout: 5))
        let minutes = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "6.25 min")
        ).firstMatch
        for _ in 0..<8 where !minutes.exists { app.swipeUp() }
        XCTAssertTrue(minutes.exists)
    }

    @MainActor
    private func replaceText(_ field: XCUIElement, with text: String) {
        // A native LabeledContent can expose the whole row as the field's AX frame.
        // Target its trailing numeric value, not the non-editable label in the middle.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).doubleTap()
        field.typeText(text)
    }

    @MainActor
    func testThreeJournalZonesAndSettingsGearAreVisible() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["zone-today"].exists)
        XCTAssertTrue(app.buttons["zone-work"].exists)
        XCTAssertTrue(app.buttons["zone-body"].exists)
        XCTAssertTrue(app.buttons["journal-settings"].exists)
    }

    @MainActor
    func testBodyMapZoomSelectsAndPersistsAnExplicitAffectedArea() throws {
        let app = makeApp()
        app.launch()
        app.buttons["zone-body"].tap()

        let editAreas = app.buttons["body-edit-affected-areas"]
        for _ in 0..<8 where !editAreas.isHittable { app.swipeUp() }
        XCTAssertTrue(editAreas.waitForExistence(timeout: 5))
        editAreas.tap()
        XCTAssertTrue(app.otherElements["body-area-picker"].waitForExistence(timeout: 5))

        if app.buttons["body-area-clear"].exists {
            app.buttons["body-area-clear"].tap()
        }
        let rightArm = app.buttons.matching(identifier: "body-focus-right.arm").firstMatch
        XCTAssertGreaterThanOrEqual(rightArm.frame.width, 44)
        XCTAssertGreaterThanOrEqual(rightArm.frame.height, 44)
        rightArm.tap()
        XCTAssertTrue(app.buttons["body-area-whole-body"].waitForExistence(timeout: 5))
        app.segmentedControls["body-map-view"].buttons["Back"].tap()

        let posteriorUpperArm = app.buttons["body-area-row-right.arm.upper-arm.back"]
        XCTAssertTrue(posteriorUpperArm.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(posteriorUpperArm.frame.height, 44)
        posteriorUpperArm.tap()

        app.buttons["body-area-add-another"].tap()
        let torso = app.buttons.matching(identifier: "body-focus-midline.torso").firstMatch
        XCTAssertTrue(torso.waitForExistence(timeout: 5))
        XCTAssertEqual(torso.value as? String, "Not selected")
        XCTAssertEqual(rightArm.value as? String, "Selected")
        torso.tap()
        XCTAssertEqual(
            app.buttons["body-area-row-midline.torso.upper-back"].value as? String,
            "Not selected")
        XCTAssertEqual(app.buttons["body-area-use"].label, "Use 1 area")
        captureJournal("BodyAreaPicker", app: app)
        app.buttons["body-area-use"].tap()

        XCTAssertTrue(app.otherElements["journal-page-body"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 mapped area"].waitForExistence(timeout: 5))
        editAreas.tap()
        XCTAssertTrue(app.buttons["body-area-clear"].waitForExistence(timeout: 5))
        app.buttons["body-area-cancel"].tap()
    }

    @MainActor
    func testMorningCheckInEntryIsAvailable() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["morning-check-in"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTrendsShowsDeterministicWeeklyReview() throws {
        let app = makeApp()
        app.launch()

        app.buttons["zone-body"].tap()

        XCTAssertTrue(app.otherElements["journal-page-body"].waitForExistence(timeout: 5))
        let review = app.buttons["weekly-review-link"]
        for _ in 0..<10 where !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.navigationBars["Weekly review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Most important change"].exists)
        XCTAssertTrue(app.staticTexts["What coincided"].exists)
        XCTAssertTrue(app.staticTexts["Next action"].exists)
        captureJournal("WeeklyReview", app: app)
    }

    @MainActor
    func testExperimentLabOpensWhenFeatureFlagIsEnabled() throws {
        let app = makeApp()
        app.launchEnvironment["WHOOPS_ENABLE_EXPERIMENT_LAB"] = "1"
        app.launch()
        app.buttons["zone-body"].tap()
        let lab = app.buttons["experiment-lab-link"]
        for _ in 0..<12 where !lab.isHittable { app.swipeUp() }
        XCTAssertTrue(lab.waitForExistence(timeout: 5))
        lab.tap()
        XCTAssertTrue(app.navigationBars["Experiment Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-experiment"].exists)
        XCTAssertTrue(staticText("One daily check-in", in: app).exists)
        XCTAssertTrue(app.buttons["log-experiment-day"].exists)
        captureJournal("ExperimentLab", app: app)
        app.buttons["new-experiment"].tap()
        XCTAssertTrue(app.textFields["Short title"].waitForExistence(timeout: 5))
        captureJournal("ExperimentEditor", app: app)
    }

    @MainActor
    func testWorkoutCanBePastedAndReviewed() throws {
        let app = makeApp()
        app.launch()

        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let reviewAndSave = app.buttons["review-and-save-workout"]
        XCTAssertTrue(reviewAndSave.waitForExistence(timeout: 5))
        reviewAndSave.tap()
        XCTAssertTrue(app.buttons["Save reviewed plan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavedWorkoutCardOpensReadOnlyDetails() throws {
        let app = makeApp()
        app.launch()

        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        app.buttons["review-and-save-workout"].tap()
        let save = app.buttons["Save reviewed plan"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))
        app.swipeUp()
        let details = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "workout-plan-details-")
        ).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        if !details.isHittable { app.swipeUp() }
        details.tap()

        XCTAssertTrue(staticText("Workout overview", in: app).waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(staticText("Segment 1 · Work", in: app).waitForExistence(timeout: 5))
        let prescription = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "planned-movement-prescription-"
            )
        ).firstMatch
        if !prescription.exists { app.swipeUp() }
        XCTAssertTrue(prescription.waitForExistence(timeout: 5))
        XCTAssertTrue(prescription.label.contains("10 reps"))
        captureJournal("PlannedWorkout", app: app)
        XCTAssertTrue(prescription.label.contains("45 lb"))
    }

    @MainActor
    func testSpelledOutAMRAPShowsPrescriptionsAndSeparateReportedScore() throws {
        let app = makeApp()
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(
            """
            Complete as many rounds as possible in 8 minutes
            - 4 Burpees
            - 12 Overhead Kettlebell Swings (35#)
            Score: 5 rounds, 3 reps
            """)
        tapParseWorkout(in: app)

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        XCTAssertFalse(staticText("Parser notes", in: app).exists)
        let segment = app.buttons["segment-setup-0"]
        for _ in 0..<5 where !segment.isHittable { app.swipeUp() }
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        XCTAssertFalse(segment.label.contains("5 rounds"))
        XCTAssertEqual(app.textFields["Completed rounds"].value as? String, "5")
        XCTAssertEqual(app.textFields["Additional reps"].value as? String, "3")

        segment.tap()
        XCTAssertTrue(app.navigationBars["Segment Setup"].waitForExistence(timeout: 5))
        let rounds = app.textFields["Prescribed rounds"]
        XCTAssertTrue(rounds.waitForExistence(timeout: 5))
        XCTAssertNotEqual(rounds.value as? String, "5")
        XCTAssertEqual(app.textFields["Duration in minutes"].value as? String, "8")
        app.navigationBars["Segment Setup"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))

        let burpee = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Burpee", "4 reps")
        ).firstMatch
        let swing = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "Overhead kettlebell swing", "12 reps · 35 lb"
            )
        ).firstMatch
        for _ in 0..<4 where !swing.isHittable { app.swipeUp() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(burpee.exists)
        XCTAssertTrue(swing.exists)
    }

    @MainActor
    func testPopulatedWorkoutFieldsKeepVisibleLabels() throws {
        let app = makeApp()
        app.launch()

        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(
            "60 Cal Echo Bike\nRest 90 sec\n52 Cal Echo Bike\n\nIntensity: RPE 8-9"
        )
        tapParseWorkout(in: app)

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let segmentSetup = app.buttons["segment-setup-0"]
        for _ in 0..<12 where !segmentSetup.isHittable { app.swipeUp() }
        XCTAssertTrue(segmentSetup.waitForExistence(timeout: 5))
        segmentSetup.tap()

        let restField = app.textFields["Rest between efforts in minutes"]
        XCTAssertTrue(restField.waitForExistence(timeout: 5))
        XCTAssertEqual(restField.value as? String, "1.5")
        let notesField = app.textFields["Notes and targets"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            notesField.value as? String,
            "Intensity: RPE 8-9"
        )
    }

    @MainActor
    func testRestSegmentUsesOneDurationWithoutWorkFields() throws {
        let app = makeApp()
        app.launch()

        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let addRest = app.buttons["add-rest-segment"]
        app.swipeUp()
        XCTAssertTrue(addRest.waitForExistence(timeout: 5))
        addRest.tap()

        let restSetup = app.buttons["segment-setup-1"]
        XCTAssertTrue(restSetup.waitForExistence(timeout: 5))
        if !restSetup.isHittable { app.swipeUp() }
        restSetup.tap()

        let duration = app.textFields["Rest duration in minutes"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Prescribed rounds"].exists)
        XCTAssertFalse(app.textFields["Rest between efforts in minutes"].exists)
        duration.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        duration.typeText("1.5")
        XCTAssertEqual(duration.value as? String, "1.5")
    }

    @MainActor
    func testDocketShowsWindDownAndCompletesWithUndo() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(staticText("The Docket", in: app).waitForExistence(timeout: 5))
        let windDown = app.buttons["docket-item-wind_down:sleep"]
        XCTAssertTrue(windDown.waitForExistence(timeout: 5))
        for _ in 0..<16 where !windDown.isHittable { app.swipeUp() }
        XCTAssertTrue(windDown.isHittable)
        if windDown.label.hasSuffix(", completed") {
            windDown.tap()
        }

        windDown.tap()
        let undo = app.buttons["docket-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertFalse(undo.waitForExistence(timeout: 2))
    }

    @MainActor
    func testProtocolPastePathReachesTapChipReview() throws {
        let app = XCUIApplication()
        app.launch()

        openWork(in: app)
        let workoutEntry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(workoutEntry.waitForExistence(timeout: 5))
        workoutEntry.tap()
        workoutEntry.typeText("5 Burpees")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let newProtocol = app.buttons["new-protocol"]
        XCTAssertTrue(newProtocol.waitForExistence(timeout: 5))
        if !newProtocol.isHittable { app.swipeDown() }
        newProtocol.tap()

        let pasteLink = app.buttons["protocol-paste-link"]
        XCTAssertTrue(pasteLink.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        captureJournal("Capture", app: app)
        pasteLink.tap()

        let entry = app.textViews["protocol-paste-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("Ring row 3x10")
        app.buttons["protocol-paste-use"].tap()

        XCTAssertTrue(app.staticTexts["found 1 movement."].waitForExistence(timeout: 5))
        captureJournal("ParseReview", app: app)
        let save = app.buttons["protocol-review-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
    }

    @MainActor
    func testPersonalMovementCanBeStartedFromLibrary() throws {
        let app = makeApp()
        app.launch()

        openWork(in: app)
        let library = app.buttons["movement-library-link"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        XCTAssertTrue(app.navigationBars["Your Movements"].waitForExistence(timeout: 5))
        app.buttons["add-movement"].tap()
        XCTAssertTrue(app.navigationBars["New Movement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["movement-name"].exists)
        XCTAssertTrue(app.buttons["save-movement"].exists)
        captureJournal("MovementEditor", app: app)
    }

    @MainActor
    func testMovementLibraryToolbarUsesClearMenuLabels() throws {
        let app = makeApp()
        app.launch()

        openWork(in: app)
        let library = app.buttons["movement-library-link"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        XCTAssertTrue(app.navigationBars["Your Movements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-movement"].exists)
        let more = app.buttons["movement-library-more"]
        XCTAssertTrue(more.exists)
        more.tap()

        XCTAssertTrue(app.buttons["Import movements from WOD Lab…"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Show archived movements ('")
            ).firstMatch.exists
        )
    }

    @MainActor
    func testAppleDraftShowsProvenanceAndFallbackIsExplicit() throws {
        let app = makeApp(appleEnabled: true)
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "fixture"
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_OUTPUT"] =
            #"{"format":"manual","segments":[{"kind":"work","contextLines":[],"movements":[{"line":1,"name":"Strict Press","reps":"10","load":"45 lb"}]}]}"#
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Parsed with Apple Intelligence · On device"].exists)
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "unavailable"
        app.launch()
        openWork(in: app)
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Built-in parser used"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSlowAppleParsingCanBeCancelledAndManualEntryStillWorks() throws {
        let app = makeApp(appleEnabled: true)
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "slow"
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)
        let cancel = app.buttons["cancel-workout-parsing"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["parse-workout"].isEnabled)
        XCTAssertEqual(entry.value as? String, "10 Strict Press 45 lb")
        app.buttons["Enter manually"].tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDisabledAppleParsingSkipsSlowProvider() throws {
        let app = makeApp()
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "slow"
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Parsed with the built-in parser or entered manually"].exists)
        XCTAssertFalse(app.staticTexts["Built-in parser used"].exists)
    }

    @MainActor
    func testNormalRunUsesBuiltInParserDespiteStoredAppleOptIn() throws {
        let app = makeApp(appleEnabled: true)
        app.launchEnvironment.removeValue(forKey: "WHOOPS_TEST_WORKOUT_MODEL")
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["apple-workout-parsing-toggle"].exists)
        XCTAssertTrue(app.staticTexts["Parsed locally with the built-in parser."].exists)
        entry.tap()
        entry.typeText("8 Burpees")
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Parsed with the built-in parser or entered manually"].exists)
        XCTAssertFalse(app.staticTexts["Built-in parser used"].exists)
        XCTAssertFalse(app.staticTexts["Parsed with Apple Intelligence · On device"].exists)
    }

    @MainActor
    private func openWork(in app: XCUIApplication) {
        app.buttons["zone-work"].tap()
        let entry = app.textViews["raw-workout-entry"]
        if !entry.exists {
            let composer = app.buttons["workout-composer"]
            for _ in 0..<15 where !composer.isHittable { app.swipeUp() }
            XCTAssertTrue(composer.waitForExistence(timeout: 5))
            composer.tap()
        }
        for _ in 0..<15 where !entry.isHittable { app.swipeUp() }
    }

    @MainActor
    func testJournalProtocolReviewMirrorsMarginAndKeepsCadenceReadable() throws {
        let app = makeApp()
        app.launchArguments += ["-journalLeftHanded", "YES"]
        app.launch()
        app.buttons["zone-work"].tap()
        let capture = app.buttons["new-protocol"]
        for _ in 0..<15 where !capture.isHittable { app.swipeUp() }
        capture.tap()
        app.buttons["protocol-paste-link"].tap()
        let entry = app.textViews["protocol-paste-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("Ring row 3x10")
        app.buttons["protocol-paste-use"].tap()
        XCTAssertTrue(app.staticTexts["found 1 movement."].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.staticTexts["new protocol"].frame.minX, 40)
        let daily = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "cadence-daily-")
        ).firstMatch
        XCTAssertTrue(daily.isHittable)
        XCTAssertLessThanOrEqual(
            daily.frame.height, 60, "Cadence words should not split into letters")
        captureJournal("ParseReview-LeftHanded", app: app)
    }

    @MainActor
    func testJournalKeepsDetailedReadinessAndDiagnosticsReachable() throws {
        let app = makeApp()
        app.launch()
        let details = app.buttons["readiness-details"]
        for _ in 0..<15 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        // LabeledContent is one accessibility element ("Confidence, Low"), not a
        // standalone label. Match the label prefix without depending on the score.
        let confidence = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Confidence,")
        ).firstMatch
        for _ in 0..<10 where !confidence.isHittable { app.swipeUp() }
        XCTAssertTrue(confidence.exists)
        captureJournal("ReadinessDetails", app: app)
        let backend = app.buttons["check-backend"]
        for _ in 0..<20 where !backend.isHittable { app.swipeUp() }
        XCTAssertTrue(backend.isHittable)
        XCTAssertTrue(app.staticTexts["backend-status"].exists)
    }

    @MainActor
    func testJournalBottomActionScrollsClearOfNavigationAndOpens() throws {
        for largeText in [false, true] {
            let app = makeApp()
            if largeText {
                app.launchArguments += [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL",
                ]
            }
            app.launch()
            openWork(in: app)
            if largeText {
                let title = app.staticTexts.matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "completed-workout-summary-title-", "editable workout")
                ).firstMatch
                if title.exists {
                    // Populated history must not squeeze large-type titles beside the date.
                    // Accessibility reports the glyph bounds, not the full proposed frame.
                    XCTAssertGreaterThanOrEqual(title.frame.width, app.frame.width * 0.65)
                }
            }
            let library = app.buttons["movement-library-link"]
            scrollAboveJournalNavigation(library, in: app)
            captureJournal(largeText ? "Work-Bottom-LargeText" : "Work-Bottom", app: app)
            // A coordinate tap cannot auto-scroll an obscured accessibility element into view.
            library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["Your Movements"].waitForExistence(timeout: 5))
            captureJournal(largeText ? "Library-LargeText" : "Library", app: app)
            app.terminate()
        }
    }

    @MainActor
    private func scrollAboveJournalNavigation(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<24 {
            let bottom = app.buttons["zone-work"].frame.minY - 18
            if element.isHittable && element.frame.maxY <= bottom && element.frame.minY >= 100 {
                break
            }
            // Use the paper margin: a drag inside the nested workout TextEditor scrolls
            // the editor instead of the page, depending on its position in populated history.
            let above = !element.frame.isEmpty && element.frame.minY < 100
            let start = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.08, dy: above ? 0.28 : 0.72))
            let end = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.08, dy: above ? 0.72 : 0.28))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !element.isHittable {
            captureJournal("BottomAction-Unreachable", app: app)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThanOrEqual(element.frame.maxY, app.buttons["zone-work"].frame.minY - 18)
        XCTAssertGreaterThanOrEqual(element.frame.minY, 100)
    }

    @MainActor
    func testJournalSecondarySettingsAndBodyScreensAreReachable() throws {
        let app = makeApp()
        app.launch()
        app.buttons["journal-settings"].tap()
        let restrictions = app.buttons["settings-restrictions"]
        for _ in 0..<12 where !restrictions.isHittable { app.swipeUp() }
        restrictions.tap()
        XCTAssertTrue(app.navigationBars["Restrictions"].waitForExistence(timeout: 5))
        captureJournal("Restrictions", app: app)
        let injury = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Right distal triceps")
        ).firstMatch
        for _ in 0..<10 where !injury.isHittable { app.swipeUp() }
        injury.tap()
        XCTAssertTrue(app.navigationBars["Restriction"].waitForExistence(timeout: 5))
        captureJournal("RestrictionEditor", app: app)
        app.navigationBars["Restriction"].buttons["Cancel"].tap()
        app.navigationBars["Restrictions"].buttons.element(boundBy: 0).tap()
        let sleep = app.buttons["Sleep schedule"]
        for _ in 0..<10 where !sleep.isHittable { app.swipeUp() }
        sleep.tap()
        XCTAssertTrue(app.navigationBars["Sleep Schedule"].waitForExistence(timeout: 5))
        captureJournal("SleepSchedule", app: app)
        let save = app.buttons["Save schedule"]
        for _ in 0..<10
        where !save.isHittable || save.frame.maxY > app.frame.maxY - 44 { app.swipeUp() }
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 5))
        let reset = app.buttons["Reset to default schedule"]
        for _ in 0..<10
        where !reset.isHittable || reset.frame.maxY > app.frame.maxY - 44 { app.swipeUp() }
        reset.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Reset to defaults"].waitForExistence(timeout: 3))
        captureJournal("SleepResetConfirmation", app: app)
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // iOS 26 may anchor the confirmation in a popover without a Cancel row.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)).tap()
        }
        app.navigationBars["Sleep Schedule"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let reminders = app.buttons["settings-reminders"]
        for _ in 0..<10 where !reminders.isHittable { app.swipeUp() }
        reminders.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["morning-reminder-toggle"].exists)
        XCTAssertTrue(app.switches["wind-down-reminder-toggle"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Time").count, 2)
        captureJournal("Reminders", app: app)
        app.navigationBars["Reminders"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["close-settings"].tap()
        app.buttons["zone-body"].tap()
        let trends = app.buttons["all-trends-link"]
        scrollAboveJournalNavigation(trends, in: app)
        trends.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Trends & export"].waitForExistence(timeout: 5))
        captureJournal("TrendsExport", app: app)
    }

    @MainActor
    func testJournalNavigationSettingsAndVisualStates() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["today-verdict"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Only journal navigation should be exposed")
        for name in ["today", "work", "body"] {
            let zone = app.buttons["zone-" + name]
            XCTAssertGreaterThanOrEqual(zone.frame.width, 44)
            XCTAssertGreaterThanOrEqual(zone.frame.height, 44)
        }
        captureJournal("Today", app: app)
        app.buttons["morning-check-in"].tap()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))
        captureJournal("CheckIn", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["zone-work"].tap()
        XCTAssertTrue(app.buttons["new-protocol"].waitForExistence(timeout: 5))
        captureJournal("Work", app: app)
        app.buttons["zone-body"].tap()
        XCTAssertTrue(app.buttons["choose-restriction"].waitForExistence(timeout: 5))
        captureJournal("Body", app: app)
        app.buttons["journal-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let handedness = app.switches["journal-left-handed"]
        bringIntoInteractionZone(handedness, in: app)
        captureJournal("Settings", app: app)
        if handedness.value as? String == "0" {
            handedness.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        app.buttons["close-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        XCTAssertLessThan(
            app.buttons["journal-settings"].frame.midX, app.buttons["zone-today"].frame.midX)
        captureJournal("LeftHanded", app: app)
        app.buttons["journal-settings"].tap()
        bringIntoInteractionZone(handedness, in: app)
        handedness.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["close-settings"].tap()
        XCTAssertGreaterThan(
            app.buttons["journal-settings"].frame.midX, app.buttons["zone-today"].frame.midX)
    }

    @MainActor
    private func bringIntoInteractionZone(_ element: XCUIElement, in app: XCUIApplication) {
        let lowestSafeY = app.frame.maxY - 160
        for _ in 0..<12 {
            if element.exists, element.frame.minY >= 100, element.frame.maxY <= lowestSafeY {
                return
            }
            app.swipeUp()
        }
    }

    @MainActor
    private func captureJournal(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Journal-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testJournalSupportsAccessibilityTextSize() throws {
        let app = makeApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["zone-work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["journal-settings"].isHittable)
        for name in ["today", "work", "body"] {
            let zone = app.buttons["zone-" + name]
            XCTAssertGreaterThanOrEqual(zone.frame.width, 44)
            XCTAssertLessThanOrEqual(
                zone.frame.height, 70, "Zone labels must not wrap into letters")
        }
        captureJournal("Today-LargeText", app: app)
        let checkIn = app.buttons["morning-check-in"]
        for _ in 0..<10 where !checkIn.isHittable { app.swipeUp() }
        checkIn.tap()
        let save = app.buttons["check-in-save"]
        for _ in 0..<20 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        captureJournal("CheckIn-LargeText", app: app)
        app.buttons["Cancel"].tap()
        app.buttons["zone-work"].tap()
        captureJournal("Work-LargeText", app: app)
        app.buttons["zone-body"].tap()
        captureJournal("Body-LargeText", app: app)
    }

    @MainActor
    private func makeApp(appleEnabled: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-appleWorkoutParsingEnabled", appleEnabled ? "YES" : "NO"]
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "unavailable"
        return app
    }

    @MainActor
    private func staticText(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label ==[c] %@", label)
        ).firstMatch
    }

    @MainActor
    func testMorningCheckInUsesChipsNotSliders() throws {
        let app = makeApp()
        app.launch()
        app.buttons["morning-check-in"].tap()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.sliders.firstMatch.waitForNonExistence(timeout: 2))

        let painChip = app.buttons["checkin-pain-at-rest-chip-3"]
        for _ in 0..<6 where !painChip.isHittable { app.swipeUp() }
        XCTAssertTrue(painChip.waitForExistence(timeout: 5))
        painChip.tap()
        XCTAssertTrue(painChip.isSelected)

        app.buttons["check-in-save"].tap()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testRecordActualWorkoutUsesChipsNotNumberPads() throws {
        let app = makeApp()
        app.launch()
        openWork(in: app)
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("AMRAP 8 minutes\n4 Burpees\nScore: 5 rounds, 3 reps")
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        app.buttons["review-and-save-workout"].tap()
        app.buttons["Save reviewed plan"].tap()
        let actual = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "record-actual-workout-")
        ).firstMatch
        for _ in 0..<8 where !actual.isHittable { app.swipeUp() }
        actual.tap()
        XCTAssertTrue(app.navigationBars["Record Actual Work"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)

        XCTAssertFalse(app.textFields["Actual repetitions"].exists)

        let rpeChip = app.buttons["session-rpe-chip-7"]
        for _ in 0..<6 where !rpeChip.isHittable { app.swipeUp() }
        for _ in 0..<4 where !rpeChip.isHittable { app.swipeLeft() }
        rpeChip.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))

        let painChip = app.buttons["post-session-pain-chip-2"]
        for _ in 0..<6 where !painChip.isHittable { app.swipeUp() }
        painChip.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testDocketProtocolItemLogsAsPrescribedAndOpensRecordActual() throws {
        let app = XCUIApplication()
        app.launch()
        pasteRingRowProtocol(in: app)

        let row = ringRowDocketRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        if row.label.hasSuffix(", completed") {
            row.tap()
        }

        row.tap()
        let undo = app.buttons["docket-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))

        let recordActual = app.buttons[recordActualIdentifier(for: row)]
        for _ in 0..<16 where !recordActual.isHittable { app.swipeUp() }
        XCTAssertTrue(recordActual.waitForExistence(timeout: 5))
        recordActual.tap()

        let asPrescribed = app.buttons["record-actual-as-prescribed"]
        XCTAssertTrue(asPrescribed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["3×10"].exists, "The title already includes this quantity")
        captureJournal("RecordActual", app: app)
        asPrescribed.tap()
        XCTAssertTrue(asPrescribed.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testDocketRecordActualPainChipIsUnselectedByDefault() throws {
        let app = XCUIApplication()
        app.launch()
        pasteRingRowProtocol(in: app)

        let row = ringRowDocketRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let recordActual = app.buttons[recordActualIdentifier(for: row)]
        XCTAssertTrue(recordActual.waitForExistence(timeout: 5))
        recordActual.tap()

        XCTAssertTrue(app.buttons["record-actual-as-prescribed"].waitForExistence(timeout: 5))
        let painChips = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "record-actual-pain-")
        )
        XCTAssertGreaterThan(painChips.count, 0)
        for index in 0..<painChips.count {
            XCTAssertFalse(painChips.element(boundBy: index).isSelected)
        }
    }

    @MainActor
    func testRecordActualControlsMeetTapTargetSize() throws {
        let app = XCUIApplication()
        app.launch()
        pasteRingRowProtocol(in: app)

        let row = ringRowDocketRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let recordActual = app.buttons[recordActualIdentifier(for: row)]
        XCTAssertTrue(recordActual.waitForExistence(timeout: 5))
        recordActual.tap()

        let painChip = app.buttons["record-actual-pain-3"]
        XCTAssertTrue(painChip.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(painChip.frame.height, 44)

        let setsPlus = app.buttons["record-actual-sets-plus"]
        XCTAssertTrue(setsPlus.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(setsPlus.frame.height, 44)
    }

    /// Reaches Today with at least one "ring row 3x10" protocol item on the docket,
    /// via the same paste path `testProtocolPastePathReachesTapChipReview` proves.
    /// Tolerates an already-present protocol row from an earlier run rather than
    /// assuming a clean store — pasting again just adds another equivalent row.
    @MainActor
    private func pasteRingRowProtocol(in app: XCUIApplication) {
        openWork(in: app)
        let workoutEntry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(workoutEntry.waitForExistence(timeout: 5))
        workoutEntry.tap()
        workoutEntry.typeText("5 Burpees")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let newProtocol = app.buttons["new-protocol"]
        XCTAssertTrue(newProtocol.waitForExistence(timeout: 5))
        if !newProtocol.isHittable { app.swipeDown() }
        newProtocol.tap()

        let pasteLink = app.buttons["protocol-paste-link"]
        XCTAssertTrue(pasteLink.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        pasteLink.tap()

        let entry = app.textViews["protocol-paste-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText("Ring row 3x10")
        app.buttons["protocol-paste-use"].tap()

        XCTAssertTrue(app.staticTexts["found 1 movement."].waitForExistence(timeout: 5))
        let save = app.buttons["protocol-review-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        // Saving reloads Train's data before the capture flow dismisses itself;
        // wait for that dismissal to complete before the tab bar is interactable.
        XCTAssertTrue(app.otherElements["journal-page-work"].waitForExistence(timeout: 5))

        app.buttons["zone-today"].tap()
        XCTAssertTrue(staticText("The Docket", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func ringRowDocketRow(in app: XCUIApplication) -> XCUIElement {
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "docket-item-protocol_item:")
        ).matching(NSPredicate(format: "label CONTAINS[c] %@", "ring row")).firstMatch
        for _ in 0..<16 where !row.isHittable { app.swipeUp() }
        return row
    }

    /// Derives a protocol row's "log details" button identifier from its own
    /// `docket-item-<item.id>` identifier, since the item id is a fresh UUID
    /// minted at parse time and can't be known ahead of the paste.
    @MainActor
    private func recordActualIdentifier(for row: XCUIElement) -> String {
        row.identifier.replacingOccurrences(of: "docket-item-", with: "docket-record-actual-")
    }
}
