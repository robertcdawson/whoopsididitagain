import Foundation
import SwiftData

@Model
final class DocketCompletionRecord {
    @Attribute(.unique) var id: String
    var day: String
    var kind: String
    var sourceID: String
    var protocolID: String?
    var completedAt: Date

    init(completion: DocketCompletion) {
        id = completion.id
        day = completion.day
        kind = completion.kind.rawValue
        sourceID = completion.sourceID
        protocolID = completion.protocolID
        completedAt = completion.completedAt
    }
}

@MainActor
final class DocketPersistence: DocketRepository, @unchecked Sendable {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func completions(days: [String]) async throws -> [DocketCompletion] {
        let wanted = Set(days)
        return try context.fetch(FetchDescriptor<DocketCompletionRecord>())
            .filter { wanted.contains($0.day) }
            .compactMap(Self.completion)
            .sorted { $0.completedAt < $1.completedAt }
    }

    /// Upserts by the natural key (day, kind, sourceID): a double tap or a stale
    /// docket refresh never records the same item twice on one day, which keeps
    /// times-per-week counts honest.
    func saveCompletion(_ completion: DocketCompletion) async throws {
        guard !completion.day.isEmpty else { throw DocketValidationError.invalidDay }
        guard !completion.sourceID.isEmpty else { throw DocketValidationError.missingSource }
        let records = try context.fetch(FetchDescriptor<DocketCompletionRecord>())
        if let existing = records.first(where: {
            $0.day == completion.day
                && $0.kind == completion.kind.rawValue
                && $0.sourceID == completion.sourceID
        }) {
            existing.protocolID = completion.protocolID
            existing.completedAt = completion.completedAt
        } else {
            context.insert(DocketCompletionRecord(completion: completion))
        }
        try context.save()
    }

    func deleteCompletion(id: String) async throws {
        if let record = try context.fetch(FetchDescriptor<DocketCompletionRecord>())
            .first(where: { $0.id == id })
        {
            context.delete(record)
        }
        try context.save()
    }

    private static func completion(_ record: DocketCompletionRecord) -> DocketCompletion? {
        guard let kind = DocketItemKind(rawValue: record.kind) else { return nil }
        return DocketCompletion(
            id: record.id,
            day: record.day,
            kind: kind,
            sourceID: record.sourceID,
            protocolID: record.protocolID,
            completedAt: record.completedAt
        )
    }
}
