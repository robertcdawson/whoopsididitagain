import SwiftData
import XCTest

@testable import WhoopsApp

final class ExperimentMilestoneTests: XCTestCase {
    func testExperimentFeatureFlagDefaultsOffAndSupportsExplicitOverrides() {
        XCTAssertFalse(
            FeatureFlags.experimentLabEnabled(storedValue: false, environment: [:])
        )
        XCTAssertTrue(
            FeatureFlags.experimentLabEnabled(
                storedValue: false,
                environment: ["WHOOPS_ENABLE_EXPERIMENT_LAB": "1"]
            )
        )
        XCTAssertTrue(
            FeatureFlags.experimentLabEnabled(storedValue: true, environment: [:])
        )
    }

    func testDifferenceStaysHiddenUntilBothConditionsMeetThreshold() {
        var experiment = makeExperiment(outcome: .whoopRecovery)
        experiment.minimumObservations = 2
        let observations = [
            observation("2026-08-18", .intervention),
            observation("2026-08-19", .intervention),
            observation("2026-08-20", .comparison),
        ]
        let input = makeInput(
            metricID: "whoop-recovery",
            values: [
                ("2026-08-18", 80),
                ("2026-08-19", 70),
                ("2026-08-20", 60),
            ]
        )

        let insufficient = DeterministicExperimentEngine().analyze(
            experiment: experiment,
            observations: observations,
            input: input,
            calendar: utcCalendar
        )
        XCTAssertEqual(insufficient.evidenceStatus, .insufficientData)
        XCTAssertNil(insufficient.observedDifference)
        XCTAssertTrue(
            insufficient.summary.contains("Bed by 10:30 PM: 2 usable of 2 required (2 logged)")
        )
        XCTAssertTrue(
            insufficient.summary.contains("Usual bedtime: 1 usable of 2 required (1 logged)")
        )

        let sufficient = DeterministicExperimentEngine().analyze(
            experiment: experiment,
            observations: observations + [observation("2026-08-21", .comparison)],
            input: makeInput(
                metricID: "whoop-recovery",
                values: [
                    ("2026-08-18", 80),
                    ("2026-08-19", 70),
                    ("2026-08-20", 60),
                    ("2026-08-21", 50),
                ]
            ),
            calendar: utcCalendar
        )
        XCTAssertEqual(sufficient.evidenceStatus, .exploratory)
        XCTAssertEqual(sufficient.interventionMean, 75)
        XCTAssertEqual(sufficient.comparisonMean, 55)
        XCTAssertEqual(sufficient.observedDifference, 20)
        XCTAssertTrue(sufficient.summary.lowercased().contains("observed association"))
        XCTAssertFalse(sufficient.summary.lowercased().contains("caused"))
    }

    func testExcludedAndMissingDaysRemainAuditableButDoNotEnterAnalysis() {
        var experiment = makeExperiment(outcome: .sleepDuration)
        experiment.minimumObservations = 2
        var excluded = observation("2026-08-19", .intervention)
        excluded.included = false
        excluded.exclusionReason = "Travel"
        let analysis = DeterministicExperimentEngine().analyze(
            experiment: experiment,
            observations: [
                observation("2026-08-18", .intervention),
                excluded,
                observation("2026-08-22", .intervention),
                observation("2026-08-20", .comparison),
                observation("2026-08-21", .comparison),
                observation("2026-08-23", .comparison),
            ],
            input: makeInput(
                sleepValues: [
                    ("2026-08-18", 480),
                    ("2026-08-19", 300),
                    ("2026-08-20", 420),
                    ("2026-08-21", 400),
                    ("2026-08-22", 500),
                ]
            ),
            calendar: utcCalendar
        )

        XCTAssertEqual(analysis.observations.count, 6)
        XCTAssertEqual(analysis.interventionCount, 2)
        XCTAssertEqual(analysis.comparisonCount, 2)
        XCTAssertEqual(analysis.interventionLoggedCount, 2)
        XCTAssertEqual(analysis.comparisonLoggedCount, 3)
        XCTAssertEqual(analysis.missingOutcomeCount, 1)
        XCTAssertEqual(analysis.observedDifference, 80)
        XCTAssertTrue(analysis.caveat.contains("1 included observations"))
    }

    func testOutcomeTimingCanUseFollowingLocalDay() {
        var experiment = makeExperiment(outcome: .whoopRecovery)
        experiment.outcomeTiming = .followingDay
        experiment.minimumObservations = 2
        let analysis = DeterministicExperimentEngine().analyze(
            experiment: experiment,
            observations: [
                observation("2026-08-18", .intervention),
                observation("2026-08-19", .intervention),
                observation("2026-08-20", .comparison),
                observation("2026-08-21", .comparison),
            ],
            input: makeInput(
                metricID: "whoop-recovery",
                values: [
                    ("2026-08-19", 80),
                    ("2026-08-20", 70),
                    ("2026-08-21", 60),
                    ("2026-08-22", 50),
                ]
            ),
            calendar: utcCalendar
        )

        XCTAssertEqual(
            analysis.observations.map(\.outcomeDay),
            [
                "2026-08-22", "2026-08-21", "2026-08-20", "2026-08-19",
            ])
        XCTAssertEqual(analysis.interventionMean, 75)
        XCTAssertEqual(analysis.comparisonMean, 55)
        XCTAssertEqual(analysis.observedDifference, 20)
    }

    func testLoggedDaysStayVisibleWhenSelectedOutcomeIsUnavailable() {
        var experiment = makeExperiment(outcome: .whoopHRVRMSSD)
        experiment.minimumObservations = 2
        let analysis = DeterministicExperimentEngine().analyze(
            experiment: experiment,
            observations: [
                observation("2026-08-18", .intervention),
                observation("2026-08-19", .intervention),
                observation("2026-08-20", .comparison),
                observation("2026-08-21", .comparison),
            ],
            input: makeInput(),
            calendar: utcCalendar
        )

        XCTAssertEqual(analysis.interventionLoggedCount, 2)
        XCTAssertEqual(analysis.comparisonLoggedCount, 2)
        XCTAssertEqual(analysis.interventionCount, 0)
        XCTAssertEqual(analysis.comparisonCount, 0)
        XCTAssertEqual(analysis.missingOutcomeCount, 4)
        XCTAssertTrue(analysis.summary.contains("2 logged"))
        XCTAssertTrue(ExperimentOutcome.whoopHRVRMSSD.dataSourceExplanation.contains("SDNN"))
    }

    func testOutcomesHaveSimpleRecommendedTimingDefaults() {
        XCTAssertEqual(ExperimentOutcome.whoopRecovery.recommendedTiming, .followingDay)
        XCTAssertEqual(ExperimentOutcome.sleepDuration.recommendedTiming, .followingDay)
        XCTAssertEqual(ExperimentOutcome.trainingLoad.recommendedTiming, .sameDay)
    }

    func testWorkoutAndCheckInOutcomesResolveByLocalDay() {
        let input = ExperimentAnalysisInput(
            trends: makeSnapshot(
                dailyLoads: [
                    DailyTrainingLoad(day: "2026-08-20", minutes: 30, sessionRPE: 8, load: 240)
                ]
            ),
            checkIns: [
                MorningCheckIn(
                    day: "2026-08-20",
                    timestamp: date("2026-08-20T07:00:00Z"),
                    painAtRest: 1,
                    painWithMovement: 3,
                    stiffness: false,
                    swelling: false,
                    perceivedWeakness: false,
                    energy: 3,
                    motivation: 3,
                    illnessSymptoms: false,
                    notes: ""
                )
            ]
        )
        let engine = DeterministicExperimentEngine()

        XCTAssertEqual(
            engine.resolve(.trainingLoad, day: "2026-08-20", input: input, calendar: utcCalendar),
            240
        )
        XCTAssertEqual(
            engine.resolve(
                .morningPainWithMovement,
                day: "2026-08-20",
                input: input,
                calendar: utcCalendar
            ),
            3
        )
    }

    @MainActor
    func testPersistenceUpsertsOneObservationPerExperimentAndDay() async throws {
        let container = try ModelContainer(
            for: ExperimentRecord.self,
            ExperimentObservationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ExperimentPersistence(container: container)
        var experiment = makeExperiment(outcome: .sleepDuration)
        experiment.status = .active
        try await repository.saveExperiment(experiment)

        var first = observation("2026-08-20", .intervention)
        try await repository.saveObservation(first)
        first.condition = .comparison
        first.notes = "Corrected assignment"
        try await repository.saveObservation(first)

        let reloaded = try await repository.experiments(includeArchived: false)
        let observations = try await repository.observations(experimentID: experiment.id)
        XCTAssertEqual(reloaded, [experiment])
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations.first?.condition, .comparison)
        XCTAssertEqual(observations.first?.notes, "Corrected assignment")
    }

    @MainActor
    func testReplacingObservationMovesItWithoutLeavingOriginalDay() async throws {
        let container = try ModelContainer(
            for: ExperimentRecord.self,
            ExperimentObservationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ExperimentPersistence(container: container)
        let original = observation("2026-08-20", .intervention)
        try await repository.saveObservation(original)

        var moved = original
        moved.day = "2026-08-21"
        moved.id = ExperimentObservation.stableID(
            experimentID: moved.experimentID,
            day: moved.day
        )
        moved.condition = .comparison
        try await repository.replaceObservation(id: original.id, with: moved)

        let observations = try await repository.observations(experimentID: original.experimentID)
        XCTAssertEqual(observations, [moved])
    }

    @MainActor
    func testReplacingObservationRejectsAnOccupiedDestinationDay() async throws {
        let container = try ModelContainer(
            for: ExperimentRecord.self,
            ExperimentObservationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ExperimentPersistence(container: container)
        let original = observation("2026-08-20", .intervention)
        let destination = observation("2026-08-21", .comparison)
        try await repository.saveObservations([original, destination])

        var moved = original
        moved.day = destination.day
        moved.id = destination.id
        do {
            try await repository.replaceObservation(id: original.id, with: moved)
            XCTFail("Expected an occupied destination to be rejected")
        } catch let error as ExperimentValidationError {
            XCTAssertEqual(
                error.errorDescription,
                ExperimentValidationError.observationDayConflict.errorDescription)
        }

        let observations = try await repository.observations(experimentID: original.experimentID)
        XCTAssertEqual(Set(observations.map(\.day)), Set([original.day, destination.day]))
    }

    @MainActor
    func testBatchSaveRecordsOneDailyCheckInAcrossExperiments() async throws {
        let container = try ModelContainer(
            for: ExperimentRecord.self,
            ExperimentObservationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ExperimentPersistence(container: container)
        var first = observation("2026-08-20", .intervention)
        var second = ExperimentObservation.new(
            experimentID: "experiment-2",
            day: "2026-08-20"
        )
        second.condition = .comparison

        try await repository.saveObservations([first, second])
        first.condition = .comparison
        try await repository.saveObservations([first])

        let firstSaved = try await repository.observations(experimentID: "experiment-1")
        let secondSaved = try await repository.observations(experimentID: "experiment-2")
        XCTAssertEqual(firstSaved.map(\.condition), [.comparison])
        XCTAssertEqual(secondSaved.map(\.condition), [.comparison])
    }

    @MainActor
    func testExcludedObservationRequiresReason() async throws {
        let container = try ModelContainer(
            for: ExperimentRecord.self,
            ExperimentObservationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ExperimentPersistence(container: container)
        var value = observation("2026-08-20", .intervention)
        value.included = false

        do {
            try await repository.saveObservation(value)
            XCTFail("Expected validation error")
        } catch let error as ExperimentValidationError {
            XCTAssertEqual(error.errorDescription, "An excluded observation needs a reason.")
        }
    }

    @MainActor
    func testDeletingObservationAndExperimentRemovesDependentRecords() async throws {
        let container = try ModelContainer(
            for: ExperimentRecord.self,
            ExperimentObservationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ExperimentPersistence(container: container)
        let experiment = makeExperiment(outcome: .sleepDuration)
        try await repository.saveExperiment(experiment)
        let first = observation("2026-08-20", .intervention)
        let second = observation("2026-08-21", .comparison)
        try await repository.saveObservations([first, second])

        try await repository.deleteObservation(id: first.id)
        let observationsAfterDayDeletion = try await repository.observations(
            experimentID: experiment.id
        )
        XCTAssertEqual(observationsAfterDayDeletion, [second])

        try await repository.deleteExperiment(id: experiment.id)
        let remainingExperiments = try await repository.experiments(includeArchived: true)
        let remainingObservations = try await repository.observations(
            experimentID: experiment.id
        )
        XCTAssertTrue(remainingExperiments.isEmpty)
        XCTAssertTrue(remainingObservations.isEmpty)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeExperiment(outcome: ExperimentOutcome) -> ExperimentDefinition {
        var value = ExperimentDefinition.draft(now: date("2026-08-18T00:00:00Z"))
        value.id = "experiment-1"
        value.title = "Bedtime test"
        value.question = "Does an earlier bedtime change recovery?"
        value.intervention = "Bed by 10:30 PM"
        value.comparisonCondition = "Usual bedtime"
        value.primaryOutcome = outcome
        value.outcomeTiming = .sameDay
        return value
    }

    private func observation(
        _ day: String,
        _ condition: ExperimentCondition
    ) -> ExperimentObservation {
        var value = ExperimentObservation.new(experimentID: "experiment-1", day: day)
        value.condition = condition
        return value
    }

    private func makeInput(
        metricID: String? = nil,
        values: [(String, Double)] = [],
        sleepValues: [(String, Double)] = []
    ) -> ExperimentAnalysisInput {
        let metric = metricID.map { id in
            MetricTrendSummary(
                id: id,
                title: "Metric",
                unit: "%",
                source: "Test",
                points: values.enumerated().map { index, value in
                    TrendPoint(
                        id: "point-\(index)",
                        date: date("\(value.0)T12:00:00Z"),
                        value: value.1,
                        source: "Test"
                    )
                },
                latestValue: values.last?.1,
                baselineMedian: nil,
                changeFromBaseline: nil,
                robustDeviation: nil,
                observationCount: values.count
            )
        }
        let sleep = MetricTrendSummary(
            id: "sleep-duration",
            title: "Sleep duration",
            unit: "min",
            source: "Test",
            points: sleepValues.enumerated().map { index, value in
                TrendPoint(
                    id: "sleep-\(index)",
                    date: date("\(value.0)T12:00:00Z"),
                    value: value.1,
                    source: "Test"
                )
            },
            latestValue: sleepValues.last?.1,
            baselineMedian: nil,
            changeFromBaseline: nil,
            robustDeviation: nil,
            observationCount: sleepValues.count
        )
        return ExperimentAnalysisInput(
            trends: makeSnapshot(metrics: metric.map { [$0] } ?? [], sleep: sleep),
            checkIns: []
        )
    }

    private func makeSnapshot(
        metrics: [MetricTrendSummary] = [],
        sleep: MetricTrendSummary? = nil,
        dailyLoads: [DailyTrainingLoad] = []
    ) -> TrendsSnapshot {
        TrendsSnapshot(
            generatedAt: date("2026-08-22T12:00:00Z"),
            recoveryMetrics: metrics,
            sleep: sleep
                ?? MetricTrendSummary(
                    id: "sleep-duration",
                    title: "Sleep duration",
                    unit: "min",
                    source: "Test",
                    points: [],
                    latestValue: nil,
                    baselineMedian: nil,
                    changeFromBaseline: nil,
                    robustDeviation: nil,
                    observationCount: 0
                ),
            dailyTrainingLoads: dailyLoads,
            currentTrainingLoad: 0,
            priorTrainingLoad: 0,
            strengthVolumes: [],
            painByMovement: [],
            injuries: [],
            weeklyReview: WeeklyReview(
                version: "test",
                periodStart: date("2026-08-15T00:00:00Z"),
                periodEnd: date("2026-08-22T00:00:00Z"),
                importantChange: "",
                plausibleExplanation: "",
                nextAction: "",
                caveat: "",
                currentWorkoutCount: 0,
                priorWorkoutCount: 0,
                physiologyObservationCount: 0,
                checkInCount: 0
            )
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
