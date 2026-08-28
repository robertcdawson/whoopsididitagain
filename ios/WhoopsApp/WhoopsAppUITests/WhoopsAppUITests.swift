import XCTest

final class WhoopsAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourTabShellIsVisible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Train"].exists)
        XCTAssertTrue(app.tabBars.buttons["Trends"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    @MainActor
    func testMorningCheckInEntryIsAvailable() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["morning-check-in"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTrendsShowsDeterministicWeeklyReview() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Trends"].tap()

        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WEEKLY REVIEW"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Most important change"].exists)
        XCTAssertTrue(app.staticTexts["What coincided"].exists)
        XCTAssertTrue(app.staticTexts["Next action"].exists)
    }

    @MainActor
    func testExperimentLabOpensWhenFeatureFlagIsEnabled() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WHOOPS_ENABLE_EXPERIMENT_LAB"] = "1"
        app.launch()
        app.tabBars.buttons["Trends"].tap()
        let lab = app.buttons["experiment-lab-link"]
        for _ in 0..<8 where !lab.exists { app.swipeUp() }
        XCTAssertTrue(lab.waitForExistence(timeout: 5))
        lab.tap()
        XCTAssertTrue(app.navigationBars["Experiment Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-experiment"].exists)
        XCTAssertTrue(app.staticTexts["ONE DAILY CHECK-IN"].exists)
        XCTAssertTrue(app.buttons["log-experiment-day"].exists)
    }

    @MainActor
    func testWorkoutCanBePastedAndReviewed() throws {
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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

        XCTAssertTrue(app.staticTexts["WORKOUT OVERVIEW"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["SEGMENT 1 · WORK"].waitForExistence(timeout: 5))
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
    func testPopulatedWorkoutFieldsKeepVisibleLabels() throws {
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
}
