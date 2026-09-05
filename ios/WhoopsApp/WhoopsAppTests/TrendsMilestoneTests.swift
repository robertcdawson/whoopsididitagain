import XCTest

@testable import WhoopsApp

final class TrendsMilestoneTests: XCTestCase {
    func testUnreportedPainIsExcludedWhileExplicitZeroRemainsAnObservation() {
        var missing = workout(
            id: "missing", start: "2026-08-20T17:00:00Z", minutes: 20,
            rpe: 5, movementPain: 9)
        missing.movements[0].painWasReported = false
        var zero = workout(
            id: "zero", start: "2026-08-19T17:00:00Z", minutes: 20,
            rpe: 5, movementPain: 0)
        zero.movements[0].painWasReported = true
        let input = makeInput(workouts: [missing, zero])
        let snapshot = DeterministicTrendsEngine().analyze(input, calendar: utcCalendar)
        XCTAssertEqual(snapshot.painByMovement.first?.observationCount, 1)
        XCTAssertEqual(snapshot.painByMovement.first?.averagePain, 0)
        let csv = String(
            decoding: TrendsExporter.csvData(input: input, snapshot: snapshot), as: UTF8.self)
        let movementRows = csv.components(separatedBy: "\n").filter {
            $0.hasPrefix("\"movement\",")
        }
        XCTAssertEqual(movementRows.count, 2)
        XCTAssertTrue(movementRows[0].contains(",\"\",\"pain_0-10\","))
        XCTAssertTrue(movementRows[1].contains(",\"0\",\"pain_0-10\","))
    }

    func testRecoverySourcesStaySeparateAndBaselineExcludesLatestValue() throws {
        let input = makeInput(
            recoveries: [
                recovery("r1", "2026-08-17T07:00:00Z", score: 60, rmssd: 40),
                recovery("r2", "2026-08-18T07:00:00Z", score: 70, rmssd: 45),
                recovery("r3", "2026-08-19T07:00:00Z", score: 80, rmssd: 50),
            ],
            healthDays: [
                HealthKitDailySummary(
                    id: "2026-08-19",
                    day: "2026-08-19",
                    restingHeartRate: nil,
                    hrvSDNNMilliseconds: 72,
                    respiratoryRate: nil,
                    oxygenSaturationPercent: nil,
                    sleepMinutes: nil,
                    activeEnergyKilocalories: nil,
                    exerciseMinutes: nil,
                    workoutCount: 0,
                    sources: ["Apple Watch"]
                )
            ]
        )

        let snapshot = DeterministicTrendsEngine().analyze(input, calendar: utcCalendar)
        let recovery = try XCTUnwrap(snapshot.recoveryMetrics.first { $0.id == "whoop-recovery" })
        let whoopHRV = try XCTUnwrap(snapshot.recoveryMetrics.first { $0.id == "whoop-hrv-rmssd" })
        let appleHRV = try XCTUnwrap(snapshot.recoveryMetrics.first { $0.id == "apple-hrv-sdnn" })

        XCTAssertEqual(recovery.baselineMedian, 65)
        XCTAssertEqual(recovery.changeFromBaseline, 15)
        XCTAssertEqual(whoopHRV.source, "WHOOP")
        XCTAssertEqual(appleHRV.source, "Apple Health")
        XCTAssertNotEqual(whoopHRV.id, appleHRV.id)
    }

    func testTrainingLoadUsesDurationTimesRPEAndSevenDayWindows() {
        let current = workout(
            id: "current",
            start: "2026-08-20T17:00:00Z",
            minutes: 30,
            rpe: 8,
            movementPain: 3
        )
        let prior = workout(
            id: "prior",
            start: "2026-08-10T17:00:00Z",
            minutes: 20,
            rpe: 5,
            movementPain: 1
        )
        let snapshot = DeterministicTrendsEngine().analyze(
            makeInput(workouts: [current, prior]),
            calendar: utcCalendar
        )

        XCTAssertEqual(snapshot.currentTrainingLoad, 240)
        XCTAssertEqual(snapshot.priorTrainingLoad, 100)
        XCTAssertTrue(snapshot.weeklyReview.importantChange.contains("n=1 vs n=1"))
        XCTAssertEqual(snapshot.painByMovement.first?.observationCount, 2)
        XCTAssertEqual(snapshot.painByMovement.first?.averagePain, 2)
    }

    func testSleepUsesWhoopPerDayAndAppleFallbackForMissingDays() {
        let appleDays = [
            healthDay("2026-08-18", sleepMinutes: 400, respiratoryRate: 14.5),
            healthDay("2026-08-19", sleepMinutes: 410, respiratoryRate: 14.2),
        ]
        let whoopSleep = SleepHistoryItem(
            id: "whoop-19",
            start: date("2026-08-18T22:00:00Z"),
            end: date("2026-08-19T06:20:00Z"),
            isNap: false,
            sleepPerformance: 88,
            sleepMinutes: 500
        )

        let snapshot = DeterministicTrendsEngine().analyze(
            makeInput(sleeps: [whoopSleep], healthDays: appleDays),
            calendar: utcCalendar
        )

        XCTAssertEqual(snapshot.sleep.points.map(\.value), [400, 500])
        XCTAssertEqual(snapshot.sleep.points.map(\.source), ["Apple Health", "WHOOP"])
        XCTAssertEqual(snapshot.sleep.source, "WHOOP + Apple Health fallback")
        XCTAssertEqual(
            snapshot.recoveryMetrics.first { $0.id == "apple-respiratory-rate" }?.points.count,
            2
        )
    }

    func testInsufficientDataIsExplicitAndNeverClaimsCausation() {
        let review = DeterministicTrendsEngine().analyze(
            makeInput(), calendar: utcCalendar
        ).weeklyReview

        XCTAssertTrue(review.importantChange.lowercased().contains("insufficient"))
        XCTAssertTrue(review.plausibleExplanation.lowercased().contains("insufficient"))
        XCTAssertFalse(review.plausibleExplanation.lowercased().contains("caused"))
        XCTAssertEqual(review.version, "trends-1.0.0")
    }

    func testNormalizedExportsExcludeCredentialAndRawPayloadFields() throws {
        let input = makeInput(
            recoveries: [recovery("r1", "2026-08-20T07:00:00Z", score: 75, rmssd: 51)],
            workouts: [
                workout(
                    id: "w1", start: "2026-08-20T17:00:00Z", minutes: 25, rpe: 7, movementPain: 2)
            ]
        )
        let snapshot = DeterministicTrendsEngine().analyze(input, calendar: utcCalendar)
        let json = try String(
            decoding: TrendsExporter.jsonData(input: input, snapshot: snapshot),
            as: UTF8.self
        )
        let csv = String(
            decoding: TrendsExporter.csvData(input: input, snapshot: snapshot),
            as: UTF8.self
        )

        XCTAssertTrue(json.contains("normalized-export-1.0.0"))
        XCTAssertTrue(json.contains("completedWorkouts"))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("refreshToken"))
        XCTAssertFalse(json.contains("rawPayload"))
        XCTAssertTrue(csv.contains("training_load"))
        XCTAssertTrue(csv.contains("movement"))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeInput(
        recoveries: [RecoveryHistoryItem] = [],
        sleeps: [SleepHistoryItem] = [],
        healthDays: [HealthKitDailySummary] = [],
        workouts: [CompletedWorkout] = []
    ) -> TrendsInput {
        TrendsInput(
            generatedAt: date("2026-08-21T12:00:00Z"),
            whoop: WhoopHistorySnapshot(
                recoveries: recoveries,
                sleeps: sleeps,
                lastSyncAt: nil
            ),
            healthKit: HealthKitHistorySnapshot(
                days: healthDays,
                lastSyncAt: nil,
                recordCount: healthDays.count,
                linkedWorkoutCount: 0
            ),
            workouts: workouts,
            plans: [],
            checkIns: [],
            assessments: [],
            restrictions: [],
            injuries: []
        )
    }

    private func healthDay(
        _ day: String,
        sleepMinutes: Int?,
        respiratoryRate: Double?
    ) -> HealthKitDailySummary {
        HealthKitDailySummary(
            id: day,
            day: day,
            restingHeartRate: 56,
            hrvSDNNMilliseconds: 70,
            respiratoryRate: respiratoryRate,
            oxygenSaturationPercent: 98,
            sleepMinutes: sleepMinutes,
            activeEnergyKilocalories: nil,
            exerciseMinutes: nil,
            workoutCount: 0,
            sources: ["Apple Watch"]
        )
    }

    private func recovery(
        _ id: String,
        _ timestamp: String,
        score: Int,
        rmssd: Double
    ) -> RecoveryHistoryItem {
        RecoveryHistoryItem(
            id: id,
            timestamp: date(timestamp),
            recoveryScore: score,
            restingHeartRate: 55,
            hrvRMSSD: rmssd
        )
    }

    private func workout(
        id: String,
        start: String,
        minutes: Int,
        rpe: Int,
        movementPain: Int
    ) -> CompletedWorkout {
        let startedAt = date(start)
        return CompletedWorkout(
            id: id,
            plannedWorkoutID: nil,
            title: "Test session",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(minutes * 60)),
            sessionRPE: rpe,
            postSessionPain: movementPain,
            notes: "",
            movements: [
                CompletedMovement(
                    id: "\(id)-movement",
                    canonicalMovementID: "air_bike",
                    plannedPrescriptionID: nil,
                    displayName: "Air bike",
                    actualRepetitions: nil,
                    actualDistanceMeters: nil,
                    actualCalories: nil,
                    actualLoadValue: nil,
                    actualLoadUnit: nil,
                    actualDurationSeconds: Double(minutes * 60),
                    modification: "",
                    painDuring: movementPain,
                    notes: ""
                )
            ]
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
