import SwiftUI

/// The generated daily checklist on Today: due protocol items, today's committed
/// workouts, and the sleep wind-down. Protocol and wind-down rows complete with
/// one tap (haptic, drawn-check animation, transient undo) — the tap itself
/// asserts the prescription was met. A trailing "log details" button on protocol
/// rows opens `RecordActualSheet` for logging a deviation instead, and the undo
/// bar's "adjust" action reopens that same sheet seeded from the completion just
/// written, so a mis-tap becomes a correction rather than undo-and-redo. Workout
/// rows launch `WorkoutCompletionView` — the docket cannot invent session RPE or
/// pain, so it defers to the same recording flow the Train tab uses.
struct DocketView: View {
    @Environment(\.scenePhase) private var scenePhase

    let protocolRepository: any ProtocolRepository
    let workoutRepository: any WorkoutRepository
    let docketRepository: any DocketRepository
    let movementLibrary: any MovementLibraryRepository
    let sleepDeadline: SleepDeadline?

    @State private var docket: DailyDocket?
    @State private var plans: [WorkoutPlan] = []
    @State private var lastCompleted: DocketItem?
    @State private var undoTask: Task<Void, Never>?
    @State private var completionCount = 0
    @State private var errorMessage: String?
    @State private var recordActualTarget: DocketItem?
    @State private var completingWorkoutPlan: WorkoutPlan?

    private let engine = DeterministicDocketEngine()

    var body: some View {
        JournalSection(title: "The Docket") {
            if let docket {
                if docket.items.isEmpty {
                    Text("nothing committed today.")
                        .font(.journal(.body))
                        .italic()
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                } else {
                    ForEach(docket.items) { item in
                        docketRow(item)
                    }
                    if docket.items.allSatisfy(\.isCompleted) {
                        Text("all done. the slow game thanks you.")
                            .font(.journal(.callout))
                            .italic()
                            .foregroundStyle(Color.journalRedPen)
                    } else {
                        Text("That's the whole day. Go live it.")
                            .font(.journal(.callout))
                            .italic()
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let lastCompleted {
                HStack(spacing: 8) {
                    Button {
                        Task { await undo(lastCompleted) }
                    } label: {
                        Label(
                            "done: \(lastCompleted.title) — undo",
                            systemImage: "arrow.uturn.backward"
                        )
                        .font(.journal(.footnote))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("docket-undo")

                    Button("adjust") {
                        recordActualTarget = lastCompleted
                    }
                    .font(.journal(.footnote))
                    .frame(minHeight: 38)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("docket-adjust")
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.journal(.footnote))
                    .foregroundStyle(Color.journalRedPen)
            }
        }
        .sensoryFeedback(.success, trigger: completionCount)
        .task(id: sleepDeadline) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reload() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("docket-card")
        .sheet(item: $recordActualTarget) { item in
            RecordActualSheet(
                item: item,
                day: docket?.day ?? engine.day(containing: .now),
                existingCompletionID: item.completionID
            ) { completion in
                await save(completion)
            }
        }
        .sheet(item: $completingWorkoutPlan) { plan in
            WorkoutCompletionView(plan: plan, movementLibrary: movementLibrary) { workout in
                await saveWorkout(workout)
            }
        }
    }

    @ViewBuilder
    private func docketRow(_ item: DocketItem) -> some View {
        switch item.completionStyle {
        case .oneTap:
            oneTapRow(item)
        case .recordActual:
            workoutRow(item)
        }
    }

    private func oneTapRow(_ item: DocketItem) -> some View {
        HStack(spacing: 8) {
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

            if item.kind == .protocolItem {
                Button {
                    recordActualTarget = item
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.journalInk.opacity(0.65))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("docket-record-actual-\(item.id)")
                .accessibilityLabel("log details for \(item.title)")
            }
        }
    }

    @ViewBuilder
    private func workoutRow(_ item: DocketItem) -> some View {
        if let plan = plans.first(where: { $0.id == item.sourceID }) {
            Button {
                completingWorkoutPlan = plan
            } label: {
                rowContent(item)
            }
            .buttonStyle(.plain)
            .disabled(item.isCompleted)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.journal(.title3))
                    .strikethrough(item.isCompleted, color: Color.journalInk.opacity(0.55))
                    .foregroundStyle(
                        item.isCompleted ? Color.journalInk.opacity(0.55) : Color.journalInk
                    )
                if let aside = deviationAside(for: item) {
                    Text(aside)
                        .font(.journal(.footnote))
                        .italic()
                        .foregroundStyle(Color.journalInk.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = item.tag {
                Text(tag)
                    .font(.journal(.footnote))
                    .italic()
                    .foregroundStyle(Color.journalRedPen.opacity(0.85))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// A short aside like `2×15 · pain 1`, rendered only for a completion that
    /// deviated from what was prescribed. An as-prescribed row (including a
    /// freshly one-tapped one) renders with no aside at all.
    private func deviationAside(for item: DocketItem) -> String? {
        guard let actual = item.recordedActual, actual.isAsPrescribed == false else { return nil }
        var parts: [String] = []
        switch (actual.sets, actual.repetitions, actual.durationSeconds) {
        case (let sets?, let repetitions?, _):
            parts.append("\(sets)×\(repetitions)")
        case (let sets?, nil, let duration?):
            parts.append("\(sets)×\(duration)s")
        case (nil, let repetitions?, _):
            parts.append("\(repetitions) reps")
        case (nil, nil, let duration?):
            parts.append("\(duration)s")
        case (let sets?, nil, nil):
            parts.append("\(sets) sets")
        case (nil, nil, nil):
            break
        }
        if let pain = actual.painDuring {
            parts.append("pain \(pain)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @MainActor
    private func reload() async {
        do {
            let now = Date.now
            let outsideCoordinator = OutsideAppDocketCoordinator(repository: docketRepository)
            let pendingActionIDs = try await outsideCoordinator.reconcilePendingCompletions()
            let protocols = try await protocolRepository.protocols(includeArchived: false)
            let fetchedPlans = try await workoutRepository.plans()
            let completions = try await docketRepository.completions(
                days: engine.weekDays(containing: now)
            )
            plans = fetchedPlans
            let generatedDocket = engine.docket(
                for: now,
                protocols: protocols,
                plans: fetchedPlans,
                sleepDeadline: sleepDeadline,
                completions: completions
            )
            docket = generatedDocket
            try await outsideCoordinator.publish(
                generatedDocket,
                acknowledging: pendingActionIDs
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
                await reload()
            } else {
                try await docketRepository.saveCompletion(
                    .asPrescribed(item: item, day: docket.day)
                )
                completionCount += 1
                await reload()
                if let updated = updatedItem(matching: item) {
                    scheduleUndo(for: updated)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Shared save path for both the "log details" deviation sheet and the undo
    /// bar's "adjust" action: persists, reloads, and (re)schedules the transient
    /// undo bar from the freshly reloaded item so "adjust" always seeds from the
    /// row actually on the docket, not a stale pre-save snapshot.
    @MainActor
    private func save(_ completion: DocketCompletion) async -> Bool {
        do {
            try await docketRepository.saveCompletion(completion)
            completionCount += 1
            await reload()
            if let updated = docket?.items.first(where: {
                $0.kind == completion.kind && $0.sourceID == completion.sourceID
            }) {
                scheduleUndo(for: updated)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func saveWorkout(_ workout: CompletedWorkout) async -> Bool {
        do {
            try await workoutRepository.saveCompletedWorkout(workout)
            await reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    private func updatedItem(matching item: DocketItem) -> DocketItem? {
        docket?.items.first { $0.kind == item.kind && $0.sourceID == item.sourceID }
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
            movementLibrary: PreviewMovementLibraryRepository(),
            sleepDeadline: SleepDeadlineCalculator.calculate(
                now: .now,
                settings: .standard
            )
        )
        .padding()
    }
}
