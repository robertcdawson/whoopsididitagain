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

final class HealthKitPersistence: @unchecked Sendable {
    private struct DailyAccumulator {
        var restingHeartRateTotal = 0.0
        var restingHeartRateCount = 0
        var hrvTotal = 0.0
        var hrvCount = 0
        var respiratoryRateTotal = 0.0
        var respiratoryRateCount = 0
        var oxygenSaturationTotal = 0.0
        var oxygenSaturationCount = 0
        var sleepMinutes = 0.0
        var hasSleep = false
        var activeEnergy = 0.0
        var hasActiveEnergy = false
        var exerciseMinutes = 0.0
        var hasExerciseMinutes = false
        var workoutCount = 0
        var sources: Set<String> = []

        mutating func add(_ record: HealthKitSourceRecord) {
            sources.insert(record.sourceName)
            guard let metric = HealthMetric(rawValue: record.metric) else { return }
            switch metric {
            case .restingHeartRate:
                Self.addAverage(
                    record.value,
                    total: &restingHeartRateTotal,
                    count: &restingHeartRateCount
                )
            case .hrvSDNN:
                Self.addAverage(record.value, total: &hrvTotal, count: &hrvCount)
            case .respiratoryRate:
                Self.addAverage(
                    record.value,
                    total: &respiratoryRateTotal,
                    count: &respiratoryRateCount
                )
            case .oxygenSaturation:
                Self.addAverage(
                    record.value,
                    total: &oxygenSaturationTotal,
                    count: &oxygenSaturationCount
                )
            case .sleepAnalysis:
                Self.addSum(record.value, total: &sleepMinutes, hasValue: &hasSleep)
            case .activeEnergy:
                Self.addSum(record.value, total: &activeEnergy, hasValue: &hasActiveEnergy)
            case .exerciseTime:
                Self.addSum(
                    record.value,
                    total: &exerciseMinutes,
                    hasValue: &hasExerciseMinutes
                )
            case .workout:
                workoutCount += 1
            case .heartRate, .walkingRunningDistance, .cyclingDistance, .vo2Max, .bodyMass,
                .sleepingWristTemperature:
                break
            }
        }

        func summary(day: String) -> HealthKitDailySummary {
            HealthKitDailySummary(
                id: day,
                day: day,
                restingHeartRate: average(restingHeartRateTotal, restingHeartRateCount),
                hrvSDNNMilliseconds: average(hrvTotal, hrvCount),
                respiratoryRate: average(respiratoryRateTotal, respiratoryRateCount),
                oxygenSaturationPercent: average(
                    oxygenSaturationTotal,
                    oxygenSaturationCount
                ),
                sleepMinutes: hasSleep ? Int(sleepMinutes.rounded()) : nil,
                activeEnergyKilocalories: hasActiveEnergy ? activeEnergy : nil,
                exerciseMinutes: hasExerciseMinutes ? exerciseMinutes : nil,
                workoutCount: workoutCount,
                sources: sources.sorted()
            )
        }

        private func average(_ total: Double, _ count: Int) -> Double? {
            count == 0 ? nil : total / Double(count)
        }

        private static func addAverage(
            _ value: Double?,
            total: inout Double,
            count: inout Int
        ) {
            guard let value else { return }
            total += value
            count += 1
        }

        private static func addSum(
            _ value: Double?,
            total: inout Double,
            hasValue: inout Bool
        ) {
            guard let value else { return }
            total += value
            hasValue = true
        }
    }

    private static let historyPageSize = 500
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func apply(
        _ batch: HealthKitChangeBatch,
        importedAt: Date,
        linkWorkouts: Bool = true
    ) throws -> HealthKitPersistenceResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var deletedCount = 0
        let requestedRecordIDs = Array(
            Set(
                batch.samples.map { HealthKitSourceRecord.recordID(for: $0.id) }
                    + batch.deletedSampleIDs.map(HealthKitSourceRecord.recordID(for:))
            )
        )
        let existingRecords = try context.fetch(
            FetchDescriptor<HealthKitSourceRecord>(
                predicate: #Predicate { requestedRecordIDs.contains($0.id) }
            )
        )
        var recordsByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })

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
                context.insert(HealthKitSourceRecord(snapshot: snapshot, importedAt: importedAt))
            }
        }

        try context.save()
        let linkedWorkoutCount =
            linkWorkouts
            ? try linkLikelyDuplicateWorkouts(at: importedAt, in: context)
            : try context.fetchCount(FetchDescriptor<WorkoutSourceLink>())
        return HealthKitPersistenceResult(
            importedCount: batch.samples.count,
            deletedCount: deletedCount,
            linkedWorkoutCount: linkedWorkoutCount
        )
    }

    func history(
        limit: Int = 180,
        metrics: [HealthMetric] = HealthMetric.summaryMetrics
    ) throws -> HealthKitHistorySnapshot {
        let metadataContext = ModelContext(container)
        let cutoff =
            Calendar.autoupdatingCurrent.date(byAdding: .day, value: -limit, to: .now)
            ?? .distantFuture

        var grouped: [String: DailyAccumulator] = [:]
        let metricNames = Array(Set(metrics)).map(\.rawValue)
        var lastRecordID = ""
        while true {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<HealthKitSourceRecord>(
                predicate: #Predicate {
                    $0.startAt >= cutoff && metricNames.contains($0.metric)
                        && $0.id > lastRecordID
                },
                sortBy: [SortDescriptor(\.id)]
            )
            descriptor.fetchLimit = Self.historyPageSize
            let records = try context.fetch(descriptor)
            for record in records {
                grouped[record.localDay, default: DailyAccumulator()].add(record)
            }
            guard records.count == Self.historyPageSize, let finalID = records.last?.id else {
                break
            }
            lastRecordID = finalID
        }
        let days = grouped.keys.sorted(by: >).prefix(limit).map {
            grouped[$0, default: DailyAccumulator()].summary(day: $0)
        }

        var lastSyncDescriptor = FetchDescriptor<HealthKitSourceRecord>(
            sortBy: [SortDescriptor(\.lastImportedAt, order: .reverse)]
        )
        lastSyncDescriptor.fetchLimit = 1

        return HealthKitHistorySnapshot(
            days: days,
            lastSyncAt: try metadataContext.fetch(lastSyncDescriptor).first?.lastImportedAt,
            recordCount: try metadataContext.fetchCount(FetchDescriptor<HealthKitSourceRecord>()),
            linkedWorkoutCount: try metadataContext.fetchCount(FetchDescriptor<WorkoutSourceLink>())
        )
    }

    private func linkLikelyDuplicateWorkouts(
        at linkedAt: Date,
        in context: ModelContext
    ) throws -> Int {
        let workoutMetric = HealthMetric.workout.rawValue
        let whoopWorkoutType = WhoopResourceType.workout.rawValue
        let healthKitWorkouts = try context.fetch(
            FetchDescriptor<HealthKitSourceRecord>(
                predicate: #Predicate { $0.metric == workoutMetric }
            )
        )
        let whoopWorkouts = try context.fetch(
            FetchDescriptor<WhoopSourceRecord>(
                predicate: #Predicate { $0.resourceType == whoopWorkoutType }
            )
        )
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
}
