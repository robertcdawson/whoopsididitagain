import Foundation

/// Deterministic generator for the daily docket: today's due protocol items,
/// today's committed workouts, and the sleep wind-down. Recurrence is resolved
/// from stored cadence plus recorded completions — nothing is generated ahead of
/// time and nothing is guessed.
struct DeterministicDocketEngine {
    static let rulesetVersion = "docket-1.1.0"

    let calendar: Calendar
    let timeZone: TimeZone

    init(
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func day(containing date: Date) -> String {
        HealthDayKey.day(containing: date, timeZone: timeZone)
    }

    /// Local-day strings for the calendar week containing `date`, honoring the
    /// calendar's first weekday. Used to count times-per-week completions.
    func weekDays(containing date: Date) -> [String] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [day(containing: date)]
        }
        var days: [String] = []
        var current = week.start
        while current < week.end {
            days.append(day(containing: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    func docket(
        for date: Date,
        protocols: [TherapyProtocol],
        plans: [WorkoutPlan],
        sleepDeadline: SleepDeadline?,
        completions: [DocketCompletion]
    ) -> DailyDocket {
        let today = day(containing: date)
        let weekday = calendar.component(.weekday, from: date)
        let week = weekDays(containing: date)
        let todayCompletions = completions.filter { $0.day == today }
        var items: [DocketItem] = []

        for therapyProtocol in protocols where isActive(therapyProtocol, on: today) {
            for item in therapyProtocol.items {
                let completion = todayCompletions.first {
                    $0.kind == .protocolItem && $0.sourceID == item.id
                }
                var tag = "PT"
                let isDue: Bool
                switch item.cadence {
                case .daily:
                    isDue = true
                case .daysOfWeek(let days):
                    isDue = days.contains(weekday)
                case .timesPerWeek(let target):
                    let weekCount = completions.filter {
                        $0.kind == .protocolItem && $0.sourceID == item.id
                            && week.contains($0.day)
                    }.count
                    isDue = weekCount < target
                    tag += " · \(min(weekCount, target)) of \(target)"
                }
                guard isDue || completion != nil else { continue }
                items.append(
                    DocketItem(
                        id: "\(DocketItemKind.protocolItem.rawValue):\(item.id)",
                        kind: .protocolItem,
                        sourceID: item.id,
                        protocolID: therapyProtocol.id,
                        title: protocolItemTitle(item),
                        tag: tag,
                        isCompleted: completion != nil,
                        completionID: completion?.id,
                        prescribedSets: item.sets,
                        prescribedRepetitions: item.repetitions,
                        prescribedDurationSeconds: item.durationSeconds,
                        recordedActual: completion?.actual
                    )
                )
            }
        }

        for plan in plans
        where plan.status != .draft && day(containing: plan.scheduledAt) == today {
            items.append(
                DocketItem(
                    id: "\(DocketItemKind.workout.rawValue):\(plan.id)",
                    kind: .workout,
                    sourceID: plan.id,
                    protocolID: nil,
                    title: plan.title,
                    tag: nil,
                    isCompleted: plan.status == .completed,
                    completionID: nil,
                    prescribedSets: nil,
                    prescribedRepetitions: nil,
                    prescribedDurationSeconds: nil,
                    recordedActual: nil
                )
            )
        }

        if let sleepDeadline {
            let completion = todayCompletions.first {
                $0.kind == .windDown && $0.sourceID == Self.windDownSourceID
            }
            var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
            timeStyle.timeZone = timeZone
            let time = sleepDeadline.windDownAt.formatted(timeStyle)
            items.append(
                DocketItem(
                    id: "\(DocketItemKind.windDown.rawValue):\(Self.windDownSourceID)",
                    kind: .windDown,
                    sourceID: Self.windDownSourceID,
                    protocolID: nil,
                    title: "wind down — \(time)",
                    tag: nil,
                    isCompleted: completion != nil,
                    completionID: completion?.id,
                    prescribedSets: nil,
                    prescribedRepetitions: nil,
                    prescribedDurationSeconds: nil,
                    recordedActual: completion?.actual
                )
            )
        }

        return DailyDocket(day: today, rulesetVersion: Self.rulesetVersion, items: items)
    }

    static let windDownSourceID = "sleep"

    private func isActive(_ therapyProtocol: TherapyProtocol, on today: String) -> Bool {
        guard !therapyProtocol.isArchived else { return false }
        guard day(containing: therapyProtocol.startedAt) <= today else { return false }
        if let endsAt = therapyProtocol.endsAt {
            return today <= day(containing: endsAt)
        }
        return true
    }

    private func protocolItemTitle(_ item: TherapyProtocolItem) -> String {
        let name = item.displayName.lowercased()
        guard let summary = item.prescriptionSummary else { return name }
        return "\(name) \(summary)"
    }
}
