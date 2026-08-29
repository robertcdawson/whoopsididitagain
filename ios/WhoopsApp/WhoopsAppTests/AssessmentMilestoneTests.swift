import SwiftData
import XCTest

@testable import WhoopsApp

final class AssessmentMilestoneTests: XCTestCase {
    func testRobustBaselineUsesMostRecent28Values() throws {
        let values = [999.0] + (1...28).map(Double.init)
        let baseline = try XCTUnwrap(RobustBaseline.calculate(values))

        XCTAssertEqual(baseline.observationCount, 28)
        XCTAssertEqual(baseline.median, 14.5)
        XCTAssertEqual(baseline.medianAbsoluteDeviation, 7)
    }

    func testHardRestrictionOverridesHighSystemicRecovery() async throws {
        let input = readinessInput(
            recovery: 95,
            checkIn: MorningCheckIn.empty(day: "2026-08-16"),
            restrictions: [hardRestriction()]
        )

        let assessment = try await VersionedReadinessEngine().assess(input)

        XCTAssertEqual(assessment.recommendation, .modify)
        XCTAssertEqual(assessment.tissueScore, 39)
        XCTAssertTrue(assessment.reasonCodes.contains { $0.hasPrefix("restriction.avoid") })
        XCTAssertGreaterThanOrEqual(assessment.systemicScore ?? 0, 80)
        XCTAssertEqual(assessment.rulesetVersion, "readiness-1.0.1")
    }

    func testHardRestrictionDoesNotInventTissueScoreWithoutCheckIn() async throws {
        let assessment = try await VersionedReadinessEngine().assess(
            readinessInput(
                recovery: 95,
                checkIn: nil,
                restrictions: [hardRestriction()]
            )
        )

        XCTAssertNil(assessment.tissueScore)
        XCTAssertEqual(assessment.recommendation, .modify)
        XCTAssertTrue(assessment.reasonCodes.contains("check-in.missing"))
    }

    func testHardRestrictionDoesNotRaiseLowerSymptomScore() async throws {
        var checkIn = MorningCheckIn.empty(day: "2026-08-16")
        checkIn.painWithMovement = 10

        let assessment = try await VersionedReadinessEngine().assess(
            readinessInput(
                recovery: 95,
                checkIn: checkIn,
                restrictions: [hardRestriction()]
            )
        )

        XCTAssertEqual(assessment.tissueScore, 30)
        XCTAssertEqual(assessment.recommendation, .modify)
    }

    func testMissingDataLowersConfidenceAndExposesReasonCodes() async throws {
        let assessment = try await VersionedReadinessEngine().assess(
            readinessInput(recovery: nil, checkIn: nil, restrictions: [])
        )

        XCTAssertEqual(assessment.confidence, .low)
        XCTAssertEqual(assessment.recommendation, .proceedWithLimits)
        XCTAssertTrue(assessment.reasonCodes.contains("whoop.recovery.missing"))
        XCTAssertTrue(assessment.reasonCodes.contains("check-in.missing"))
    }

    func testSleepDeadlineIncludesLatencyAndWindDown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-16T20:00:00Z"))

        let deadline = SleepDeadlineCalculator.calculate(
            now: now,
            settings: .standard,
            calendar: calendar
        )

        XCTAssertEqual(
            ISO8601DateFormatter().string(from: deadline.lightsOutAt),
            "2026-08-16T22:55:00Z"
        )
        XCTAssertEqual(
            ISO8601DateFormatter().string(from: deadline.windDownAt),
            "2026-08-16T22:10:00Z"
        )
    }

    @MainActor
    func testPersistenceSeedsEditableRestrictionsAndPreservesOverride() async throws {
        let repository = AssessmentPersistence(container: try makeContainer())
        try await repository.prepareDefaults()

        var restrictions = try await repository.restrictions()
        XCTAssertEqual(restrictions.count, 5)
        XCTAssertTrue(restrictions.contains { $0.id == "right-distal-triceps" && $0.isActive })

        restrictions[0].isActive.toggle()
        try await repository.saveRestriction(restrictions[0])
        let updatedRestrictions = try await repository.restrictions()
        XCTAssertEqual(
            updatedRestrictions.first { $0.id == restrictions[0].id }?.isActive,
            restrictions[0].isActive
        )

        let assessment = try await VersionedReadinessEngine().assess(
            readinessInput(
                recovery: 80,
                checkIn: MorningCheckIn.empty(day: "2026-08-16"),
                restrictions: []
            )
        )
        try await repository.saveAssessment(assessment)
        try await repository.saveOverride(
            assessmentID: assessment.id,
            recommendation: .proceedWithLimits,
            note: "Synthetic coaching context"
        )
        try await repository.saveAssessment(assessment)

        let stored = try await repository.assessment(for: assessment.day)
        XCTAssertEqual(stored?.userOverride, .proceedWithLimits)
        XCTAssertEqual(stored?.overrideNote, "Synthetic coaching context")
    }

    @MainActor
    func testDeletingCheckInKeepsOtherDays() async throws {
        let repository = AssessmentPersistence(container: try makeContainer())
        let first = MorningCheckIn.empty(day: "2026-08-20")
        let second = MorningCheckIn.empty(day: "2026-08-21")
        try await repository.saveCheckIn(first)
        try await repository.saveCheckIn(second)

        try await repository.deleteCheckIn(day: first.day)

        let deleted = try await repository.checkIn(for: first.day)
        let remaining = try await repository.checkIn(for: second.day)
        XCTAssertNil(deleted)
        XCTAssertEqual(remaining, second)
    }

    private func readinessInput(
        recovery: Int?,
        checkIn: MorningCheckIn?,
        restrictions: [RestrictionProfile]
    ) -> ReadinessInput {
        ReadinessInput(
            date: Date(timeIntervalSince1970: 1_776_000_000),
            day: "2026-08-16",
            physiology: PhysiologyReadinessInput(
                whoopRecovery: recovery,
                whoopHRVRMSSD: nil,
                whoopHRVHistory: [],
                appleHRVSDNN: nil,
                appleHRVHistory: [],
                restingHeartRate: nil,
                restingHeartRateHistory: [],
                sleepMinutes: nil
            ),
            checkIn: checkIn,
            activeRestrictions: restrictions,
            sleepSettings: .standard
        )
    }

    private func hardRestriction() -> RestrictionProfile {
        RestrictionProfile(
            id: "test-hard-restriction",
            injuryName: "Test injury",
            bodyRegion: "Arm",
            side: "Right",
            movementTag: "ballistic elbow extension",
            level: .avoid,
            painThreshold: 2,
            rationale: "Synthetic test restriction",
            isActive: true
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: InjuryRecord.self,
            RestrictionRecord.self,
            SymptomCheckInRecord.self,
            ReadinessAssessmentRecord.self,
            SleepScheduleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
