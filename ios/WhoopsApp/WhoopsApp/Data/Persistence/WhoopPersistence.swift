import Foundation
import SwiftData

@Model
final class WhoopSourceRecord {
    @Attribute(.unique) var id: String
    var resourceType: String
    var sourceIdentifier: String
    var sourceUpdatedAt: Date?
    var startAt: Date?
    var endAt: Date?
    var rawPayload: Data
    var lastImportedAt: Date

    init(
        id: String,
        resourceType: String,
        sourceIdentifier: String,
        sourceUpdatedAt: Date?,
        startAt: Date?,
        endAt: Date?,
        rawPayload: Data,
        lastImportedAt: Date
    ) {
        self.id = id
        self.resourceType = resourceType
        self.sourceIdentifier = sourceIdentifier
        self.sourceUpdatedAt = sourceUpdatedAt
        self.startAt = startAt
        self.endAt = endAt
        self.rawPayload = rawPayload
        self.lastImportedAt = lastImportedAt
    }
}

final class WhoopPersistence: @unchecked Sendable {
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        self.container = container
    }

    func upsert(_ response: WhoopSyncResponse) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let existing = try context.fetch(FetchDescriptor<WhoopSourceRecord>())
        var recordsById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var importedCount = 0

        for resource in response.resources {
            for value in resource.records {
                guard let payload = value.objectValue,
                    let sourceIdentifier = Self.sourceIdentifier(
                        for: resource.resourceType,
                        payload: payload
                    )
                else { continue }

                let id = "\(resource.resourceType.rawValue):\(sourceIdentifier)"
                let rawPayload = try encoder.encode(value)
                let sourceUpdatedAt = Self.date(payload["updated_at"]?.stringValue)
                let startAt = Self.date(payload["start"]?.stringValue)
                let endAt = Self.date(payload["end"]?.stringValue)

                if let record = recordsById[id] {
                    if record.sourceUpdatedAt == nil || sourceUpdatedAt == nil
                        || record.sourceUpdatedAt! <= sourceUpdatedAt!
                    {
                        record.sourceUpdatedAt = sourceUpdatedAt
                        record.startAt = startAt
                        record.endAt = endAt
                        record.rawPayload = rawPayload
                        record.lastImportedAt = response.completedAt
                    }
                } else {
                    let record = WhoopSourceRecord(
                        id: id,
                        resourceType: resource.resourceType.rawValue,
                        sourceIdentifier: sourceIdentifier,
                        sourceUpdatedAt: sourceUpdatedAt,
                        startAt: startAt,
                        endAt: endAt,
                        rawPayload: rawPayload,
                        lastImportedAt: response.completedAt
                    )
                    context.insert(record)
                    recordsById[id] = record
                }
                importedCount += 1
            }
        }
        try context.save()
        return importedCount
    }

    func history(limit: Int = 180) throws -> WhoopHistorySnapshot {
        let context = ModelContext(container)
        let recoveryType = WhoopResourceType.recovery.rawValue
        var recoveryDescriptor = FetchDescriptor<WhoopSourceRecord>(
            predicate: #Predicate { $0.resourceType == recoveryType },
            sortBy: [SortDescriptor(\.sourceUpdatedAt, order: .reverse)]
        )
        recoveryDescriptor.fetchLimit = limit
        let sleepType = WhoopResourceType.sleep.rawValue
        var sleepDescriptor = FetchDescriptor<WhoopSourceRecord>(
            predicate: #Predicate { $0.resourceType == sleepType },
            sortBy: [SortDescriptor(\.startAt, order: .reverse)]
        )
        sleepDescriptor.fetchLimit = limit
        var lastSyncDescriptor = FetchDescriptor<WhoopSourceRecord>(
            sortBy: [SortDescriptor(\.lastImportedAt, order: .reverse)]
        )
        lastSyncDescriptor.fetchLimit = 1
        let recoveries =
            try context.fetch(recoveryDescriptor)
            .compactMap(Self.recoveryItem)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
        let sleeps =
            try context.fetch(sleepDescriptor)
            .compactMap(Self.sleepItem)
            .sorted { $0.start > $1.start }
            .prefix(limit)

        return WhoopHistorySnapshot(
            recoveries: Array(recoveries),
            sleeps: Array(sleeps),
            lastSyncAt: try context.fetch(lastSyncDescriptor).first?.lastImportedAt
        )
    }

    func deleteAllWhoopRecords() throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try context.delete(model: WhoopSourceRecord.self)
        try context.save()
    }

    private static func sourceIdentifier(
        for resourceType: WhoopResourceType,
        payload: [String: JSONValue]
    ) -> String? {
        let key = resourceType == .recovery ? "cycle_id" : "id"
        if let value = payload[key]?.stringValue { return value }
        if let value = payload[key]?.numberValue { return String(Int64(value)) }
        return nil
    }

    private static func recoveryItem(_ record: WhoopSourceRecord) -> RecoveryHistoryItem? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: record.rawPayload),
            let payload = value.objectValue
        else { return nil }
        let score = payload["score"]?.objectValue
        let timestamp = date(payload["updated_at"]?.stringValue) ?? record.sourceUpdatedAt
        guard let timestamp else { return nil }
        return RecoveryHistoryItem(
            id: record.id,
            timestamp: timestamp,
            recoveryScore: score?["recovery_score"]?.numberValue.map(Int.init),
            restingHeartRate: score?["resting_heart_rate"]?.numberValue.map(Int.init),
            hrvRMSSD: score?["hrv_rmssd_milli"]?.numberValue
        )
    }

    private static func sleepItem(_ record: WhoopSourceRecord) -> SleepHistoryItem? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: record.rawPayload),
            let payload = value.objectValue,
            let start = date(payload["start"]?.stringValue)
        else { return nil }
        let score = payload["score"]?.objectValue
        let stage = score?["stage_summary"]?.objectValue
        let inBed = stage?["total_in_bed_time_milli"]?.numberValue
        let awake = stage?["total_awake_time_milli"]?.numberValue
        let noData = stage?["total_no_data_time_milli"]?.numberValue
        let light = stage?["total_light_sleep_time_milli"]?.numberValue
        let slowWave = stage?["total_slow_wave_sleep_time_milli"]?.numberValue
        let rem = stage?["total_rem_sleep_time_milli"]?.numberValue
        let sleepMilliseconds: Double?
        if let light, let slowWave, let rem {
            sleepMilliseconds = light + slowWave + rem
        } else {
            sleepMilliseconds = inBed.map { max(0, $0 - (awake ?? 0) - (noData ?? 0)) }
        }
        let sleepMinutes = sleepMilliseconds.map { Int(($0 / 60_000).rounded()) }
        return SleepHistoryItem(
            id: record.id,
            start: start,
            end: date(payload["end"]?.stringValue),
            isNap: payload["nap"]?.boolValue ?? false,
            sleepPerformance: score?["sleep_performance_percentage"]?.numberValue,
            sleepMinutes: sleepMinutes
        )
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return fractional.date(from: value) ?? wholeSeconds.date(from: value)
    }
}
