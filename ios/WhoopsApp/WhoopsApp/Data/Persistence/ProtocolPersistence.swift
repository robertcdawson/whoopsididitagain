import Foundation
import SwiftData

@Model
final class TherapyProtocolRecord {
    @Attribute(.unique) var id: String
    var title: String
    var source: String
    var rawText: String
    var phaseNumber: Int?
    var phaseCount: Int?
    var unlockMilestone: String?
    var startedAt: Date
    var endsAt: Date?
    var parserVersion: String
    var confidence: Double
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(therapyProtocol: TherapyProtocol, updatedAt: Date) {
        id = therapyProtocol.id
        title = therapyProtocol.title
        source = therapyProtocol.source.rawValue
        rawText = therapyProtocol.rawText
        phaseNumber = therapyProtocol.phaseNumber
        phaseCount = therapyProtocol.phaseCount
        unlockMilestone = therapyProtocol.unlockMilestone
        startedAt = therapyProtocol.startedAt
        endsAt = therapyProtocol.endsAt
        parserVersion = therapyProtocol.parserVersion
        confidence = therapyProtocol.confidence
        isArchived = therapyProtocol.isArchived
        createdAt = therapyProtocol.createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TherapyProtocolItemRecord {
    @Attribute(.unique) var id: String
    var protocolID: String
    var sequence: Int
    var canonicalMovementID: String
    var displayName: String
    var originalText: String
    var sets: Int?
    var repetitions: Int?
    var durationSeconds: Int?
    var loadValue: Double?
    var loadUnit: String?
    var cadenceData: Data
    var notes: String

    init(item: TherapyProtocolItem, protocolID: String, cadenceData: Data) {
        id = item.id
        self.protocolID = protocolID
        sequence = item.order
        canonicalMovementID = item.canonicalMovementID
        displayName = item.displayName
        originalText = item.originalText
        sets = item.sets
        repetitions = item.repetitions
        durationSeconds = item.durationSeconds
        loadValue = item.loadValue
        loadUnit = item.loadUnit
        self.cadenceData = cadenceData
        notes = item.notes
    }
}

@MainActor
final class ProtocolPersistence: ProtocolRepository, @unchecked Sendable {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func protocols(includeArchived: Bool) async throws -> [TherapyProtocol] {
        let protocolRecords = try context.fetch(FetchDescriptor<TherapyProtocolRecord>())
        let itemRecords = try context.fetch(FetchDescriptor<TherapyProtocolItemRecord>())
        return protocolRecords.compactMap { record in
            Self.therapyProtocol(
                record,
                items: itemRecords.filter { $0.protocolID == record.id },
                decoder: decoder
            )
        }
        .filter { includeArchived || !$0.isArchived }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func saveProtocol(_ therapyProtocol: TherapyProtocol) async throws {
        let validated = try therapyProtocol.validated()
        let now = Date.now
        let protocolRecords = try context.fetch(FetchDescriptor<TherapyProtocolRecord>())
        if let record = protocolRecords.first(where: { $0.id == validated.id }) {
            record.title = validated.title
            record.source = validated.source.rawValue
            record.rawText = validated.rawText
            record.phaseNumber = validated.phaseNumber
            record.phaseCount = validated.phaseCount
            record.unlockMilestone = validated.unlockMilestone
            record.startedAt = validated.startedAt
            record.endsAt = validated.endsAt
            record.parserVersion = validated.parserVersion
            record.confidence = validated.confidence
            record.isArchived = validated.isArchived
            record.updatedAt = now
        } else {
            context.insert(TherapyProtocolRecord(therapyProtocol: validated, updatedAt: now))
        }

        let itemRecords = try context.fetch(FetchDescriptor<TherapyProtocolItemRecord>())
        let newItemIDs = Set(validated.items.map(\.id))
        for record in itemRecords
        where record.protocolID == validated.id && !newItemIDs.contains(record.id) {
            context.delete(record)
        }
        for item in validated.items {
            let cadenceData = try encoder.encode(item.cadence)
            if let record = itemRecords.first(where: { $0.id == item.id }) {
                Self.update(record, from: item, protocolID: validated.id, cadenceData: cadenceData)
            } else {
                context.insert(
                    TherapyProtocolItemRecord(
                        item: item,
                        protocolID: validated.id,
                        cadenceData: cadenceData
                    )
                )
            }
        }
        try context.save()
    }

    func deleteProtocol(id: String) async throws {
        for record in try context.fetch(FetchDescriptor<TherapyProtocolItemRecord>())
        where record.protocolID == id {
            context.delete(record)
        }
        if let record = try context.fetch(FetchDescriptor<TherapyProtocolRecord>())
            .first(where: { $0.id == id })
        {
            context.delete(record)
        }
        try context.save()
    }

    private static func therapyProtocol(
        _ record: TherapyProtocolRecord,
        items: [TherapyProtocolItemRecord],
        decoder: JSONDecoder
    ) -> TherapyProtocol? {
        guard let source = ProtocolSource(rawValue: record.source) else { return nil }
        let decodedItems = items.compactMap { item -> TherapyProtocolItem? in
            guard let cadence = try? decoder.decode(ProtocolCadence.self, from: item.cadenceData)
            else { return nil }
            return TherapyProtocolItem(
                id: item.id,
                order: item.sequence,
                canonicalMovementID: item.canonicalMovementID,
                displayName: item.displayName,
                originalText: item.originalText,
                sets: item.sets,
                repetitions: item.repetitions,
                durationSeconds: item.durationSeconds,
                loadValue: item.loadValue,
                loadUnit: item.loadUnit,
                cadence: cadence,
                notes: item.notes
            )
        }.sorted { $0.order < $1.order }
        guard decodedItems.count == items.count else { return nil }
        return TherapyProtocol(
            id: record.id,
            title: record.title,
            source: source,
            rawText: record.rawText,
            phaseNumber: record.phaseNumber,
            phaseCount: record.phaseCount,
            unlockMilestone: record.unlockMilestone,
            startedAt: record.startedAt,
            endsAt: record.endsAt,
            parserVersion: record.parserVersion,
            confidence: record.confidence,
            isArchived: record.isArchived,
            createdAt: record.createdAt,
            items: decodedItems
        )
    }

    private static func update(
        _ record: TherapyProtocolItemRecord,
        from item: TherapyProtocolItem,
        protocolID: String,
        cadenceData: Data
    ) {
        record.protocolID = protocolID
        record.sequence = item.order
        record.canonicalMovementID = item.canonicalMovementID
        record.displayName = item.displayName
        record.originalText = item.originalText
        record.sets = item.sets
        record.repetitions = item.repetitions
        record.durationSeconds = item.durationSeconds
        record.loadValue = item.loadValue
        record.loadUnit = item.loadUnit
        record.cadenceData = cadenceData
        record.notes = item.notes
    }
}
