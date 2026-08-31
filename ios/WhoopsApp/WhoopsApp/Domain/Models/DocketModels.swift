import Foundation

enum DocketItemKind: String, Codable, CaseIterable, Sendable {
    case protocolItem = "protocol_item"
    case workout
    case windDown = "wind_down"
}

/// One recorded completion of a docket item on a local day. The docket itself is
/// recomputed deterministically; only completions are stored, so editing or
/// deleting a protocol never leaves stale docket rows behind.
struct DocketCompletion: Equatable, Identifiable, Sendable {
    let id: String
    let day: String
    let kind: DocketItemKind
    let sourceID: String
    let protocolID: String?
    let completedAt: Date

    static func completed(
        item: DocketItem,
        day: String,
        at completedAt: Date = .now
    ) -> DocketCompletion {
        DocketCompletion(
            id: UUID().uuidString.lowercased(),
            day: day,
            kind: item.kind,
            sourceID: item.sourceID,
            protocolID: item.protocolID,
            completedAt: completedAt
        )
    }
}

/// One row of the generated daily checklist.
struct DocketItem: Equatable, Identifiable, Sendable {
    let id: String
    let kind: DocketItemKind
    let sourceID: String
    let protocolID: String?
    let title: String
    let tag: String?
    var isCompleted: Bool
    var completionID: String?

    /// Workout rows reflect the Train tab's record-actual flow; completing one from
    /// the docket would have to invent session RPE and pain values, so their taps
    /// wait for the record-actual phase.
    var completesFromDocket: Bool { kind != .workout }
}

struct DailyDocket: Equatable, Sendable {
    let day: String
    let rulesetVersion: String
    var items: [DocketItem]
}

enum DocketValidationError: Error, Equatable, LocalizedError, Sendable {
    case invalidDay
    case missingSource

    var errorDescription: String? {
        switch self {
        case .invalidDay: "A docket completion needs its local day."
        case .missingSource: "A docket completion needs the item it completes."
        }
    }
}
