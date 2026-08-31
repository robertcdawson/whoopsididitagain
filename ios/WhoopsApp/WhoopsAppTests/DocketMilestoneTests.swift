import SwiftData
import XCTest

@testable import WhoopsApp

@MainActor
final class DocketMilestoneTests: XCTestCase {
    // 2026-08-31 is a Monday; the test calendar starts its week on Monday in UTC.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var engine: DeterministicDocketEngine {
        DeterministicDocketEngine(calendar: calendar, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testDailyItemAppearsWithQuantityTitleAndTag() throws {
        let docket = engine.docket(
            for: date(2026, 8, 31),
            protocols: [makeProtocol(items: [makeItem(id: "band", cadence: .daily)])],
            plans: [],
            sleepDeadline: nil,
            completions: []
        )

        XCTAssertEqual(docket.day, "2026-08-31")
        XCTAssertEqual(docket.rulesetVersion, "docket-1.1.0")
        XCTAssertEqual(docket.items.count, 1)
        let item = try XCTUnwrap(docket.items.first)
        XCTAssertEqual(item.title, "band extensions 3×15")
        XCTAssertEqual(item.tag, "PT")
        XCTAssertEqual(item.kind, .protocolItem)
        XCTAssertFalse(item.isCompleted)
        XCTAssertEqual(item.completionStyle, .oneTap)
    }

    func testDaysOfWeekItemIsDueOnlyOnMatchingWeekdays() {
        let protocols = [
            makeProtocol(items: [makeItem(id: "slides", cadence: .daysOfWeek([2, 4]))])
        ]

        let monday = engine.docket(
            for: date(2026, 8, 31),
            protocols: protocols,
            plans: [],
            sleepDeadline: nil,
            completions: []
        )
        let tuesday = engine.docket(
            for: date(2026, 9, 1),
            protocols: protocols,
            plans: [],
            sleepDeadline: nil,
            completions: []
        )

        XCTAssertEqual(monday.items.count, 1)
        XCTAssertTrue(tuesday.items.isEmpty)
    }

    func testTimesPerWeekCountsCompletionsWithinTheCalendarWeek() {
        let protocols = [
            makeProtocol(items: [makeItem(id: "holds", cadence: .timesPerWeek(2))])
        ]
        let wednesday = date(2026, 9, 2)

        let untouched = engine.docket(
            for: wednesday,
            protocols: protocols,
            plans: [],
            sleepDeadline: nil,
            completions: [completion(day: "2026-08-30", sourceID: "holds")]
        )
        XCTAssertEqual(untouched.items.first?.tag, "PT · 0 of 2")
        XCTAssertEqual(untouched.items.first?.isCompleted, false)

        let satisfiedEarlier = engine.docket(
            for: wednesday,
            protocols: protocols,
            plans: [],
            sleepDeadline: nil,
            completions: [
                completion(day: "2026-08-31", sourceID: "holds"),
                completion(day: "2026-09-01", sourceID: "holds"),
            ]
        )
        XCTAssertTrue(satisfiedEarlier.items.isEmpty)

        let completedToday = engine.docket(
            for: wednesday,
            protocols: protocols,
            plans: [],
            sleepDeadline: nil,
            completions: [
                completion(day: "2026-08-31", sourceID: "holds"),
                completion(day: "2026-09-02", sourceID: "holds"),
            ]
        )
        XCTAssertEqual(completedToday.items.count, 1)
        XCTAssertEqual(completedToday.items.first?.isCompleted, true)
        XCTAssertEqual(completedToday.items.first?.tag, "PT · 2 of 2")
    }

    func testProtocolDateRangeAndArchivalGateItems() {
        let monday = date(2026, 8, 31)
        let items = [makeItem(id: "band", cadence: .daily)]

        let startsTomorrow = makeProtocol(items: items, startedAt: date(2026, 9, 1))
        let endedYesterday = makeProtocol(
            items: items,
            startedAt: date(2026, 8, 1),
            endsAt: date(2026, 8, 30)
        )
        let archived = makeProtocol(items: items, isArchived: true)
        let endsToday = makeProtocol(
            items: items,
            startedAt: date(2026, 8, 1),
            endsAt: monday
        )

        for (therapyProtocol, expected) in [
            (startsTomorrow, 0), (endedYesterday, 0), (archived, 0), (endsToday, 1),
        ] {
            let docket = engine.docket(
                for: monday,
                protocols: [therapyProtocol],
                plans: [],
                sleepDeadline: nil,
                completions: []
            )
            XCTAssertEqual(docket.items.count, expected)
        }
    }

    func testWorkoutRowsMirrorPlanStatusWithoutDocketCompletion() {
        let monday = date(2026, 8, 31)
        let docket = engine.docket(
            for: monday,
            protocols: [],
            plans: [
                makePlan(id: "planned", scheduledAt: monday, status: .planned),
                makePlan(id: "done", scheduledAt: monday, status: .completed),
                makePlan(id: "draft", scheduledAt: monday, status: .draft),
                makePlan(id: "tomorrow", scheduledAt: date(2026, 9, 1), status: .planned),
            ],
            sleepDeadline: nil,
            completions: []
        )

        XCTAssertEqual(docket.items.map(\.sourceID), ["planned", "done"])
        XCTAssertEqual(docket.items.map(\.isCompleted), [false, true])
        XCTAssertTrue(docket.items.allSatisfy { $0.completionStyle == .recordActual })
        XCTAssertTrue(docket.items.allSatisfy { $0.tag == nil })
    }

    func testWorkoutRowsUseRecordActualCompletionStyle() {
        let monday = date(2026, 8, 31)
        let docket = engine.docket(
            for: monday,
            protocols: [],
            plans: [makePlan(id: "squat", scheduledAt: monday, status: .planned)],
            sleepDeadline: nil,
            completions: []
        )

        let item = docket.items.first { $0.sourceID == "squat" }
        XCTAssertEqual(item?.completionStyle, .recordActual)
        XCTAssertNil(item?.prescribedSets)
        XCTAssertNil(item?.recordedActual)
    }

    func testWindDownRowUsesDeadlineTimeAndCompletionState() throws {
        let monday = date(2026, 8, 31)
        let deadline = SleepDeadlineCalculator.calculate(
            now: monday,
            settings: .standard,
            calendar: calendar
        )

        let open = engine.docket(
            for: monday,
            protocols: [],
            plans: [],
            sleepDeadline: deadline,
            completions: []
        )
        let windDown = try XCTUnwrap(open.items.first)
        XCTAssertEqual(windDown.kind, .windDown)
        XCTAssertTrue(windDown.title.hasPrefix("wind down — "))
        XCTAssertFalse(windDown.isCompleted)

        let done = engine.docket(
            for: monday,
            protocols: [],
            plans: [],
            sleepDeadline: deadline,
            completions: [
                DocketCompletion(
                    id: "c1",
                    day: "2026-08-31",
                    kind: .windDown,
                    sourceID: DeterministicDocketEngine.windDownSourceID,
                    protocolID: nil,
                    completedAt: monday
                )
            ]
        )
        XCTAssertEqual(done.items.first?.isCompleted, true)
        XCTAssertEqual(done.items.first?.completionID, "c1")
    }

    func testWeekDaysSpanTheCalendarWeekFromMonday() {
        let week = engine.weekDays(containing: date(2026, 9, 2))
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, "2026-08-31")
        XCTAssertEqual(week.last, "2026-09-06")
        XCTAssertTrue(week.contains("2026-09-02"))
    }

    func testDocketPersistenceUpsertsByNaturalKeyAndDeletes() async throws {
        let container = try ModelContainer(
            for: DocketCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = DocketPersistence(container: container)
        let first = DocketCompletion(
            id: "first",
            day: "2026-08-31",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let duplicate = DocketCompletion(
            id: "second",
            day: "2026-08-31",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: Date(timeIntervalSince1970: 1_700_000_600)
        )
        let otherDay = DocketCompletion(
            id: "other",
            day: "2026-09-01",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: Date(timeIntervalSince1970: 1_700_100_000)
        )

        try await repository.saveCompletion(first)
        try await repository.saveCompletion(duplicate)
        try await repository.saveCompletion(otherDay)

        let mondayOnly = try await repository.completions(days: ["2026-08-31"])
        XCTAssertEqual(mondayOnly.count, 1)
        XCTAssertEqual(mondayOnly.first?.id, "first")
        XCTAssertEqual(
            mondayOnly.first?.completedAt,
            Date(timeIntervalSince1970: 1_700_000_600)
        )

        let bothDays = try await repository.completions(days: ["2026-08-31", "2026-09-01"])
        XCTAssertEqual(bothDays.count, 2)

        try await repository.deleteCompletion(id: "first")
        let remaining = try await repository.completions(days: ["2026-08-31", "2026-09-01"])
        XCTAssertEqual(remaining.map(\.id), ["other"])
    }

    func testDocketPersistenceRejectsIncompleteCompletions() async throws {
        let container = try ModelContainer(
            for: DocketCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = DocketPersistence(container: container)

        do {
            try await repository.saveCompletion(
                DocketCompletion(
                    id: "bad",
                    day: "",
                    kind: .windDown,
                    sourceID: DeterministicDocketEngine.windDownSourceID,
                    protocolID: nil,
                    completedAt: .now
                )
            )
            XCTFail("Expected invalidDay")
        } catch let error as DocketValidationError {
            XCTAssertEqual(error, .invalidDay)
        }
    }

    func testAsPrescribedSnapshotsPrescribedQuantities() {
        let docket = engine.docket(
            for: date(2026, 8, 31),
            protocols: [makeProtocol(items: [makeItem(id: "band", cadence: .daily)])],
            plans: [],
            sleepDeadline: nil,
            completions: []
        )
        let item = docket.items[0]

        let completion = DocketCompletion.asPrescribed(item: item, day: docket.day)

        XCTAssertEqual(completion.actual?.sets, 3)
        XCTAssertEqual(completion.actual?.repetitions, 15)
        XCTAssertNil(completion.actual?.durationSeconds)
        XCTAssertNil(completion.actual?.painDuring)
        XCTAssertEqual(completion.actual?.note, "")
        XCTAssertEqual(completion.actual?.isAsPrescribed, true)
    }

    func testAsPrescribedWithNoPrescriptionStoresNoQuantities() throws {
        let docket = engine.docket(
            for: date(2026, 8, 31),
            protocols: [],
            plans: [],
            sleepDeadline: SleepDeadlineCalculator.calculate(
                now: date(2026, 8, 31),
                settings: .standard,
                calendar: calendar
            ),
            completions: []
        )
        let item = try XCTUnwrap(docket.items.first)

        let completion = DocketCompletion.asPrescribed(item: item, day: docket.day)

        XCTAssertNil(completion.actual?.sets)
        XCTAssertNil(completion.actual?.repetitions)
        XCTAssertNil(completion.actual?.durationSeconds)
        XCTAssertNil(completion.actual?.painDuring)
        XCTAssertEqual(completion.actual?.isAsPrescribed, true)
    }

    func testDeviationStoresEditedActualsAndPain() throws {
        let deviation = DocketCompletion(
            id: "c1",
            day: "2026-08-31",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: date(2026, 8, 31),
            actual: DocketActual(
                sets: 2,
                repetitions: 10,
                durationSeconds: nil,
                painDuring: 3,
                note: "shoulder tight",
                isAsPrescribed: false
            )
        )
        let docket = engine.docket(
            for: date(2026, 8, 31),
            protocols: [makeProtocol(items: [makeItem(id: "band", cadence: .daily)])],
            plans: [],
            sleepDeadline: nil,
            completions: [deviation]
        )

        let item = try XCTUnwrap(docket.items.first)
        XCTAssertEqual(item.recordedActual, deviation.actual)
        XCTAssertEqual(item.recordedActual?.isAsPrescribed, false)
        XCTAssertEqual(item.recordedActual?.painDuring, 3)
    }

    func testLegacyCompletionWithoutActualsStaysTapOnly() throws {
        let legacy = DocketCompletion(
            id: "c1",
            day: "2026-08-31",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: date(2026, 8, 31)
        )
        XCTAssertNil(legacy.actual)

        let docket = engine.docket(
            for: date(2026, 8, 31),
            protocols: [makeProtocol(items: [makeItem(id: "band", cadence: .daily)])],
            plans: [],
            sleepDeadline: nil,
            completions: [legacy]
        )

        let item = try XCTUnwrap(docket.items.first)
        XCTAssertTrue(item.isCompleted)
        XCTAssertNil(item.recordedActual)
    }

    func testDocketItemExposesPrescriptionAndRecordedActual() throws {
        let docket = engine.docket(
            for: date(2026, 8, 31),
            protocols: [makeProtocol(items: [makeItem(id: "band", cadence: .daily)])],
            plans: [],
            sleepDeadline: nil,
            completions: []
        )

        let item = try XCTUnwrap(docket.items.first)
        XCTAssertEqual(item.prescribedSets, 3)
        XCTAssertEqual(item.prescribedRepetitions, 15)
        XCTAssertNil(item.prescribedDurationSeconds)
        XCTAssertNil(item.recordedActual)
    }

    func testDocketPersistenceRoundTripsActualsAndUpsertOverwritesThem() async throws {
        let container = try ModelContainer(
            for: DocketCompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = DocketPersistence(container: container)
        let firstPass = DocketCompletion(
            id: "first",
            day: "2026-08-31",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: date(2026, 8, 31),
            actual: DocketActual(
                sets: 3,
                repetitions: 15,
                durationSeconds: nil,
                painDuring: nil,
                note: "",
                isAsPrescribed: true
            )
        )

        try await repository.saveCompletion(firstPass)
        let roundTripped = try await repository.completions(days: ["2026-08-31"])
        XCTAssertEqual(roundTripped.count, 1)
        XCTAssertEqual(roundTripped.first?.actual, firstPass.actual)

        let corrected = DocketCompletion(
            id: "second",
            day: "2026-08-31",
            kind: .protocolItem,
            sourceID: "band",
            protocolID: "proto",
            completedAt: date(2026, 8, 31, hour: 13),
            actual: DocketActual(
                sets: 2,
                repetitions: 10,
                durationSeconds: nil,
                painDuring: 4,
                note: "adjusted after warm-up",
                isAsPrescribed: false
            )
        )
        try await repository.saveCompletion(corrected)

        let overwritten = try await repository.completions(days: ["2026-08-31"])
        XCTAssertEqual(overwritten.count, 1, "upsert on (day, kind, sourceID) must not duplicate")
        XCTAssertEqual(overwritten.first?.id, "first", "the natural key row's identity is retained")
        XCTAssertEqual(overwritten.first?.actual, corrected.actual)

        let legacy = DocketCompletion(
            id: "legacy",
            day: "2026-09-01",
            kind: .windDown,
            sourceID: DeterministicDocketEngine.windDownSourceID,
            protocolID: nil,
            completedAt: date(2026, 9, 1)
        )
        try await repository.saveCompletion(legacy)
        let legacyRoundTripped = try await repository.completions(days: ["2026-09-01"])
        XCTAssertNil(
            legacyRoundTripped.first?.actual,
            "all-nil columns must not be backfilled into an asserted actual"
        )
    }

    // MARK: - Fixtures

    private func makeItem(
        id: String,
        cadence: ProtocolCadence
    ) -> TherapyProtocolItem {
        TherapyProtocolItem(
            id: id,
            order: 1,
            canonicalMovementID: "band_extension",
            displayName: "Band extensions",
            originalText: "Band extensions 3×15",
            sets: 3,
            repetitions: 15,
            durationSeconds: nil,
            loadValue: nil,
            loadUnit: nil,
            cadence: cadence,
            notes: ""
        )
    }

    private func makeProtocol(
        items: [TherapyProtocolItem],
        startedAt: Date? = nil,
        endsAt: Date? = nil,
        isArchived: Bool = false
    ) -> TherapyProtocol {
        TherapyProtocol(
            id: "proto",
            title: "Tricep protocol",
            source: .photo,
            rawText: "raw",
            phaseNumber: nil,
            phaseCount: nil,
            unlockMilestone: nil,
            startedAt: startedAt ?? date(2026, 8, 1),
            endsAt: endsAt,
            parserVersion: DeterministicProtocolParser.parserVersion,
            confidence: 1,
            isArchived: isArchived,
            createdAt: date(2026, 8, 1),
            items: items
        )
    }

    private func makePlan(
        id: String,
        scheduledAt: Date,
        status: WorkoutPlanStatus
    ) -> WorkoutPlan {
        WorkoutPlan(
            id: id,
            title: "squat day — legs only",
            rawText: "raw",
            parsedAt: scheduledAt,
            scheduledAt: scheduledAt,
            status: status,
            format: .manual,
            intendedStimulus: .unknown,
            timeCapSeconds: nil,
            parserVersion: "manual-1.0.0",
            modelVersion: nil,
            confidence: 1,
            ambiguities: [],
            segments: []
        )
    }

    private func completion(day: String, sourceID: String) -> DocketCompletion {
        DocketCompletion(
            id: UUID().uuidString.lowercased(),
            day: day,
            kind: .protocolItem,
            sourceID: sourceID,
            protocolID: "proto",
            completedAt: date(2026, 8, 31)
        )
    }
}
