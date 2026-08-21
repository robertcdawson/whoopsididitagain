import Foundation
import SwiftData

@Model
final class HealthKitSourceRecord {
    @Attribute(.unique) var id: String
    var sampleIdentifier: String
    var metric: String
    var startAt: Date
    var endAt: Date
    var value: Double?
    var unit: String?
    var categoryValue: Int?
    var workoutActivityType: Int?
    var sourceName: String
    var sourceBundleIdentifier: String
    var timeZoneIdentifier: String
    var timeZoneOffsetSeconds: Int
    var localDay: String
    var lastImportedAt: Date

    init(snapshot: HealthSampleSnapshot, importedAt: Date) {
        id = Self.recordID(for: snapshot.id)
        sampleIdentifier = snapshot.id.uuidString
        metric = snapshot.metric.rawValue
        startAt = snapshot.startAt
        endAt = snapshot.endAt
        value = snapshot.value
        unit = snapshot.unit
        categoryValue = snapshot.categoryValue
        workoutActivityType = snapshot.workoutActivityType.map { Int($0) }
        sourceName = snapshot.sourceName
        sourceBundleIdentifier = snapshot.sourceBundleIdentifier
        timeZoneIdentifier = snapshot.timeZoneIdentifier
        timeZoneOffsetSeconds = snapshot.timeZoneOffsetSeconds
        localDay = snapshot.localDay
        lastImportedAt = importedAt
    }

    static func recordID(for sampleID: UUID) -> String {
        "healthkit:\(sampleID.uuidString.lowercased())"
    }

    func update(from snapshot: HealthSampleSnapshot, importedAt: Date) {
        metric = snapshot.metric.rawValue
        startAt = snapshot.startAt
        endAt = snapshot.endAt
        value = snapshot.value
        unit = snapshot.unit
        categoryValue = snapshot.categoryValue
        workoutActivityType = snapshot.workoutActivityType.map { Int($0) }
        sourceName = snapshot.sourceName
        sourceBundleIdentifier = snapshot.sourceBundleIdentifier
        timeZoneIdentifier = snapshot.timeZoneIdentifier
        timeZoneOffsetSeconds = snapshot.timeZoneOffsetSeconds
        localDay = snapshot.localDay
        lastImportedAt = importedAt
    }
}

@Model
final class WorkoutSourceLink {
    @Attribute(.unique) var id: String
    var whoopRecordID: String
    var healthKitRecordID: String
    var confidence: Double
    var reason: String
    var linkedAt: Date

    init(
        whoopRecordID: String,
        healthKitRecordID: String,
        confidence: Double,
        reason: String,
        linkedAt: Date
    ) {
        id = "workout-link:\(whoopRecordID):\(healthKitRecordID)"
        self.whoopRecordID = whoopRecordID
        self.healthKitRecordID = healthKitRecordID
        self.confidence = confidence
        self.reason = reason
        self.linkedAt = linkedAt
    }
}

struct HealthKitPersistenceResult: Sendable {
    let importedCount: Int
    let deletedCount: Int
    let linkedWorkoutCount: Int
}

@MainActor
final class HealthKitPersistence: @unchecked Sendable {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func apply(
        _ batch: HealthKitChangeBatch,
        importedAt: Date
    ) throws -> HealthKitPersistenceResult {
        let existing = try context.fetch(FetchDescriptor<HealthKitSourceRecord>())
        var recordsByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var deletedCount = 0

        for sampleID in batch.deletedSampleIDs {
            let recordID = HealthKitSourceRecord.recordID(for: sampleID)
            if let record = recordsByID.removeValue(forKey: recordID) {
                context.delete(record)
                deletedCount += 1
            }
        }

        for snapshot in batch.samples {
            let recordID = HealthKitSourceRecord.recordID(for: snapshot.id)
            if let record = recordsByID[recordID] {
                record.update(from: snapshot, importedAt: importedAt)
            } else {
                let record = HealthKitSourceRecord(snapshot: snapshot, importedAt: importedAt)
                context.insert(record)
                recordsByID[recordID] = record
            }
        }

        try context.save()
        let linkedWorkoutCount = try linkLikelyDuplicateWorkouts(at: importedAt)
        return HealthKitPersistenceResult(
            importedCount: batch.samples.count,
            deletedCount: deletedCount,
            linkedWorkoutCount: linkedWorkoutCount
        )
    }

    func history(limit: Int = 30) throws -> HealthKitHistorySnapshot {
        let records = try context.fetch(FetchDescriptor<HealthKitSourceRecord>())
        let links = try context.fetch(FetchDescriptor<WorkoutSourceLink>())
        let grouped = Dictionary(grouping: records, by: \.localDay)
        let days = grouped.keys.sorted(by: >).prefix(limit).map { day in
            let dailyRecords = grouped[day, default: []]
            return HealthKitDailySummary(
                id: day,
                day: day,
                restingHeartRate: Self.average(dailyRecords, metric: .restingHeartRate),
                hrvSDNNMilliseconds: Self.average(dailyRecords, metric: .hrvSDNN),
                respiratoryRate: Self.average(dailyRecords, metric: .respiratoryRate),
                oxygenSaturationPercent: Self.average(dailyRecords, metric: .oxygenSaturation),
                sleepMinutes: Self.sum(dailyRecords, metric: .sleepAnalysis).map {
                    Int($0.rounded())
                },
                activeEnergyKilocalories: Self.sum(dailyRecords, metric: .activeEnergy),
                exerciseMinutes: Self.sum(dailyRecords, metric: .exerciseTime),
                workoutCount: dailyRecords.filter { $0.metric == HealthMetric.workout.rawValue }
                    .count,
                sources: Array(Set(dailyRecords.map(\.sourceName))).sorted()
            )
        }

        return HealthKitHistorySnapshot(
            days: days,
            lastSyncAt: records.map(\.lastImportedAt).max(),
            recordCount: records.count,
            linkedWorkoutCount: links.count
        )
    }

    private func linkLikelyDuplicateWorkouts(at linkedAt: Date) throws -> Int {
        let healthKitWorkouts = try context.fetch(FetchDescriptor<HealthKitSourceRecord>())
            .filter { $0.metric == HealthMetric.workout.rawValue }
        let whoopWorkouts = try context.fetch(FetchDescriptor<WhoopSourceRecord>())
            .filter { $0.resourceType == WhoopResourceType.workout.rawValue }
        let existingLinks = try context.fetch(FetchDescriptor<WorkoutSourceLink>())
        var linkIDs = Set(existingLinks.map(\.id))

        for healthKitWorkout in healthKitWorkouts {
            guard
                let match = whoopWorkouts.compactMap({ whoop -> (WhoopSourceRecord, Double)? in
                    guard let whoopStart = whoop.startAt, let whoopEnd = whoop.endAt else {
                        return nil
                    }
                    let startDifference = abs(
                        whoopStart.timeIntervalSince(healthKitWorkout.startAt))
                    let durationDifference = abs(
                        whoopEnd.timeIntervalSince(whoopStart)
                            - healthKitWorkout.endAt.timeIntervalSince(healthKitWorkout.startAt)
                    )
                    guard startDifference <= 20 * 60, durationDifference <= 30 * 60 else {
                        return nil
                    }
                    return (whoop, startDifference + durationDifference)
                }).min(by: { $0.1 < $1.1 })
            else { continue }

            let id = "workout-link:\(match.0.id):\(healthKitWorkout.id)"
            guard linkIDs.insert(id).inserted else { continue }
            let confidence = max(0.5, 1 - match.1 / (50 * 60))
            context.insert(
                WorkoutSourceLink(
                    whoopRecordID: match.0.id,
                    healthKitRecordID: healthKitWorkout.id,
                    confidence: confidence,
                    reason: "Start times and durations are within the duplicate-workout window.",
                    linkedAt: linkedAt
                )
            )
        }

        try context.save()
        return linkIDs.count
    }

    private static func average(
        _ records: [HealthKitSourceRecord],
        metric: HealthMetric
    ) -> Double? {
        let values = records.filter { $0.metric == metric.rawValue }.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func sum(
        _ records: [HealthKitSourceRecord],
        metric: HealthMetric
    ) -> Double? {
        let values = records.filter { $0.metric == metric.rawValue }.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}
