import Foundation

enum DocketItemKind: String, Codable, CaseIterable, Sendable {
    case protocolItem = "protocol_item"
    case workout
    case windDown = "wind_down"
}

/// How a docket row is marked done. Protocol and wind-down rows are asserted complete
/// with a single tap — the tap itself is the assertion that the prescription was met.
/// Workouts need session RPE and pain that the docket cannot invent, so their rows
/// launch the record-actual flow (`WorkoutCompletionView`) instead of completing inline.
enum DocketCompletionStyle: Equatable, Sendable {
    case oneTap
    case recordActual
}

/// What was actually done for a completion, as distinct from what was prescribed.
/// A one-tap completion snapshots the prescription itself into this type; a logged
/// deviation carries the edited quantities and/or pain instead. All fields are nil
/// (and `isAsPrescribed` unset) only on a legacy phase-2 completion that made no
/// claim about quantities at all — see `DocketCompletionRecord`.
struct DocketActual: Codable, Equatable, Sendable {
    var sets: Int?
    var repetitions: Int?
    var durationSeconds: Int?
    var painDuring: Int?
    var note: String
    var isAsPrescribed: Bool
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
    let actual: DocketActual?

    init(
        id: String,
        day: String,
        kind: DocketItemKind,
        sourceID: String,
        protocolID: String?,
        completedAt: Date,
        actual: DocketActual? = nil
    ) {
        self.id = id
        self.day = day
        self.kind = kind
        self.sourceID = sourceID
        self.protocolID = protocolID
        self.completedAt = completedAt
        self.actual = actual
    }

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
            completedAt: completedAt,
            actual: nil
        )
    }

    /// A one-tap completion: the tap is the user's assertion that the prescription
    /// was met, so the item's prescribed quantities are snapshotted into `actual` at
    /// completion time — editing the protocol later cannot rewrite what was recorded.
    /// An item with no prescription (e.g. wind-down) snapshots no quantities;
    /// `isAsPrescribed` still reads true because nothing was contradicted, and
    /// `painDuring` stays nil because nothing was tapped.
    static func asPrescribed(
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
            completedAt: completedAt,
            actual: DocketActual(
                sets: item.prescribedSets,
                repetitions: item.prescribedRepetitions,
                durationSeconds: item.prescribedDurationSeconds,
                painDuring: nil,
                note: "",
                isAsPrescribed: true
            )
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
    var prescribedSets: Int?
    var prescribedRepetitions: Int?
    var prescribedDurationSeconds: Int?
    var recordedActual: DocketActual?

    var completionStyle: DocketCompletionStyle {
        kind == .workout ? .recordActual : .oneTap
    }
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
