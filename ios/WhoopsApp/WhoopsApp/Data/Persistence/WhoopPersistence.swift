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

@MainActor
final class WhoopPersistence: @unchecked Sendable {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func upsert(_ response: WhoopSyncResponse) throws -> Int {
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
        let records = try context.fetch(
            FetchDescriptor<WhoopSourceRecord>(
                sortBy: [SortDescriptor(\.lastImportedAt, order: .reverse)]
            )
        )
        let recoveries =
            records
            .filter { $0.resourceType == WhoopResourceType.recovery.rawValue }
            .compactMap(Self.recoveryItem)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
        let sleeps =
            records
            .filter { $0.resourceType == WhoopResourceType.sleep.rawValue }
            .compactMap(Self.sleepItem)
            .sorted { $0.start > $1.start }
            .prefix(limit)

        return WhoopHistorySnapshot(
            recoveries: Array(recoveries),
            sleeps: Array(sleeps),
            lastSyncAt: records.map(\.lastImportedAt).max()
        )
    }

    func deleteAllWhoopRecords() throws {
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
        let sleepMinutes = inBed.map { Int(max(0, $0 - (awake ?? 0)) / 60_000) }
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
