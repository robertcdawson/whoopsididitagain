import Foundation
import UIKit
import UserNotifications
import WidgetKit

enum ReminderKind: String, CaseIterable, Sendable {
    case morningCheckIn = "morning-check-in"
    case windDown = "wind-down"

    var dailyRequestIdentifier: String { "whoops.reminder.\(rawValue)" }
    var snoozeRequestIdentifier: String { "\(dailyRequestIdentifier).snooze" }

    var categoryIdentifier: String {
        switch self {
        case .morningCheckIn: ReminderNotificationIdentifiers.morningCategory
        case .windDown: ReminderNotificationIdentifiers.windDownCategory
        }
    }

    var title: String {
        switch self {
        case .morningCheckIn: "Morning check-in"
        case .windDown: "Begin wind-down"
        }
    }

    var body: String {
        switch self {
        case .morningCheckIn: "A quick check-in keeps today’s recommendation honest."
        case .windDown: "Your sleep schedule says it’s time to call the day."
        }
    }
}

enum ReminderAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

struct ReminderPreferences: Equatable, Sendable {
    var morningCheckInEnabled: Bool
    var windDownEnabled: Bool

    static let disabled = ReminderPreferences(
        morningCheckInEnabled: false,
        windDownEnabled: false
    )

    func isEnabled(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .morningCheckIn: morningCheckInEnabled
        case .windDown: windDownEnabled
        }
    }

    mutating func setEnabled(_ enabled: Bool, for kind: ReminderKind) {
        switch kind {
        case .morningCheckIn: morningCheckInEnabled = enabled
        case .windDown: windDownEnabled = enabled
        }
    }
}

struct DailyReminder: Equatable, Sendable {
    let kind: ReminderKind
    let hour: Int
    let minute: Int
}

enum ReminderScheduleFactory {
    static func dailyReminder(
        for kind: ReminderKind,
        settings: SleepScheduleSettings,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DailyReminder {
        switch kind {
        case .morningCheckIn:
            return DailyReminder(
                kind: kind,
                hour: settings.wakeHour,
                minute: settings.wakeMinute
            )
        case .windDown:
            let deadline = SleepDeadlineCalculator.calculate(
                now: now,
                settings: settings,
                calendar: calendar
            )
            let components = calendar.dateComponents([.hour, .minute], from: deadline.windDownAt)
            return DailyReminder(
                kind: kind,
                hour: components.hour ?? 0,
                minute: components.minute ?? 0
            )
        }
    }
}

protocol ReminderScheduling: Sendable {
    func authorizationStatus() async -> ReminderAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func scheduleDaily(_ reminder: DailyReminder) async throws
    func scheduleSnooze(for kind: ReminderKind, delay: TimeInterval) async throws
    func removeDaily(_ kind: ReminderKind) async
}

final class UserNotificationReminderScheduler: ReminderScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> ReminderAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func scheduleDaily(_ reminder: DailyReminder) async throws {
        center.removePendingNotificationRequests(
            withIdentifiers: [reminder.kind.dailyRequestIdentifier]
        )
        let content = Self.content(for: reminder.kind)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: reminder.hour, minute: reminder.minute),
            repeats: true
        )
        try await center.add(
            UNNotificationRequest(
                identifier: reminder.kind.dailyRequestIdentifier,
                content: content,
                trigger: trigger
            )
        )
    }

    func scheduleSnooze(for kind: ReminderKind, delay: TimeInterval) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [kind.snoozeRequestIdentifier])
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(delay, 60),
            repeats: false
        )
        try await center.add(
            UNNotificationRequest(
                identifier: kind.snoozeRequestIdentifier,
                content: Self.content(for: kind),
                trigger: trigger
            )
        )
    }

    func removeDaily(_ kind: ReminderKind) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [kind.dailyRequestIdentifier, kind.snoozeRequestIdentifier]
        )
    }

    static func registerCategories(on center: UNUserNotificationCenter = .current()) {
        let done = UNNotificationAction(
            identifier: ReminderNotificationIdentifiers.doneAction,
            title: "Done"
        )
        let later = UNNotificationAction(
            identifier: ReminderNotificationIdentifiers.laterAction,
            title: "Later"
        )
        let open = UNNotificationAction(
            identifier: ReminderNotificationIdentifiers.openAction,
            title: "Open check-in",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: ReminderNotificationIdentifiers.windDownCategory,
                actions: [done, later],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: ReminderNotificationIdentifiers.morningCategory,
                actions: [open, later],
                intentIdentifiers: []
            ),
        ])
    }

    private static func content(for kind: ReminderKind) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body
        content.sound = .default
        content.categoryIdentifier = kind.categoryIdentifier
        content.userInfo = [ReminderNotificationIdentifiers.kindKey: kind.rawValue]
        return content
    }
}

struct ReminderPreferenceStore: @unchecked Sendable {
    private enum Key {
        static let morning = "morningCheckInReminderEnabled"
        static let windDown = "windDownReminderEnabled"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preferences() -> ReminderPreferences {
        ReminderPreferences(
            morningCheckInEnabled: defaults.bool(forKey: Key.morning),
            windDownEnabled: defaults.bool(forKey: Key.windDown)
        )
    }

    func save(_ preferences: ReminderPreferences) {
        defaults.set(preferences.morningCheckInEnabled, forKey: Key.morning)
        defaults.set(preferences.windDownEnabled, forKey: Key.windDown)
    }
}

enum LocalReminderServiceError: LocalizedError, Equatable, Sendable {
    case notificationsDisabled

    var errorDescription: String? {
        "Notifications are disabled for WHOOPs in iPhone Settings."
    }
}

actor LocalReminderService {
    private let scheduler: any ReminderScheduling
    private let preferenceStore: ReminderPreferenceStore

    init(
        scheduler: any ReminderScheduling = UserNotificationReminderScheduler(),
        preferenceStore: ReminderPreferenceStore = ReminderPreferenceStore()
    ) {
        self.scheduler = scheduler
        self.preferenceStore = preferenceStore
    }

    static func live() -> LocalReminderService { LocalReminderService() }

    func state() async -> (ReminderPreferences, ReminderAuthorizationStatus) {
        (preferenceStore.preferences(), await scheduler.authorizationStatus())
    }

    func setEnabled(
        _ enabled: Bool,
        for kind: ReminderKind,
        settings: SleepScheduleSettings
    ) async throws {
        var preferences = preferenceStore.preferences()
        if enabled {
            var status = await scheduler.authorizationStatus()
            if status == .notDetermined {
                let granted = try await scheduler.requestAuthorization()
                status = granted ? .allowed : .denied
            }
            guard status == .allowed else {
                throw LocalReminderServiceError.notificationsDisabled
            }
            try await scheduler.scheduleDaily(
                ReminderScheduleFactory.dailyReminder(for: kind, settings: settings)
            )
        } else {
            await scheduler.removeDaily(kind)
        }
        preferences.setEnabled(enabled, for: kind)
        preferenceStore.save(preferences)
    }

    func refreshEnabledSchedules(settings: SleepScheduleSettings) async {
        guard await scheduler.authorizationStatus() == .allowed else { return }
        let preferences = preferenceStore.preferences()
        for kind in ReminderKind.allCases where preferences.isEnabled(kind) {
            try? await scheduler.scheduleDaily(
                ReminderScheduleFactory.dailyReminder(for: kind, settings: settings)
            )
        }
    }

    func snooze(_ kind: ReminderKind, delay: TimeInterval = 15 * 60) async throws {
        try await scheduler.scheduleSnooze(for: kind, delay: delay)
    }
}

enum ReminderNotificationIdentifiers {
    static let morningCategory = "WHOOPS_MORNING_CHECK_IN"
    static let windDownCategory = "WHOOPS_WIND_DOWN"
    static let openAction = "WHOOPS_OPEN"
    static let doneAction = "WHOOPS_DONE"
    static let laterAction = "WHOOPS_LATER"
    static let kindKey = "whoopsReminderKind"
}

enum PendingAppRoute: String, Equatable, Sendable {
    case today
    case morningCheckIn
    case painLog
}

enum HomeScreenQuickAction {
    static let logPainType = "com.robertcdawson.whoops.log-pain"

    static func route(for shortcutType: String) -> PendingAppRoute? {
        shortcutType == logPainType ? .painLog : nil
    }
}

struct PendingAppRouteStore: @unchecked Sendable {
    static let routeRequested = Notification.Name("WhoopsPendingAppRouteRequested")

    private static let key = "pendingAppRoute"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ route: PendingAppRoute) {
        defaults.set(route.rawValue, forKey: Self.key)
        NotificationCenter.default.post(name: Self.routeRequested, object: nil)
    }

    func consume() -> PendingAppRoute? {
        guard let value = defaults.string(forKey: Self.key),
            let route = PendingAppRoute(rawValue: value)
        else { return nil }
        defaults.removeObject(forKey: Self.key)
        return route
    }
}

enum ReminderActionOutcome: Equatable, Sendable {
    case none
    case queuedWindDown
    case snoozed(ReminderKind)
    case open(PendingAppRoute)
}

struct ReminderNotificationActionHandler: Sendable {
    let reminderService: LocalReminderService
    let docketStore: SharedDocketStore?

    init(
        reminderService: LocalReminderService = .live(),
        docketStore: SharedDocketStore? = SharedDocketStore.live()
    ) {
        self.reminderService = reminderService
        self.docketStore = docketStore
    }

    func handle(actionIdentifier: String, categoryIdentifier: String) async throws
        -> ReminderActionOutcome
    {
        switch (categoryIdentifier, actionIdentifier) {
        case (
            ReminderNotificationIdentifiers.windDownCategory,
            ReminderNotificationIdentifiers.doneAction
        ):
            guard let docketStore,
                let snapshot = try docketStore.currentEffectiveSnapshot(),
                let item = snapshot.items.first(where: {
                    $0.kind == DocketItemKind.windDown.rawValue
                        && !$0.isCompleted
                        && $0.supportsOneTapCompletion
                })
            else { throw SharedDocketStoreError.itemUnavailable }
            try docketStore.enqueueCompletion(for: item, day: snapshot.day)
            WidgetCenter.shared.reloadTimelines(ofKind: WhoopsWidgetConstants.kind)
            return .queuedWindDown

        case (
            ReminderNotificationIdentifiers.windDownCategory,
            ReminderNotificationIdentifiers.laterAction
        ):
            try await reminderService.snooze(.windDown)
            return .snoozed(.windDown)

        case (
            ReminderNotificationIdentifiers.morningCategory,
            ReminderNotificationIdentifiers.laterAction
        ):
            try await reminderService.snooze(.morningCheckIn)
            return .snoozed(.morningCheckIn)

        case (
            ReminderNotificationIdentifiers.morningCategory,
            ReminderNotificationIdentifiers.openAction
        ),
            (
                ReminderNotificationIdentifiers.morningCategory,
                UNNotificationDefaultActionIdentifier
            ):
            return .open(.morningCheckIn)

        case (
            ReminderNotificationIdentifiers.windDownCategory,
            UNNotificationDefaultActionIdentifier
        ):
            return .open(.today)

        default:
            return .none
        }
    }
}

final class ReminderNotificationDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        UserNotificationReminderScheduler.registerCategories(on: center)
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem,
            let route = HomeScreenQuickAction.route(for: shortcut.type)
        {
            PendingAppRouteStore().save(route)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let route = HomeScreenQuickAction.route(for: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        PendingAppRouteStore().save(route)
        completionHandler(true)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let outcome = try? await ReminderNotificationActionHandler().handle(
                actionIdentifier: response.actionIdentifier,
                categoryIdentifier: response.notification.request.content.categoryIdentifier
            )
        else { return }
        if case .open(let route) = outcome {
            await MainActor.run {
                PendingAppRouteStore().save(route)
            }
        }
    }
}
