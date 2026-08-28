import Foundation

struct DeterministicTrendsEngine: Sendable {
    static let version = "trends-1.0.0"

    func analyze(
        _ input: TrendsInput,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TrendsSnapshot {
        let recovery = metric(
            id: "whoop-recovery",
            title: "Recovery",
            unit: "%",
            source: "WHOOP",
            values: input.whoop.recoveries.compactMap { item in
                item.recoveryScore.map { (item.id, item.timestamp, Double($0)) }
            }
        )
        let restingHeartRate = metric(
            id: "whoop-resting-heart-rate",
            title: "Resting heart rate",
            unit: "bpm",
            source: "WHOOP",
            values: input.whoop.recoveries.compactMap { item in
                item.restingHeartRate.map { (item.id, item.timestamp, Double($0)) }
            }
        )
        let hrv = metric(
            id: "whoop-hrv-rmssd",
            title: "HRV RMSSD",
            unit: "ms",
            source: "WHOOP",
            values: input.whoop.recoveries.compactMap { item in
                item.hrvRMSSD.map { (item.id, item.timestamp, $0) }
            }
        )
        let appleHRV = metric(
            id: "apple-hrv-sdnn",
            title: "HRV SDNN",
            unit: "ms",
            source: "Apple Health",
            values: input.healthKit.days.compactMap { day in
                guard let date = dayDate(day.day, calendar: calendar),
                    let value = day.hrvSDNNMilliseconds
                else { return nil }
                return (day.id, date, value)
            }
        )
        let appleRestingHeartRate = metric(
            id: "apple-resting-heart-rate",
            title: "Resting heart rate",
            unit: "bpm",
            source: "Apple Health",
            values: input.healthKit.days.compactMap { day in
                guard let date = dayDate(day.day, calendar: calendar),
                    let value = day.restingHeartRate
                else { return nil }
                return (day.id, date, value)
            }
        )
        let respiratoryRate = metric(
            id: "apple-respiratory-rate",
            title: "Respiratory rate",
            unit: "breaths/min",
            source: "Apple Health",
            values: input.healthKit.days.compactMap { day in
                guard let date = dayDate(day.day, calendar: calendar),
                    let value = day.respiratoryRate
                else { return nil }
                return (day.id, date, value)
            }
        )
        let oxygenSaturation = metric(
            id: "apple-oxygen-saturation",
            title: "Oxygen saturation",
            unit: "%",
            source: "Apple Health",
            values: input.healthKit.days.compactMap { day in
                guard let date = dayDate(day.day, calendar: calendar),
                    let value = day.oxygenSaturationPercent
                else { return nil }
                return (day.id, date, value)
            }
        )

        let sleep = sleepMetric(input: input, calendar: calendar)
        let loads = trainingLoads(input.workouts, calendar: calendar)
        let windows = weeklyWindows(now: input.generatedAt, calendar: calendar)
        let currentWorkouts = input.workouts.filter {
            windows.current.contains($0.startedAt)
        }
        let priorWorkouts = input.workouts.filter {
            windows.prior.contains($0.startedAt)
        }
        let currentLoad = currentWorkouts.reduce(0) { $0 + sessionLoad($1) }
        let priorLoad = priorWorkouts.reduce(0) { $0 + sessionLoad($1) }
        let metrics = [
            recovery,
            restingHeartRate,
            hrv,
            appleHRV,
            appleRestingHeartRate,
            respiratoryRate,
            oxygenSaturation,
        ]
        let physiologyCount = Set(
            metrics.flatMap(\.points).filter { windows.current.contains($0.date) }.map {
                calendar.startOfDay(for: $0.date)
            }
        ).count
        let currentCheckIns = input.checkIns.filter { windows.current.contains($0.timestamp) }
        let review = weeklyReview(
            windows: windows,
            currentWorkouts: currentWorkouts,
            priorWorkouts: priorWorkouts,
            currentLoad: currentLoad,
            priorLoad: priorLoad,
            recovery: recovery,
            sleep: sleep,
            physiologyCount: physiologyCount,
            checkIns: currentCheckIns
        )

        return TrendsSnapshot(
            generatedAt: input.generatedAt,
            recoveryMetrics: metrics,
            sleep: sleep,
            dailyTrainingLoads: loads,
            currentTrainingLoad: currentLoad,
            priorTrainingLoad: priorLoad,
            strengthVolumes: strengthVolumes(input.workouts),
            painByMovement: painSummaries(input.workouts),
            injuries: input.injuries,
            weeklyReview: review
        )
    }

    private func metric(
        id: String,
        title: String,
        unit: String,
        source: String,
        values: [(String, Date, Double)]
    ) -> MetricTrendSummary {
        let points =
            values
            .filter { $0.2.isFinite }
            .sorted { $0.1 < $1.1 }
            .map { TrendPoint(id: $0.0, date: $0.1, value: $0.2, source: source) }
        return metricSummary(
            id: id,
            title: title,
            unit: unit,
            source: source,
            points: points
        )
    }

    private func metricSummary(
        id: String,
        title: String,
        unit: String,
        source: String,
        points: [TrendPoint]
    ) -> MetricTrendSummary {
        let latest = points.last?.value
        let baseline = RobustBaseline.calculate(Array(points.dropLast().map(\.value)))
        return MetricTrendSummary(
            id: id,
            title: title,
            unit: unit,
            source: source,
            points: points,
            latestValue: latest,
            baselineMedian: baseline?.median,
            changeFromBaseline: latest.flatMap { value in baseline.map { value - $0.median } },
            robustDeviation: latest.flatMap { value in baseline?.robustDeviation(of: value) },
            observationCount: points.count
        )
    }

    private func sleepMetric(input: TrendsInput, calendar: Calendar) -> MetricTrendSummary {
        var pointsByDay: [Date: TrendPoint] = [:]
        for day in input.healthKit.days {
            guard let date = dayDate(day.day, calendar: calendar), let minutes = day.sleepMinutes
            else { continue }
            let localDay = calendar.startOfDay(for: date)
            pointsByDay[localDay] = TrendPoint(
                id: "apple-sleep:\(day.id)",
                date: localDay,
                value: Double(minutes),
                source: "Apple Health"
            )
        }
        for item in input.whoop.sleeps {
            guard !item.isNap, let minutes = item.sleepMinutes else { continue }
            let localDay = calendar.startOfDay(for: item.end ?? item.start)
            pointsByDay[localDay] = TrendPoint(
                id: "whoop-sleep:\(item.id)",
                date: localDay,
                value: Double(minutes),
                source: "WHOOP"
            )
        }
        let points = pointsByDay.values.sorted { $0.date < $1.date }
        let sources = Set(points.map(\.source))
        let source =
            sources.count > 1 ? "WHOOP + Apple Health fallback" : sources.first ?? "WHOOP"
        return metricSummary(
            id: "sleep-duration",
            title: "Sleep duration",
            unit: "min",
            source: source,
            points: points
        )
    }

    private func trainingLoads(
        _ workouts: [CompletedWorkout],
        calendar: Calendar
    ) -> [DailyTrainingLoad] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return Dictionary(grouping: workouts, by: { formatter.string(from: $0.startedAt) })
            .map { day, sessions in
                DailyTrainingLoad(
                    day: day,
                    minutes: sessions.reduce(0) { $0 + durationMinutes($1) },
                    sessionRPE: sessions.map(\.sessionRPE).max() ?? 0,
                    load: sessions.reduce(0) { $0 + sessionLoad($1) }
                )
            }
            .sorted { $0.day < $1.day }
    }

    private func strengthVolumes(_ workouts: [CompletedWorkout]) -> [StrengthVolumeSummary] {
        struct Key: Hashable {
            let movement: String
            let unit: String
        }
        var values: [Key: (volume: Double, sets: Int)] = [:]
        for movement in workouts.flatMap(\.movements) {
            guard let repetitions = movement.actualRepetitions,
                let load = movement.actualLoadValue,
                let unit = movement.actualLoadUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
                !unit.isEmpty
            else { continue }
            let key = Key(movement: movement.displayName, unit: unit)
            let current = values[key, default: (0, 0)]
            values[key] = (current.volume + Double(repetitions) * load, current.sets + 1)
        }
        return values.map { key, value in
            StrengthVolumeSummary(
                movement: key.movement,
                unit: key.unit,
                volume: value.volume,
                entryCount: value.sets
            )
        }.sorted { $0.volume > $1.volume }
    }

    private func painSummaries(_ workouts: [CompletedWorkout]) -> [PainByMovementSummary] {
        struct Entry {
            let pain: Int
            let date: Date
        }
        var entries: [String: [Entry]] = [:]
        for workout in workouts {
            for movement in workout.movements {
                entries[movement.displayName, default: []].append(
                    Entry(pain: movement.painDuring, date: workout.endedAt)
                )
            }
        }
        return entries.compactMap { movement, values in
            guard let latest = values.map(\.date).max() else { return nil }
            return PainByMovementSummary(
                movement: movement,
                observationCount: values.count,
                averagePain: Double(values.reduce(0) { $0 + $1.pain }) / Double(values.count),
                maximumPain: values.map(\.pain).max() ?? 0,
                latestAt: latest
            )
        }.sorted {
            if $0.averagePain == $1.averagePain { return $0.latestAt > $1.latestAt }
            return $0.averagePain > $1.averagePain
        }
    }

    private func weeklyReview(
        windows: (current: Range<Date>, prior: Range<Date>),
        currentWorkouts: [CompletedWorkout],
        priorWorkouts: [CompletedWorkout],
        currentLoad: Double,
        priorLoad: Double,
        recovery: MetricTrendSummary,
        sleep: MetricTrendSummary,
        physiologyCount: Int,
        checkIns: [MorningCheckIn]
    ) -> WeeklyReview {
        let importantChange: String
        if currentWorkouts.isEmpty && priorWorkouts.isEmpty {
            importantChange =
                "Insufficient workout data: 0 sessions were recorded in either seven-day window."
        } else if priorLoad > 0 {
            let percent = ((currentLoad - priorLoad) / priorLoad) * 100
            importantChange =
                "Training load was \(signed(percent))% versus the prior seven days (n=\(currentWorkouts.count) vs n=\(priorWorkouts.count) sessions)."
        } else {
            importantChange =
                "Training load was \(whole(currentLoad)) this week from n=\(currentWorkouts.count) sessions; the prior window had no comparable load."
        }

        let plausibleExplanation: String
        if recovery.observationCount >= 3, sleep.observationCount >= 3,
            let recoveryChange = recovery.changeFromBaseline,
            let sleepChange = sleep.changeFromBaseline
        {
            plausibleExplanation =
                "The latest recovery (n=\(recovery.observationCount)) and sleep duration (n=\(sleep.observationCount)) coincided with changes of \(signed(recoveryChange)) percentage points and \(signed(sleepChange)) minutes from their separate baselines. This is an association, not a cause."
        } else {
            plausibleExplanation =
                "Insufficient physiology data for a comparison: recovery n=\(recovery.observationCount), sleep n=\(sleep.observationCount)."
        }

        let averagePain =
            checkIns.isEmpty
            ? nil : Double(checkIns.reduce(0) { $0 + $1.painWithMovement }) / Double(checkIns.count)
        let nextAction: String
        if let averagePain, averagePain >= 3 {
            nextAction =
                "Review active restrictions before training; movement pain averaged \(oneDecimal(averagePain))/10 across n=\(checkIns.count) check-ins."
        } else if !currentWorkouts.isEmpty {
            nextAction =
                "Use the recorded load as context for the next plan and continue the morning check-in (n=\(checkIns.count) this week)."
        } else {
            nextAction =
                "Record completed workouts and morning check-ins before changing training based on this report (workouts n=0, check-ins n=\(checkIns.count))."
        }

        return WeeklyReview(
            version: Self.version,
            periodStart: windows.current.lowerBound,
            periodEnd: windows.current.upperBound,
            importantChange: importantChange,
            plausibleExplanation: plausibleExplanation,
            nextAction: nextAction,
            caveat:
                "Descriptive only. The report uses local records, keeps WHOOP and Apple HRV definitions separate, and does not diagnose injury or readiness.",
            currentWorkoutCount: currentWorkouts.count,
            priorWorkoutCount: priorWorkouts.count,
            physiologyObservationCount: physiologyCount,
            checkInCount: checkIns.count
        )
    }

    private func weeklyWindows(
        now: Date,
        calendar: Calendar
    ) -> (current: Range<Date>, prior: Range<Date>) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let currentStart = calendar.date(byAdding: .day, value: -7, to: tomorrow)!
        let priorStart = calendar.date(byAdding: .day, value: -7, to: currentStart)!
        return (currentStart..<tomorrow, priorStart..<currentStart)
    }

    private func sessionLoad(_ workout: CompletedWorkout) -> Double {
        durationMinutes(workout) * Double(max(0, workout.sessionRPE))
    }

    private func durationMinutes(_ workout: CompletedWorkout) -> Double {
        max(0, workout.endedAt.timeIntervalSince(workout.startedAt) / 60)
    }

    private func dayDate(_ day: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private func whole(_ value: Double) -> String { String(format: "%.0f", value) }
    private func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }
}

enum TrendsExporter {
    static func write(input: TrendsInput, snapshot: TrendsSnapshot) throws -> TrendsExportFiles {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoops-trends-export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = filenameString(snapshot.generatedAt)
        let jsonURL = directory.appendingPathComponent("whoops-export-\(stamp).json")
        let csvURL = directory.appendingPathComponent("whoops-export-\(stamp).csv")
        try jsonData(input: input, snapshot: snapshot).write(to: jsonURL, options: .atomic)
        try csvData(input: input, snapshot: snapshot).write(to: csvURL, options: .atomic)
        return TrendsExportFiles(jsonURL: jsonURL, csvURL: csvURL)
    }

    static func jsonData(input: TrendsInput, snapshot: TrendsSnapshot) throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": "normalized-export-1.0.0",
            "generatedAt": isoString(snapshot.generatedAt),
            "privacy":
                "Normalized user-visible records only. No OAuth tokens, API keys, Keychain values, or raw WHOOP payloads.",
            "weeklyReview": try encodableObject(snapshot.weeklyReview),
            "recoveries": input.whoop.recoveries.map {
                compact([
                    "id": $0.id,
                    "timestamp": isoString($0.timestamp),
                    "recoveryScore": $0.recoveryScore,
                    "restingHeartRate": $0.restingHeartRate,
                    "hrvRMSSD": $0.hrvRMSSD,
                ])
            },
            "whoopSleeps": input.whoop.sleeps.map {
                compact([
                    "id": $0.id,
                    "start": isoString($0.start),
                    "end": $0.end.map(isoString),
                    "isNap": $0.isNap,
                    "sleepPerformance": $0.sleepPerformance,
                    "sleepMinutes": $0.sleepMinutes,
                ])
            },
            "healthKitDays": input.healthKit.days.map {
                compact([
                    "day": $0.day,
                    "restingHeartRate": $0.restingHeartRate,
                    "hrvSDNNMilliseconds": $0.hrvSDNNMilliseconds,
                    "respiratoryRate": $0.respiratoryRate,
                    "oxygenSaturationPercent": $0.oxygenSaturationPercent,
                    "sleepMinutes": $0.sleepMinutes,
                    "activeEnergyKilocalories": $0.activeEnergyKilocalories,
                    "exerciseMinutes": $0.exerciseMinutes,
                    "workoutCount": $0.workoutCount,
                    "sources": $0.sources,
                ])
            },
            "morningCheckIns": input.checkIns.map {
                compact([
                    "day": $0.day,
                    "timestamp": isoString($0.timestamp),
                    "painAtRest": $0.painAtRest,
                    "painWithMovement": $0.painWithMovement,
                    "stiffness": $0.stiffness,
                    "swelling": $0.swelling,
                    "perceivedWeakness": $0.perceivedWeakness,
                    "energy": $0.energy,
                    "motivation": $0.motivation,
                    "illnessSymptoms": $0.illnessSymptoms,
                    "notes": $0.notes,
                ])
            },
            "assessments": input.assessments.map {
                compact([
                    "id": $0.id,
                    "day": $0.day,
                    "computedAt": isoString($0.computedAt),
                    "recommendation": $0.recommendation.rawValue,
                    "effectiveRecommendation": $0.effectiveRecommendation.rawValue,
                    "confidence": $0.confidence.rawValue,
                    "reasonCodes": $0.reasonCodes,
                    "rulesetVersion": $0.rulesetVersion,
                    "overrideNote": $0.overrideNote,
                ])
            },
            "restrictions": input.restrictions.map {
                compact([
                    "id": $0.id,
                    "injuryName": $0.injuryName,
                    "bodyRegion": $0.bodyRegion,
                    "side": $0.side,
                    "movementTag": $0.movementTag,
                    "level": $0.level.rawValue,
                    "painThreshold": $0.painThreshold,
                    "rationale": $0.rationale,
                    "isActive": $0.isActive,
                ])
            },
            "injuries": try input.injuries.map(encodableObject),
            "workoutPlans": input.plans.map {
                compact([
                    "id": $0.id,
                    "title": $0.title,
                    "scheduledAt": isoString($0.scheduledAt),
                    "status": $0.status.rawValue,
                    "format": $0.format.rawValue,
                    "rawText": $0.rawText,
                ])
            },
            "completedWorkouts": input.workouts.map {
                compact([
                    "id": $0.id,
                    "plannedWorkoutID": $0.plannedWorkoutID,
                    "title": $0.title,
                    "startedAt": isoString($0.startedAt),
                    "endedAt": isoString($0.endedAt),
                    "sessionRPE": $0.sessionRPE,
                    "postSessionPain": $0.postSessionPain,
                    "notes": $0.notes,
                    "movements": (try? $0.movements.map(encodableObject)) ?? [],
                ])
            },
        ]
        return try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func csvData(input: TrendsInput, snapshot: TrendsSnapshot) -> Data {
        var rows = [["record_type", "date", "name", "value", "unit", "source", "notes"]]
        for metric in snapshot.recoveryMetrics + [snapshot.sleep] {
            rows += metric.points.map {
                [
                    "metric", isoString($0.date), metric.title, String($0.value), metric.unit,
                    $0.source, "",
                ]
            }
        }
        rows += snapshot.dailyTrainingLoads.map {
            [
                "training_load", $0.day, "Session load", String($0.load), "minutes_x_RPE",
                "Local workout log", "RPE \($0.sessionRPE)",
            ]
        }
        rows += input.checkIns.map {
            [
                "check_in", $0.day, "Pain with movement", String($0.painWithMovement), "0-10",
                "Morning check-in", $0.notes,
            ]
        }
        for workout in input.workouts {
            rows.append([
                "workout", isoString(workout.startedAt), workout.title, String(workout.sessionRPE),
                "RPE", "Local workout log", workout.notes,
            ])
            rows += workout.movements.map {
                [
                    "movement", isoString(workout.startedAt), $0.displayName, String($0.painDuring),
                    "pain_0-10", "Local workout log", $0.notes,
                ]
            }
        }
        let csv =
            rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
        return Data(csv.utf8)
    }

    private static func encodableObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder.withISO8601.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func compact(_ values: [String: Any?]) -> [String: Any] {
        values.compactMapValues { $0 }
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func filenameString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

extension JSONEncoder {
    fileprivate static var withISO8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
