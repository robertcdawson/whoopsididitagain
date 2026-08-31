import Foundation

/// Mutable state backing `RecordActualSheet`: seeded from a docket item's prescription,
/// edited through clamped steppers and a tap-only pain scale, and turned back into a
/// `DocketCompletion` on save. This holds UI-editable state rather than policy, so it
/// lives in `Domain/Models` alongside `ProtocolReviewItem` (see ProtocolModels.swift)
/// rather than `Domain/Services`, which holds stateless versioned engines.
struct RecordActualDraft: Equatable {
    static let setsRange = 0...20
    static let repetitionsRange = 0...200
    static let holdSecondsRange = 0...3600
    static let holdStep = 5
    static let painRange = 0...10

    /// True when the item prescribes a hold duration rather than repetitions — the sheet
    /// steps hold-seconds in place of reps for these items.
    let isDurationBased: Bool

    private let prescribedSets: Int?
    private let prescribedRepetitions: Int?
    private let prescribedDurationSeconds: Int?

    var sets: Int
    var repetitions: Int
    var holdSeconds: Int
    private(set) var painDuring: Int?
    var note: String

    /// Seeds every stepper from the item's prescription. A dimension with no prescription
    /// (e.g. an item with no duration) seeds to 0 for display, but `completion(item:day:)`
    /// never reports that dimension unless the user actually steps it away from zero —
    /// it does not invent a value the prescription never made.
    init(item: DocketItem) {
        isDurationBased = item.prescribedRepetitions == nil && item.prescribedDurationSeconds != nil
        prescribedSets = item.prescribedSets
        prescribedRepetitions = item.prescribedRepetitions
        prescribedDurationSeconds = item.prescribedDurationSeconds
        sets = item.prescribedSets ?? 0
        repetitions = item.prescribedRepetitions ?? 0
        holdSeconds = item.prescribedDurationSeconds ?? 0
        painDuring = nil
        note = ""
    }

    /// True only while every value still matches the seeded prescription and nothing has
    /// been asserted beyond it — the moment any control moves, or pain or a note is
    /// recorded, this is a deviation.
    var isAsPrescribed: Bool {
        sets == (prescribedSets ?? 0)
            && repetitions == (prescribedRepetitions ?? 0)
            && holdSeconds == (prescribedDurationSeconds ?? 0)
            && painDuring == nil
            && note.isEmpty
    }

    mutating func incrementSets() {
        sets = min(Self.setsRange.upperBound, sets + 1)
    }

    mutating func decrementSets() {
        sets = max(Self.setsRange.lowerBound, sets - 1)
    }

    mutating func incrementRepetitions() {
        repetitions = min(Self.repetitionsRange.upperBound, repetitions + 1)
    }

    mutating func decrementRepetitions() {
        repetitions = max(Self.repetitionsRange.lowerBound, repetitions - 1)
    }

    mutating func incrementHoldSeconds() {
        holdSeconds = min(Self.holdSecondsRange.upperBound, holdSeconds + Self.holdStep)
    }

    mutating func decrementHoldSeconds() {
        holdSeconds = max(Self.holdSecondsRange.lowerBound, holdSeconds - Self.holdStep)
    }

    /// Pain stays nil until a chip is tapped — never defaults to 0. Tapping the already
    /// selected value clears it back to nil rather than leaving it stuck selected.
    mutating func selectPain(_ value: Int?) {
        guard let value, Self.painRange.contains(value) else {
            painDuring = nil
            return
        }
        painDuring = painDuring == value ? nil : value
    }

    /// Builds the completion to save. Reuses `existingID` when editing a completion
    /// already on the docket (the undo bar's "adjust" path, wired in T3), so correcting
    /// a mis-tap overwrites that row instead of minting a second one.
    func completion(
        item: DocketItem,
        day: String,
        existingID: String? = nil,
        at completedAt: Date = .now
    ) -> DocketCompletion {
        let actual = DocketActual(
            sets: Self.resolvedValue(current: sets, prescribed: prescribedSets),
            repetitions: Self.resolvedValue(
                current: repetitions, prescribed: prescribedRepetitions),
            durationSeconds: Self.resolvedValue(
                current: holdSeconds, prescribed: prescribedDurationSeconds),
            painDuring: painDuring,
            note: note,
            isAsPrescribed: isAsPrescribed
        )
        return DocketCompletion(
            id: existingID ?? UUID().uuidString.lowercased(),
            day: day,
            kind: item.kind,
            sourceID: item.sourceID,
            protocolID: item.protocolID,
            completedAt: completedAt,
            actual: actual
        )
    }

    /// A dimension is reported only if the item actually prescribed it, or the user
    /// stepped it away from the unprescribed zero baseline — never an invented value.
    private static func resolvedValue(current: Int, prescribed: Int?) -> Int? {
        if prescribed != nil { return current }
        return current == 0 ? nil : current
    }
}
