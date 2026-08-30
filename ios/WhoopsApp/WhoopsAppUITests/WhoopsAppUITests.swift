import XCTest

final class WhoopsAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
        app.buttons["parse-workout"].tap()

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
        app.buttons["parse-workout"].tap()

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
        app.buttons["parse-workout"].tap()

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        XCTAssertFalse(staticText("Parser notes", in: app).exists)
        let segment = app.buttons["segment-setup-0"]
        for _ in 0..<5 where !segment.isHittable { app.swipeUp() }
        XCTAssertTrue(segment.waitForExistence(timeout: 5))
        XCTAssertFalse(segment.label.contains("5 rounds"))
        let score = staticText(
            "Reported result (not a prescription): Score: 5 rounds, 3 reps", in: app)
        XCTAssertTrue(score.exists)

        segment.tap()
        XCTAssertTrue(app.navigationBars["Segment Setup"].waitForExistence(timeout: 5))
        let rounds = app.textFields["Rounds"]
        XCTAssertTrue(rounds.waitForExistence(timeout: 5))
        XCTAssertNotEqual(rounds.value as? String, "5")
        XCTAssertEqual(app.textFields["Duration in seconds"].value as? String, "480")
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
        app.buttons["parse-workout"].tap()

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let segmentSetup = app.buttons["segment-setup-0"]
        XCTAssertTrue(segmentSetup.waitForExistence(timeout: 5))
        segmentSetup.tap()

        let restField = app.textFields["Rest between efforts in seconds"]
        XCTAssertTrue(restField.waitForExistence(timeout: 5))
        XCTAssertEqual(restField.value as? String, "90")
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
        app.buttons["parse-workout"].tap()

        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        let addRest = app.buttons["add-rest-segment"]
        app.swipeUp()
        XCTAssertTrue(addRest.waitForExistence(timeout: 5))
        addRest.tap()

        let restSetup = app.buttons["segment-setup-1"]
        XCTAssertTrue(restSetup.waitForExistence(timeout: 5))
        if !restSetup.isHittable { app.swipeUp() }
        restSetup.tap()

        let duration = app.textFields["Rest duration in seconds"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Rounds"].exists)
        XCTAssertFalse(app.textFields["Rest between efforts in seconds"].exists)
        duration.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        duration.typeText("90")
        XCTAssertEqual(duration.value as? String, "90")
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
        app.buttons["parse-workout"].tap()
        XCTAssertTrue(app.navigationBars["Review Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Parsed with Apple Intelligence · On device"].exists)
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchEnvironment["WHOOPS_TEST_WORKOUT_MODEL"] = "unavailable"
        app.launch()
        app.tabBars.buttons["Train"].tap()
        entry.tap()
        entry.typeText("10 Strict Press 45 lb")
        app.buttons["parse-workout"].tap()
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
        app.buttons["parse-workout"].tap()
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
        app.buttons["parse-workout"].tap()
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
        app.buttons["parse-workout"].tap()
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
