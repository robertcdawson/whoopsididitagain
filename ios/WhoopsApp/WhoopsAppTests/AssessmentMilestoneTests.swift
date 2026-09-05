import SwiftData
import XCTest

@testable import WhoopsApp

final class AssessmentMilestoneTests: XCTestCase {
    func testJournalReadinessPresentationUsesExistingScoreBoundaries() {
        let cases: [(Int?, JournalReadinessMetric.Status, JournalReadinessMetric.Status)] = [
            (nil, .unavailable, .unavailable), (0, .low, .low), (39, .low, .low),
            (40, .caution, .low), (64, .caution, .low), (65, .positive, .low),
            (69, .positive, .low), (70, .positive, .caution), (89, .positive, .caution),
            (90, .positive, .positive), (100, .positive, .positive),
        ]
        for (score, body, sleep) in cases {
            let assessment = presentationAssessment(score: score)
            let rows = JournalReadinessMetric.rows(for: assessment)
            XCTAssertEqual(rows.map(\.title), ["Body", "Sleep", "Tissue"])
            XCTAssertEqual(rows[0].status, body)
            XCTAssertEqual(rows[1].status, sleep)
            XCTAssertEqual(rows[0].value, score.map { "\($0)/100" } ?? "Unavailable")
            XCTAssertEqual(assessment.recommendation, .proceedWithLimits)
        }
    }

    func testJournalTissueRestrictionAndCautionDoNotInventScores() {
        let hard = ReadinessReason(
            code: "restriction.avoid.test", message: "Synthetic", direction: .restriction,
            priority: 100)
        for score in [nil, 100] as [Int?] {
            let row = JournalReadinessMetric.rows(
                for: presentationAssessment(score: score, reasons: [hard]))[2]
            XCTAssertEqual(row.status, .restricted)
            XCTAssertEqual(row.value, "Restricted")
        }
        for code in [
            "restriction.limit.test", "restriction.monitor.test", "check-in.movement-pain",
            "check-in.tissue-signals",
        ] {
            let reason = ReadinessReason(
                code: code, message: "Synthetic", direction: .caution, priority: 60)
            XCTAssertEqual(
                JournalReadinessMetric.rows(
                    for: presentationAssessment(score: 90, reasons: [reason]))[2].status, .caution)
            XCTAssertEqual(
                JournalReadinessMetric.rows(
                    for: presentationAssessment(score: nil, reasons: [reason]))[2].status,
                .unavailable)
            XCTAssertEqual(
                JournalReadinessMetric.rows(
                    for: presentationAssessment(score: 39, reasons: [reason]))[2].status, .low)
        }
        let unrelated = ReadinessReason(
            code: "whoop.recovery", message: "Synthetic", direction: .caution, priority: 40)
        XCTAssertEqual(
            JournalReadinessMetric.rows(
                for: presentationAssessment(score: 40, reasons: [unrelated]))[2].status, .positive)
    }

    private func presentationAssessment(score: Int?, reasons: [ReadinessReason] = [])
        -> ReadinessAssessment
    {
        ReadinessAssessment(
            id: "presentation-test", day: "2026-08-31", computedAt: .distantPast,
            systemicScore: score, sleepScore: score, tissueScore: score,
            recommendation: .proceedWithLimits, confidence: .low, reasons: reasons,
            rulesetVersion: VersionedReadinessEngine.rulesetVersion, userOverride: nil,
            overrideNote: nil)
    }

    @MainActor
    func testDefaultRationaleCleanupPreservesDatesAndRunsOnlyOnce() async throws {
        let container = try makeContainer()
        let repository = AssessmentPersistence(container: container)
        try await repository.prepareDefaults()
        let context = ModelContext(container)
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<RestrictionRecord>()).first {
                $0.id == "right-distal-triceps"
            })
        let injury = try XCTUnwrap(
            context.fetch(FetchDescriptor<InjuryRecord>()).first { $0.id == record.injuryID })
        XCTAssertEqual(record.rationale, "Known partial distal-triceps injury.")
        let originalDate = Date(timeIntervalSince1970: 1_600_000_000)
        record.rationale =
            "Known partial distal-triceps injury; keep this editable as guidance changes."
        record.updatedAt = originalDate
        injury.updatedAt = originalDate
        record.painThreshold = 4
        record.isActive = false
        try context.save()

        let upgraded = AssessmentPersistence(container: container)
        try await upgraded.prepareDefaults()
        try await upgraded.prepareDefaults()
        let refreshed = ModelContext(container)
        let saved = try XCTUnwrap(
            refreshed.fetch(FetchDescriptor<RestrictionRecord>()).first { $0.id == record.id })
        let savedInjury = try XCTUnwrap(
            refreshed.fetch(FetchDescriptor<InjuryRecord>()).first { $0.id == injury.id })
        XCTAssertEqual(saved.rationale, "Known partial distal-triceps injury.")
        XCTAssertEqual(saved.updatedAt, originalDate)
        XCTAssertEqual(savedInjury.updatedAt, originalDate)
        XCTAssertEqual(saved.painThreshold, 4)
        XCTAssertFalse(saved.isActive)
        XCTAssertEqual(try refreshed.fetchCount(FetchDescriptor<RestrictionRecord>()), 5)
    }

    @MainActor
    func testDefaultRationaleCleanupPreservesCustomNotesAndOtherRecords() async throws {
        let container = try makeContainer()
        let repository = AssessmentPersistence(container: container)
        try await repository.prepareDefaults()
        let profiles = try await repository.restrictions()
        var custom = try XCTUnwrap(profiles.first { $0.id == "right-distal-triceps" })
        custom.rationale = "My updated note; keep this editable as guidance changes."
        try await repository.saveRestriction(custom)
        var other = try XCTUnwrap(profiles.first { $0.id != "right-distal-triceps" })
        other.rationale =
            "Known partial distal-triceps injury; keep this editable as guidance changes."
        try await repository.saveRestriction(other)
        try await repository.prepareDefaults()
        let saved = try await repository.restrictions()
        XCTAssertEqual(saved.first { $0.id == custom.id }?.rationale, custom.rationale)
        XCTAssertEqual(saved.first { $0.id == other.id }?.rationale, other.rationale)
    }

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

    func testBodyAreaCatalogUsesStableValidatedAnatomyIDs() throws {
        XCTAssertEqual(Set(BodyAreaCatalog.all.map(\.id)).count, BodyAreaCatalog.all.count)
        let posteriorUpperArm = try XCTUnwrap(
            BodyAreaCatalog.definition(for: "right.arm.upper-arm.back"))
        XCTAssertEqual(posteriorUpperArm.focus, BodyMapFocus(region: .arm, side: .right))
        XCTAssertEqual(posteriorUpperArm.view, .back)
        XCTAssertEqual(
            posteriorUpperArm.shortLabel,
            "Posterior upper arm (triceps area)")
        XCTAssertEqual(
            BodyAreaCatalog.definition(for: "right.arm.elbow.back")?.shortLabel,
            "Back elbow")
        XCTAssertNil(BodyAreaCatalog.definition(for: "free text that should not be inferred"))
    }

    func testBodyAreaCatalogCoversPracticalExternalRegions() {
        let requiredIDs = [
            "midline.head-neck.face",
            "midline.head-neck.jaw-chin",
            "midline.head-neck.neck.left",
            "midline.torso.chest.left",
            "midline.torso.collarbone.left",
            "midline.torso.sternum",
            "midline.torso.groin.right",
            "midline.torso.hip.left",
            "midline.torso.shoulder-blade.left",
            "midline.torso.sacrum-tailbone",
            "midline.torso.si-joint.right",
            "midline.torso.glute.right",
            "left.arm.armpit",
            "left.arm.thumb",
            "right.arm.fingers",
            "left.leg.knee.inner",
            "right.leg.lower-leg.back",
            "left.leg.heel",
            "left.leg.ball-foot",
            "right.leg.sole-arch",
            "right.leg.toes",
        ]

        XCTAssertTrue(requiredIDs.allSatisfy { BodyAreaCatalog.definition(for: $0) != nil })
        for focus in BodyAreaCatalog.focuses(for: .front) {
            XCTAssertEqual(
                BodyAreaCatalog.all.filter { $0.focus == focus && $0.isWholeFocus }.count,
                1,
                "Every focus should have exactly one broad selection: \(focus.id)"
            )
        }

        let rightArm = BodyMapFocus(region: .arm, side: .right)
        XCTAssertEqual(BodyAreaCatalog.figureAreas(for: rightArm, view: .front).count, 5)
        XCTAssertEqual(BodyAreaCatalog.figureAreas(for: rightArm, view: .back).count, 5)
        XCTAssertFalse(
            BodyAreaCatalog.all.contains { $0.id.contains(".leg.hip") },
            "Hip, groin, and glute areas should have one canonical torso focus"
        )
    }

    @MainActor
    func testAffectedAreasRoundTripWithoutInferringFromRestrictionText() async throws {
        let repository = AssessmentPersistence(container: try makeContainer())
        try await repository.prepareDefaults()

        let seeded = try await repository.restrictions()
        var restriction = try XCTUnwrap(
            seeded.first { $0.id == "right-distal-triceps" })
        XCTAssertTrue(restriction.affectedAreaIDs.isEmpty)

        restriction.affectedAreaIDs = [
            "right.arm.elbow.back",
            "not-a-catalog-area",
            "right.arm.upper-arm.back",
            "right.arm.elbow.back",
        ]
        try await repository.saveRestriction(restriction)

        let roundTripped = try await repository.restrictions()
        let saved = try XCTUnwrap(roundTripped.first { $0.id == restriction.id })
        XCTAssertEqual(
            saved.affectedAreaIDs,
            ["right.arm.upper-arm.back", "right.arm.elbow.back"])
        XCTAssertEqual(saved.bodyRegion, "Elbow / upper arm")
        XCTAssertEqual(saved.side, "Right")
    }

    @MainActor
    func testInvalidOrLegacyAffectedAreaPayloadRemainsUnmapped() async throws {
        let container = try makeContainer()
        let repository = AssessmentPersistence(container: container)
        try await repository.prepareDefaults()
        let context = ModelContext(container)
        let injury = try XCTUnwrap(
            context.fetch(FetchDescriptor<InjuryRecord>()).first {
                $0.id == "injury:right-distal-triceps"
            })

        injury.affectedAreaIDsJSON = "[\"right.arm.upper-arm.back\",\"unknown\"]"
        try context.save()
        var saved = try await repository.restrictions()
        XCTAssertEqual(
            saved.first { $0.id == "right-distal-triceps" }?.affectedAreaIDs,
            ["right.arm.upper-arm.back"])

        injury.affectedAreaIDsJSON = "not json"
        try context.save()
        saved = try await repository.restrictions()
        XCTAssertTrue(
            saved.first { $0.id == "right-distal-triceps" }?.affectedAreaIDs.isEmpty == true)
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

    func testPainLogRejectsUnknownAreasAndOutOfRangeIntensity() {
        XCTAssertThrowsError(
            try PainLogEntry(bodyAreaID: "invented.area", intensity: 4)
        ) {
            XCTAssertEqual($0 as? PainLogValidationError, .unknownBodyArea)
        }
        XCTAssertThrowsError(
            try PainLogEntry(bodyAreaID: "midline.head-neck.entire", intensity: 11)
        ) {
            XCTAssertEqual($0 as? PainLogValidationError, .intensityOutOfRange)
        }
    }

    @MainActor
    func testPainLogsAreIndependentEditableAndExplicitlyDeletable() async throws {
        let repository = AssessmentPersistence(container: try makeContainer())
        let older = try PainLogEntry(
            id: "pain-older",
            occurredAt: Date(timeIntervalSince1970: 100),
            bodyAreaID: "midline.head-neck.entire",
            intensity: 2,
            note: "  after waking  "
        )
        let newer = try PainLogEntry(
            id: "pain-newer",
            occurredAt: Date(timeIntervalSince1970: 200),
            bodyAreaID: "right.arm.upper-arm.back",
            intensity: 5
        )
        try await repository.savePainLog(older)
        try await repository.savePainLog(newer)

        var saved = try await repository.painLogs()
        XCTAssertEqual(saved.map(\.id), ["pain-newer", "pain-older"])
        XCTAssertEqual(saved.last?.note, "after waking")
        let unrelatedCheckIn = try await repository.checkIn(for: "1970-01-01")
        XCTAssertNil(unrelatedCheckIn)

        let correction = try PainLogEntry(
            id: newer.id,
            occurredAt: newer.occurredAt,
            bodyAreaID: newer.bodyAreaID,
            intensity: 3,
            note: "settled down"
        )
        try await repository.savePainLog(correction)
        saved = try await repository.painLogs()
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first?.intensity, 3)

        try await repository.deletePainLog(id: older.id)
        saved = try await repository.painLogs()
        XCTAssertEqual(saved.map(\.id), ["pain-newer"])
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
            PainLogRecord.self,
            ReadinessAssessmentRecord.self,
            SleepScheduleRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
