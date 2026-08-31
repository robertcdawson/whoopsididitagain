import XCTest

final class WhoopsAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompletedWorkoutFieldsCanBeEditedCancelledAndReopened() throws {
        let app = makeApp()
        let workoutTitle = "Editable " + UUID().uuidString.prefix(6)
        app.launch()
        app.tabBars.buttons["Train"].tap()
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
        replaceWholeField(app.textFields["Workout title"], with: workoutTitle, in: app)
        app.buttons["save-actual-workout"].tap()
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        let detailLink = app.buttons["View completed workout: \(workoutTitle)"]
        for _ in 0..<10 where !detailLink.isHittable { app.swipeUp() }
        detailLink.tap()
        XCTAssertTrue(app.buttons["edit-completed-workout"].waitForExistence(timeout: 5))
        app.buttons["edit-completed-workout"].tap()
        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Workout title"].value as? String, workoutTitle)
        XCTAssertTrue(app.datePickers["workout-started-at"].exists)
        XCTAssertTrue(app.datePickers["workout-ended-at"].exists)
        let duration = app.textFields["Session duration in minutes"]
        for _ in 0..<6 where !duration.isHittable { app.swipeUp() }
        replaceText(duration, with: "30.25")
        app.buttons["dismiss-workout-keyboard"].tap()
        XCTAssertEqual(duration.value as? String, "30.25")
        let rpe = app.steppers["session-rpe"]
        for _ in 0..<6 where !rpe.isHittable { app.swipeUp() }
        rpe.buttons["session-rpe-Increment"].tap()
        rpe.buttons["session-rpe-Increment"].tap()
        let pain = app.steppers["post-session-pain"]
        for _ in 0..<6 where !pain.isHittable { app.swipeUp() }
        pain.buttons["post-session-pain-Increment"].tap()
        pain.buttons["post-session-pain-Increment"].tap()
        let rounds = app.textFields["Completed rounds"]
        for _ in 0..<8 where !rounds.isHittable { app.swipeUp() }
        replaceText(rounds, with: "6")
        app.buttons["dismiss-workout-keyboard"].tap()
        let reps = app.textFields["Actual repetitions"].firstMatch
        for _ in 0..<8 where !reps.isHittable { app.swipeUp() }
        replaceText(reps, with: "17")
        app.buttons["dismiss-workout-keyboard"].tap()
        let load = app.textFields["Actual load"].firstMatch
        for _ in 0..<6 where !load.isHittable { app.swipeUp() }
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
        replaceWholeField(app.textFields["Workout title"], with: "Cancelled edit", in: app)
        app.navigationBars["Edit Workout"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars[workoutTitle].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Train"].tap()
        for _ in 0..<10 where !detailLink.isHittable { app.swipeUp() }
        XCTAssertEqual(
            app.buttons.matching(identifier: "View completed workout: \(workoutTitle)").count, 1)
        detailLink.tap()
        app.buttons["edit-completed-workout"].tap()
        XCTAssertEqual(duration.value as? String, "30.25")
        for _ in 0..<8 where !rounds.isHittable { app.swipeUp() }
        XCTAssertEqual(rounds.value as? String, "6")
        for _ in 0..<8 where !reps.isHittable { app.swipeUp() }
        XCTAssertEqual(reps.value as? String, "17")
        for _ in 0..<6 where !load.isHittable { app.swipeUp() }
        XCTAssertEqual(load.value as? String, "12.5")
    }

    @MainActor
    func testSavedPlanHasAnEditActionAndEditableScheduleAndEstimates() throws {
        let app = makeApp()
        app.launch()
        app.tabBars.buttons["Train"].tap()
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
        // A labeled field's accessibility frame includes its label. Tap the trailing value.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let existing = (field.value as? String) ?? ""
        field.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + text)
        XCTAssertEqual(field.value as? String, text)
    }

    @MainActor
    func testSharedKeyboardDismissalPreservesMultilineNotes() throws {
        let app = makeApp()
        app.launch()
        app.buttons["morning-check-in"].tap()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))
        let notes = app.textFields["check-in-notes"]
        for _ in 0..<6 where !notes.isHittable { app.swipeUp() }
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
        for _ in 0..<6 where !notes.isHittable { app.swipeUp() }
        notes.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Morning Check-In"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        app.navigationBars["Morning Check-In"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
    }

    @MainActor
    func testWorkoutKeyboardDismissesOnSubmitCancelSaveAndTabChanges() throws {
        let app = makeApp()
        app.launch()
        app.tabBars.buttons["Train"].tap()
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
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)

        for _ in 0..<6
        where entry.frame.minY < app.navigationBars["Train"].frame.maxY + 16 { app.swipeDown() }
        entry.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        // The software keyboard covers the tab bar; finish editing before tapping a tab.
        app.buttons["dismiss-workout-keyboard"].tap()
        assertKeyboardHidden(in: app)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)
        app.tabBars.buttons["Train"].tap()
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
        assertKeyboardHidden(in: app)

        let actual = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "record-actual-workout-")
        ).firstMatch
        for _ in 0..<8 where !actual.isHittable { app.swipeUp() }
        actual.tap()
        XCTAssertTrue(app.navigationBars["Record Actual Work"].waitForExistence(timeout: 5))
        let reps = app.textFields["Actual repetitions"].firstMatch
        for _ in 0..<6 where !reps.isHittable { app.swipeUp() }
        replaceText(reps, with: "18")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["save-actual-workout"].tap()
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
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
        // XCUITest can consider a control hittable while the keyboard accessory overlaps it.
        if app.keyboards.firstMatch.exists
            && parse.frame.maxY > app.keyboards.firstMatch.frame.minY - 100
        {
            app.buttons["dismiss-workout-keyboard"].tap()
            assertKeyboardHidden(in: app)
        }
        parse.tap()
    }

    @MainActor
    func testReportedMovementTotalsCanBeCorrectedResetAndReopened() throws {
        let app = makeApp()
        app.launch()
        app.tabBars.buttons["Train"].tap()
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
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Train"].tap()
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
        app.tabBars.buttons["Train"].tap()
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(
            "AMRAP 8 minutes\n4 Burpees\n12 Overhead Kettlebell Swings (35#)\nScore: 5 rounds, 3 reps"
        )
        tapParseWorkout(in: app)
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let completedRounds = app.textFields["Completed rounds"]
        for _ in 0..<6 where !completedRounds.isHittable { app.swipeUp() }
        XCTAssertEqual(completedRounds.value as? String, "5")
        XCTAssertEqual(app.textFields["Additional reps"].value as? String, "3")
        replaceText(completedRounds, with: "6")
        XCTAssertEqual(completedRounds.value as? String, "6")
        app.buttons["dismiss-workout-keyboard"].tap()

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
        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
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
        field.doubleTap()
        field.typeText(text)
    }

    @MainActor
    func testFourTabShellIsVisible() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Train"].exists)
        XCTAssertTrue(app.tabBars.buttons["Trends"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
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

        app.tabBars.buttons["Trends"].tap()

        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        XCTAssertTrue(staticText("Weekly review", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Most important change"].exists)
        XCTAssertTrue(app.staticTexts["What coincided"].exists)
        XCTAssertTrue(app.staticTexts["Next action"].exists)
    }

    @MainActor
    func testExperimentLabOpensWhenFeatureFlagIsEnabled() throws {
        let app = makeApp()
        app.launchEnvironment["WHOOPS_ENABLE_EXPERIMENT_LAB"] = "1"
        app.launch()
        app.tabBars.buttons["Trends"].tap()
        let lab = app.buttons["experiment-lab-link"]
        for _ in 0..<8 where !lab.exists { app.swipeUp() }
        XCTAssertTrue(lab.waitForExistence(timeout: 5))
        lab.tap()
        XCTAssertTrue(app.navigationBars["Experiment Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-experiment"].exists)
        XCTAssertTrue(staticText("One daily check-in", in: app).exists)
        XCTAssertTrue(app.buttons["log-experiment-day"].exists)
    }

    @MainActor
    func testWorkoutCanBePastedAndReviewed() throws {
        let app = makeApp()
        app.launch()

        app.tabBars.buttons["Train"].tap()
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

        app.tabBars.buttons["Train"].tap()
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

        XCTAssertTrue(app.navigationBars["Train"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(prescription.label.contains("45 lb"))
    }

    @MainActor
    func testSpelledOutAMRAPShowsPrescriptionsAndSeparateReportedScore() throws {
        let app = makeApp()
        app.launch()
        app.tabBars.buttons["Train"].tap()
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

        app.tabBars.buttons["Train"].tap()
        let entry = app.textViews["raw-workout-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(
            "60 Cal Echo Bike\nRest 90 sec\n52 Cal Echo Bike\n\nIntensity: RPE 8-9"
        )
        tapParseWorkout(in: app)

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let segmentSetup = app.buttons["segment-setup-0"]
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

        app.tabBars.buttons["Train"].tap()
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

        XCTAssertTrue(app.staticTexts["The Docket"].waitForExistence(timeout: 5))
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

        app.tabBars.buttons["Train"].tap()
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
        XCTAssertTrue(save.isEnabled)
    }

    @MainActor
    func testPersonalMovementCanBeStartedFromLibrary() throws {
        let app = makeApp()
        app.launch()

        app.tabBars.buttons["Train"].tap()
        let library = app.buttons["movement-library-link"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        XCTAssertTrue(app.navigationBars["Your Movements"].waitForExistence(timeout: 5))
        app.buttons["add-movement"].tap()
        XCTAssertTrue(app.navigationBars["New Movement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["movement-name"].exists)
        XCTAssertTrue(app.buttons["save-movement"].exists)
    }

    @MainActor
    func testAppleDraftShowsProvenanceAndFallbackIsExplicit() throws {
        let app = makeApp(appleEnabled: true)
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "fixture"
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_OUTPUT"] =
            #"{"format":"manual","segments":[{"kind":"work","contextLines":[],"movements":[{"line":1,"name":"Strict Press","reps":"10","load":"45 lb"}]}]}"#
        app.launch()
        app.tabBars.buttons["Train"].tap()
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
        app.tabBars.buttons["Train"].tap()
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
        app.tabBars.buttons["Train"].tap()
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
        app.tabBars.buttons["Train"].tap()
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
        app.tabBars.buttons["Train"].tap()
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
}
