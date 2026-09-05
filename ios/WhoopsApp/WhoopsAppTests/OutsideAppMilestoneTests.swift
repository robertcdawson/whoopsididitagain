import XCTest

@testable import WhoopsApp

final class OutsideAppMilestoneTests: XCTestCase {
    func testHomeScreenPainShortcutMapsOnlyItsStableType() {
        XCTAssertEqual(
            HomeScreenQuickAction.route(for: HomeScreenQuickAction.logPainType),
            .painLog
        )
        XCTAssertNil(HomeScreenQuickAction.route(for: "com.example.unknown"))
    }

    func testPendingPainRouteIsConsumedExactlyOnce() throws {
        let suiteName = "PendingPainRoute-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PendingAppRouteStore(defaults: defaults)

        store.save(.painLog)

        XCTAssertEqual(store.consume(), .painLog)
        XCTAssertNil(store.consume())
    }

    func testPendingCompletionIsImmediatelyReflectedInEffectiveSnapshot() throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let item = sharedProtocolItem()
        try store.saveSnapshot(SharedDocketSnapshot(day: "2026-09-01", items: [item]))

        try store.enqueueCompletion(
            for: item,
            day: "2026-09-01",
            at: Date(timeIntervalSince1970: 100)
        )

        let effective = try XCTUnwrap(store.effectiveSnapshot())
        XCTAssertTrue(try XCTUnwrap(effective.items.first).isCompleted)
        XCTAssertEqual(try store.pendingCompletionActions().count, 1)
    }

    func testCoordinatorPersistsThenAcknowledgesOutsideCompletionAfterPublishing() async throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let repository = PreviewDocketRepository()
        let coordinator = OutsideAppDocketCoordinator(repository: repository, store: store)
        let item = sharedProtocolItem()
        try store.saveSnapshot(SharedDocketSnapshot(day: "2026-09-01", items: [item]))
        let action = try store.enqueueCompletion(
            for: item,
            day: "2026-09-01",
            at: Date(timeIntervalSince1970: 100)
        )

        let actionIDs = try await coordinator.reconcilePendingCompletions()
        let completions = try await repository.completions(days: ["2026-09-01"])

        XCTAssertEqual(actionIDs, [action.id])
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.sourceID, "band-work")
        XCTAssertEqual(completions.first?.actual?.sets, 3)
        XCTAssertEqual(completions.first?.actual?.repetitions, 15)
        XCTAssertTrue(completions.first?.actual?.isAsPrescribed == true)
        XCTAssertEqual(try store.pendingCompletionActions().count, 1)

        let completedItem = DocketItem(
            id: item.id,
            kind: .protocolItem,
            sourceID: item.sourceID,
            protocolID: item.protocolID,
            title: item.title,
            tag: item.tag,
            isCompleted: true,
            completionID: completions.first?.id,
            prescribedSets: item.prescribedSets,
            prescribedRepetitions: item.prescribedRepetitions,
            prescribedDurationSeconds: item.prescribedDurationSeconds,
            recordedActual: completions.first?.actual
        )
        try await coordinator.publish(
            DailyDocket(
                day: "2026-09-01",
                rulesetVersion: DeterministicDocketEngine.rulesetVersion,
                items: [completedItem]
            ),
            acknowledging: actionIDs
        )

        XCTAssertTrue(try XCTUnwrap(store.snapshot()).items[0].isCompleted)
        XCTAssertTrue(try store.pendingCompletionActions().isEmpty)
    }

    func testWorkoutCannotBeCompletedThroughOutsideBridge() throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let workout = SharedDocketItem(
            id: "workout:plan",
            kind: "workout",
            sourceID: "plan",
            protocolID: nil,
            title: "evening workout",
            tag: nil,
            isCompleted: false,
            prescribedSets: nil,
            prescribedRepetitions: nil,
            prescribedDurationSeconds: nil
        )

        XCTAssertThrowsError(try store.enqueueCompletion(for: workout, day: "2026-09-01")) {
            XCTAssertEqual($0 as? SharedDocketStoreError, .workoutRequiresApp)
        }
    }

    func testCachedSnapshotIsUnavailableOutsideItsLocalDay() throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let timeZone = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)
        )!
        try store.saveSnapshot(
            SharedDocketSnapshot(day: "2026-08-31", items: [sharedProtocolItem()])
        )

        XCTAssertNil(try store.currentEffectiveSnapshot(now: today, timeZone: timeZone))
    }

    func testShortcutResolverReturnsEveryAmbiguousMatch() {
        let first = sharedProtocolItem()
        let second = SharedDocketItem(
            id: "protocol_item:other-band-work",
            kind: "protocol_item",
            sourceID: "other-band-work",
            protocolID: "other-pt",
            title: first.title,
            tag: first.tag,
            isCompleted: false,
            prescribedSets: 2,
            prescribedRepetitions: 12,
            prescribedDurationSeconds: nil
        )
        let snapshot = SharedDocketSnapshot(day: "2026-09-01", items: [first, second])

        let matches = DocketItemEntityResolver.entities(matching: "band extensions", in: snapshot)

        XCTAssertEqual(Set(matches.map(\.docketItemID)), Set([first.id, second.id]))
    }

    func testShortcutResolverRejectsStaleEntityDay() throws {
        let item = sharedProtocolItem()
        let snapshot = SharedDocketSnapshot(day: "2026-09-02", items: [item])
        let staleEntity = DocketItemEntity(item: item, day: "2026-09-01")

        XCTAssertThrowsError(try DocketItemEntityResolver.item(for: staleEntity, in: snapshot)) {
            XCTAssertEqual($0 as? SharedDocketStoreError, .itemUnavailable)
        }
    }

    func testShortcutEntityIdentifierChangesWithLocalDay() {
        let item = sharedProtocolItem()

        let yesterday = DocketItemEntity(item: item, day: "2026-09-01")
        let today = DocketItemEntity(item: item, day: "2026-09-02")

        XCTAssertNotEqual(yesterday.id, today.id)
        XCTAssertEqual(yesterday.docketItemID, today.docketItemID)
    }

    func testReminderScheduleUsesWakeTimeAndCalculatedWindDownTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)
        )!
        let settings = SleepScheduleSettings(
            wakeHour: 7,
            wakeMinute: 15,
            targetSleepMinutes: 8 * 60,
            sleepLatencyMinutes: 20,
            windDownMinutes: 45
        )

        XCTAssertEqual(
            ReminderScheduleFactory.dailyReminder(
                for: .morningCheckIn,
                settings: settings,
                now: now,
                calendar: calendar
            ),
            DailyReminder(kind: .morningCheckIn, hour: 7, minute: 15)
        )
        XCTAssertEqual(
            ReminderScheduleFactory.dailyReminder(
                for: .windDown,
                settings: settings,
                now: now,
                calendar: calendar
            ),
            DailyReminder(kind: .windDown, hour: 22, minute: 10)
        )
    }

    func testReminderOptInPersistsOnlyAfterPermissionAndScheduling() async throws {
        let scheduler = RecordingReminderScheduler(status: .notDetermined, grantsPermission: true)
        let suite = "OutsideAppMilestoneTests.reminders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = LocalReminderService(
            scheduler: scheduler,
            preferenceStore: ReminderPreferenceStore(defaults: defaults)
        )

        try await service.setEnabled(true, for: .morningCheckIn, settings: .standard)

        let state = await service.state()
        let recorded = await scheduler.recordedDailyReminders()
        XCTAssertTrue(state.0.morningCheckInEnabled)
        XCTAssertEqual(state.1, .allowed)
        XCTAssertEqual(
            recorded,
            [DailyReminder(kind: .morningCheckIn, hour: 7, minute: 15)]
        )
    }

    func testWindDownDoneQueuesSharedCompletionButMorningOpenDoesNot() async throws {
        let (store, rootURL) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let today = SharedDocketDay.localDay(containing: .now)
        let windDown = sharedWindDownItem()
        try store.saveSnapshot(SharedDocketSnapshot(day: today, items: [windDown]))
        let scheduler = RecordingReminderScheduler(status: .allowed, grantsPermission: true)
        let service = LocalReminderService(scheduler: scheduler)
        let handler = ReminderNotificationActionHandler(
            reminderService: service,
            docketStore: store
        )

        let open = try await handler.handle(
            actionIdentifier: ReminderNotificationIdentifiers.openAction,
            categoryIdentifier: ReminderNotificationIdentifiers.morningCategory
        )
        XCTAssertEqual(open, .open(.morningCheckIn))
        XCTAssertTrue(try store.pendingCompletionActions().isEmpty)

        let done = try await handler.handle(
            actionIdentifier: ReminderNotificationIdentifiers.doneAction,
            categoryIdentifier: ReminderNotificationIdentifiers.windDownCategory
        )
        XCTAssertEqual(done, .queuedWindDown)
        XCTAssertEqual(try store.pendingCompletionActions().map(\.item.id), [windDown.id])
    }

    func testLaterActionSchedulesOnlyTheRequestedReminder() async throws {
        let scheduler = RecordingReminderScheduler(status: .allowed, grantsPermission: true)
        let service = LocalReminderService(scheduler: scheduler)
        let handler = ReminderNotificationActionHandler(
            reminderService: service,
            docketStore: nil
        )

        let outcome = try await handler.handle(
            actionIdentifier: ReminderNotificationIdentifiers.laterAction,
            categoryIdentifier: ReminderNotificationIdentifiers.morningCategory
        )

        let snoozes = await scheduler.recordedSnoozes()
        XCTAssertEqual(outcome, .snoozed(.morningCheckIn))
        XCTAssertEqual(snoozes.map(\.0), [.morningCheckIn])
    }

    private func temporaryStore() throws -> (SharedDocketStore, URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoops-outside-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return (SharedDocketStore(rootURL: rootURL), rootURL)
    }

    private func sharedProtocolItem() -> SharedDocketItem {
        SharedDocketItem(
            id: "protocol_item:band-work",
            kind: "protocol_item",
            sourceID: "band-work",
            protocolID: "pt",
            title: "band extensions 3×15",
            tag: "PT",
            isCompleted: false,
            prescribedSets: 3,
            prescribedRepetitions: 15,
            prescribedDurationSeconds: nil
        )
    }

    private func sharedWindDownItem() -> SharedDocketItem {
        SharedDocketItem(
            id: "wind_down:sleep",
            kind: "wind_down",
            sourceID: "sleep",
            protocolID: nil,
            title: "wind down — 10:10 PM",
            tag: nil,
            isCompleted: false,
            prescribedSets: nil,
            prescribedRepetitions: nil,
            prescribedDurationSeconds: nil
        )
    }
}

private actor RecordingReminderScheduler: ReminderScheduling {
    private var status: ReminderAuthorizationStatus
    private let grantsPermission: Bool
    private var dailyReminders: [DailyReminder] = []
    private var snoozes: [(ReminderKind, TimeInterval)] = []

    init(status: ReminderAuthorizationStatus, grantsPermission: Bool) {
        self.status = status
        self.grantsPermission = grantsPermission
    }

    func authorizationStatus() async -> ReminderAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        status = grantsPermission ? .allowed : .denied
        return grantsPermission
    }

    func scheduleDaily(_ reminder: DailyReminder) async throws {
        dailyReminders.append(reminder)
    }

    func scheduleSnooze(for kind: ReminderKind, delay: TimeInterval) async throws {
        snoozes.append((kind, delay))
    }

    func removeDaily(_ kind: ReminderKind) async {}

    func recordedDailyReminders() -> [DailyReminder] { dailyReminders }
    func recordedSnoozes() -> [(ReminderKind, TimeInterval)] { snoozes }
}
