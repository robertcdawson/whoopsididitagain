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
    var actualSets: Int?
    var actualRepetitions: Int?
    var actualDurationSeconds: Int?
    var painDuring: Int?
    var actualNote: String?
    var isAsPrescribed: Bool?

    init(completion: DocketCompletion) {
        id = completion.id
        day = completion.day
        kind = completion.kind.rawValue
        sourceID = completion.sourceID
        protocolID = completion.protocolID
        completedAt = completion.completedAt
        actualSets = completion.actual?.sets
        actualRepetitions = completion.actual?.repetitions
        actualDurationSeconds = completion.actual?.durationSeconds
        painDuring = completion.actual?.painDuring
        actualNote = completion.actual?.note
        isAsPrescribed = completion.actual?.isAsPrescribed
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
    /// times-per-week counts honest. Overwrites any previously recorded actual too,
    /// so re-logging (e.g. correcting a deviation) is idempotent rather than stacking.
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
            existing.actualSets = completion.actual?.sets
            existing.actualRepetitions = completion.actual?.repetitions
            existing.actualDurationSeconds = completion.actual?.durationSeconds
            existing.painDuring = completion.actual?.painDuring
            existing.actualNote = completion.actual?.note
            existing.isAsPrescribed = completion.actual?.isAsPrescribed
        } else {
            context.insert(DocketCompletionRecord(completion: completion))
        }
        try context.save()
    }

    func deleteCompletion(id: String) async throws {
        try EditorDraftStore.shared.deleteSource(id)
        if let record = try context.fetch(FetchDescriptor<DocketCompletionRecord>())
            .first(where: { $0.id == id })
        {
            context.delete(record)
        }
        try context.save()
    }

    /// `isAsPrescribed` is the sentinel: `saveCompletion` always sets it whenever an
    /// actual is written, so nil there (with the other five columns also nil) means a
    /// legacy phase-2 tap that made no claim about quantities — never backfilled.
    private static func completion(_ record: DocketCompletionRecord) -> DocketCompletion? {
        guard let kind = DocketItemKind(rawValue: record.kind) else { return nil }
        let actual: DocketActual? = record.isAsPrescribed.map { isAsPrescribed in
            DocketActual(
                sets: record.actualSets,
                repetitions: record.actualRepetitions,
                durationSeconds: record.actualDurationSeconds,
                painDuring: record.painDuring,
                note: record.actualNote ?? "",
                isAsPrescribed: isAsPrescribed
            )
        }
        return DocketCompletion(
            id: record.id,
            day: record.day,
            kind: kind,
            sourceID: record.sourceID,
            protocolID: record.protocolID,
            completedAt: record.completedAt,
            actual: actual
        )
    }
}
