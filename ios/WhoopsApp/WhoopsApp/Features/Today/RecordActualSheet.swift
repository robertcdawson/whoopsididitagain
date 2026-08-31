import SwiftUI

/// The record-actual sheet (`RecordActual.html`): a giant "as prescribed" button by
/// default, with steppers and a tap-only pain scale for logging a deviation instead.
/// Reached from a docket row's "log details" button (T3) — never from the row tap
/// itself, which always logs as prescribed. Owns no repository; saving goes through
/// the `onSave` closure the caller supplies.
struct RecordActualSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNoteFocused: Bool

    let item: DocketItem
    let day: String
    let existingCompletionID: String?
    let onSave: (DocketCompletion) async -> Bool

    @State private var draft: RecordActualDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        item: DocketItem,
        day: String,
        existingCompletionID: String? = nil,
        onSave: @escaping (DocketCompletion) async -> Bool
    ) {
        self.item = item
        self.day = day
        self.existingCompletionID = existingCompletionID
        self.onSave = onSave
        _draft = State(initialValue: RecordActualDraft(item: item))
    }

    var body: some View {
        ZStack(alignment: .top) {
            JournalPaperBackground(showsMarginRule: false)

            VStack(spacing: 14) {
                Capsule()
                    .fill(Color.journalInk.opacity(0.3))
                    .frame(width: 44, height: 5)
                    .padding(.top, 10)

                titleRow

                asPrescribedButton

                Text("one tap. that's the whole log.")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Color.journalInk.opacity(0.55))

                SquiggleDivider()
                    .stroke(Color.journalInk.opacity(0.25), lineWidth: 1.5)
                    .frame(height: 10)

                Text("or, if it went sideways:")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.journalInk.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)

                deviationControls

                painSection

                noteField

                Spacer(minLength: 0)

                Text("saved with undo — mis-taps happen to the best thumbs")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Color.journalInk.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                logItButton

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.journalInk)
                .frame(height: 2)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .ignoresSafeArea(edges: .bottom)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(.system(.title2, design: .serif, weight: .bold))
            if let prescriptionSummary {
                Text(prescriptionSummary)
                    .font(.system(.body, design: .serif, weight: .medium))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.journalInk)
    }

    private var prescriptionSummary: String? {
        switch (item.prescribedSets, item.prescribedRepetitions, item.prescribedDurationSeconds) {
        case (let sets?, let repetitions?, _):
            "\(sets)×\(repetitions)"
        case (let sets?, nil, let duration?):
            "\(sets)×\(duration)s"
        case (nil, let repetitions?, _):
            "\(repetitions) reps"
        case (nil, nil, let duration?):
            "\(duration)s"
        case (let sets?, nil, nil):
            "\(sets) sets"
        case (nil, nil, nil):
            nil
        }
    }

    private var asPrescribedButton: some View {
        Button {
            Task { await save(RecordActualDraft(item: item)) }
        } label: {
            HStack(spacing: 12) {
                DrawnCheckmarkView(color: .journalPaper, size: 26)
                Text("as prescribed")
                    .font(.system(.title3, design: .serif, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .foregroundStyle(Color.journalPaper)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.journalInk))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityIdentifier("record-actual-as-prescribed")
    }

    private var deviationControls: some View {
        HStack(spacing: 16) {
            JournalStepper(
                label: "sets",
                value: draft.sets,
                minusAccessibilityID: "record-actual-sets-minus",
                plusAccessibilityID: "record-actual-sets-plus",
                onDecrement: { draft.decrementSets() },
                onIncrement: { draft.incrementSets() }
            )
            if draft.isDurationBased {
                JournalStepper(
                    label: "hold (s)",
                    value: draft.holdSeconds,
                    minusAccessibilityID: "record-actual-reps-minus",
                    plusAccessibilityID: "record-actual-reps-plus",
                    onDecrement: { draft.decrementHoldSeconds() },
                    onIncrement: { draft.incrementHoldSeconds() }
                )
            } else {
                JournalStepper(
                    label: "reps",
                    value: draft.repetitions,
                    minusAccessibilityID: "record-actual-reps-minus",
                    plusAccessibilityID: "record-actual-reps-plus",
                    onDecrement: { draft.decrementRepetitions() },
                    onIncrement: { draft.incrementRepetitions() }
                )
            }
        }
    }

    private var painSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("pain during")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.journalInk)
                Text("(tap it)")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Color.journalInk.opacity(0.5))
            }
            JournalScaleChipRow(
                range: 0...10,
                selected: draft.painDuring,
                selectedFill: .journalRedPen,
                accessibilityID: { "record-actual-pain-\($0)" }
            ) { value in
                draft.selectPain(value)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("note")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Color.journalInk.opacity(0.6))
            TextField(
                "What changed — load, form, anything else",
                text: $draft.note,
                axis: .vertical
            )
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color.journalInk)
            .focused($isNoteFocused)
            .submitLabel(.done)
            .onSubmit { isNoteFocused = false }
            .lineLimit(1...3)
            .accessibilityIdentifier("record-actual-note")
        }
    }

    private var logItButton: some View {
        Button {
            Task { await save(draft) }
        } label: {
            Text("log it")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(15)
                .foregroundStyle(Color.journalPaper)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.journalInk))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityIdentifier("record-actual-log")
    }

    @MainActor
    private func save(_ draft: RecordActualDraft) async {
        isNoteFocused = false
        isSaving = true
        defer { isSaving = false }
        let completion = draft.completion(item: item, day: day, existingID: existingCompletionID)
        if await onSave(completion) {
            dismiss()
        } else {
            errorMessage = "Couldn't save that. Try again."
        }
    }
}

/// A shallow hand-drawn wave, replacing hairlines per DESIGN.md's "squiggle divider".
private struct SquiggleDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let midY = rect.midY
        let amplitude = rect.height / 2
        path.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        let step = width / 4
        while x < width {
            path.addQuadCurve(
                to: CGPoint(x: min(x + step, width), y: midY),
                control: CGPoint(x: x + step / 2, y: midY - amplitude)
            )
            x += step
        }
        return path
    }
}

#Preview {
    RecordActualSheet(
        item: DocketItem(
            id: "preview-item",
            kind: .protocolItem,
            sourceID: "preview-source",
            protocolID: "preview-protocol",
            title: "band extensions",
            tag: "PT",
            isCompleted: false,
            completionID: nil,
            prescribedSets: 3,
            prescribedRepetitions: 15,
            prescribedDurationSeconds: nil,
            recordedActual: nil
        ),
        day: "2026-08-30"
    ) { _ in true }
}
