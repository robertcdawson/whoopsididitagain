import SwiftUI

/// The generated daily checklist on Today: due protocol items, today's committed
/// workouts, and the sleep wind-down. Protocol and wind-down rows complete with
/// one tap (haptic, drawn-check animation, transient undo); workout rows mirror
/// the Train tab's record-actual state until the record-actual phase brings
/// logging here.
struct DocketView: View {
    let protocolRepository: any ProtocolRepository
    let workoutRepository: any WorkoutRepository
    let docketRepository: any DocketRepository
    let sleepDeadline: SleepDeadline?

    @State private var docket: DailyDocket?
    @State private var lastCompleted: DocketItem?
    @State private var undoTask: Task<Void, Never>?
    @State private var completionCount = 0
    @State private var errorMessage: String?

    private let engine = DeterministicDocketEngine()

    var body: some View {
        FoundationCard(title: "The Docket") {
            if let docket {
                if docket.items.isEmpty {
                    Text("nothing committed today.")
                        .font(.system(.body, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(docket.items) { item in
                        docketRow(item)
                    }
                    if docket.items.allSatisfy(\.isCompleted) {
                        Text("all done. the slow game thanks you.")
                            .font(.system(.callout, design: .serif))
                            .italic()
                            .foregroundStyle(Color.journalRedPen)
                    } else {
                        Text("That's the whole day. Go live it.")
                            .font(.system(.callout, design: .serif))
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let lastCompleted {
                Button {
                    Task { await undo(lastCompleted) }
                } label: {
                    Label(
                        "done: \(lastCompleted.title) — undo",
                        systemImage: "arrow.uturn.backward"
                    )
                    .font(.system(.footnote, design: .serif))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("docket-undo")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .sensoryFeedback(.success, trigger: completionCount)
        .task(id: sleepDeadline) { await reload() }
        .accessibilityIdentifier("docket-card")
    }

    @ViewBuilder
    private func docketRow(_ item: DocketItem) -> some View {
        if item.completesFromDocket {
            Button {
                Task { await toggle(item) }
            } label: {
                rowContent(item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("docket-item-\(item.id)")
            .accessibilityLabel(
                "\(item.title), \(item.isCompleted ? "completed" : "not completed")"
            )
        } else {
            rowContent(item)
                .accessibilityIdentifier("docket-item-\(item.id)")
        }
    }

    private func rowContent(_ item: DocketItem) -> some View {
        HStack(spacing: 12) {
            DrawnCheckbox(isChecked: item.isCompleted)
            Text(item.title)
                .font(.system(.title3, design: .serif))
                .strikethrough(item.isCompleted, color: Color.journalInk.opacity(0.55))
                .foregroundStyle(
                    item.isCompleted ? Color.journalInk.opacity(0.55) : Color.journalInk
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = item.tag {
                Text(tag)
                    .font(.system(.footnote, design: .serif))
                    .italic()
                    .foregroundStyle(Color.journalRedPen.opacity(0.85))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @MainActor
    private func reload() async {
        do {
            let now = Date.now
            let protocols = try await protocolRepository.protocols(includeArchived: false)
            let plans = try await workoutRepository.plans()
            let completions = try await docketRepository.completions(
                days: engine.weekDays(containing: now)
            )
            docket = engine.docket(
                for: now,
                protocols: protocols,
                plans: plans,
                sleepDeadline: sleepDeadline,
                completions: completions
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggle(_ item: DocketItem) async {
        guard let docket else { return }
        do {
            if item.isCompleted {
                if let completionID = item.completionID {
                    try await docketRepository.deleteCompletion(id: completionID)
                }
                clearUndo()
            } else {
                try await docketRepository.saveCompletion(
                    .completed(item: item, day: docket.day)
                )
                completionCount += 1
                scheduleUndo(for: item)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func undo(_ item: DocketItem) async {
        clearUndo()
        guard let docket else { return }
        do {
            let completions = try await docketRepository.completions(days: [docket.day])
            if let completion = completions.first(where: {
                $0.kind == item.kind && $0.sourceID == item.sourceID
            }) {
                try await docketRepository.deleteCompletion(id: completion.id)
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleUndo(for item: DocketItem) {
        lastCompleted = item
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            lastCompleted = nil
        }
    }

    private func clearUndo() {
        undoTask?.cancel()
        lastCompleted = nil
    }
}

#Preview {
    ScrollView {
        DocketView(
            protocolRepository: PreviewProtocolRepository(),
            workoutRepository: PreviewWorkoutRepository(),
            docketRepository: PreviewDocketRepository(),
            sleepDeadline: SleepDeadlineCalculator.calculate(
                now: .now,
                settings: .standard
            )
        )
        .padding()
    }
}
