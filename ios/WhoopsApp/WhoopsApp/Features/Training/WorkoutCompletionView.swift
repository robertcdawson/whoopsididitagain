import SwiftUI

struct WorkoutCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State private var workout: CompletedWorkout
    @State private var durationSeconds: Double?
    @State private var rpeAnswered = false
    @State private var painAnswered = false
    @State private var workConfirmed = false
    @State private var showsMovementDetails = false
    @State private var isSaving = false
    @State private var isShowingSaveError = false
    @State private var availableMovements = MovementDefinition.bundled
    @State private var movementPendingDeletion: String?
    @State private var isRemovingScore = false
    let isEditing: Bool
    private let plannedWork: CompletedWorkout?
    let introduction: String
    let movementLibrary: any MovementLibraryRepository
    let onSave: (CompletedWorkout) async -> Bool

    init(
        plan: WorkoutPlan,
        movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (CompletedWorkout) async -> Bool
    ) {
        isEditing = false
        plannedWork = CompletedWorkout.asPlanned(plan)
        introduction =
            plan.hasReportedRepetitions
            ? "Review the score and actual movement totals before saving. Changing the score does not replace movement totals."
            : "The values below are copied from the plan. Edit them to record what actually happened."
        self.movementLibrary = movementLibrary
        self.onSave = onSave
        var draft = plannedWork ?? CompletedWorkout(plan: plan)
        if plannedWork == nil && !plan.hasReportedRepetitions {
            for index in draft.movements.indices {
                draft.movements[index].actualRepetitions = nil
                draft.movements[index].actualDistanceMeters = nil
                draft.movements[index].actualCalories = nil
                draft.movements[index].actualDurationSeconds = nil
            }
        }
        draft.startedAt = draft.endedAt
        _workout = State(initialValue: draft)
        _durationSeconds = State(initialValue: nil)
    }

    init(
        workout: CompletedWorkout,
        movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (CompletedWorkout) async -> Bool
    ) {
        isEditing = true
        plannedWork = nil
        introduction =
            "Edit what actually happened. Saving updates this workout, not its original plan or another copy."
        self.movementLibrary = movementLibrary
        self.onSave = onSave
        _workout = State(initialValue: workout)
        _durationSeconds = State(initialValue: workout.durationSeconds)
        _rpeAnswered = State(initialValue: true)
        _painAnswered = State(initialValue: true)
        _workConfirmed = State(initialValue: true)
        _showsMovementDetails = State(initialValue: true)
    }

    var body: some View {
        NavigationStack {
            JournalForm {
                Section {
                    textField("Workout title", text: $workout.title)
                    Text(introduction)
                        .font(.journal(.caption))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }

                actualWorkSection
                sessionSection

                movementDetails
                if let message = validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(
                            Color.journalAmberText)
                    }
                }
            }
            .recoverableDraft(key: draftKey, value: draftBinding)
            .navigationTitle(isEditing ? "Edit Workout" : "Record Actual Work")
            .navigationBarTitleDisplayMode(.inline)
            .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
            .journalSaveBar {
                Button("Save") {
                    focusedField = nil
                    Task {
                        isSaving = true
                        if await onSave(workout) {
                            try? EditorDraftStore.shared.finish(key: draftKey)
                            dismiss()
                        } else {
                            isShowingSaveError = true
                        }
                        isSaving = false
                    }
                }
                .disabled(isSaving || validationMessage != nil)
                .accessibilityIdentifier("save-actual-workout")

            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }

            }
            .task {
                if let definitions = try? await movementLibrary.movements(includeArchived: true) {
                    availableMovements = definitions
                }
            }
            .alert("Couldn’t save workout", isPresented: $isShowingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your edits are still here. Please try saving again.")
            }
            .confirmationDialog(
                "Remove this movement result?", isPresented: movementDeletionIsPresented,
                titleVisibility: .visible
            ) {
                Button("Remove movement", role: .destructive) {
                    workout.movements.removeAll { $0.id == movementPendingDeletion }
                    movementPendingDeletion = nil
                }
                Button("Keep movement", role: .cancel) { movementPendingDeletion = nil }
            } message: {
                Text(
                    "This removes the movement only from this workout. Changes take effect when you save."
                )
            }
            .confirmationDialog(
                "Remove the reported result?", isPresented: $isRemovingScore,
                titleVisibility: .visible
            ) {
                Button("Remove result", role: .destructive) { workout.reportedResult = nil }
                Button("Keep result", role: .cancel) {}
            } message: {
                Text("Actual movement totals are kept. Changes take effect when you save.")
            }
        }
    }

    private var actualWorkSection: some View {
        Section("Actual work") {
            Text("\(workout.movements.count) movements · review what you performed")
            ForEach(workout.movements) { movement in
                Text(movementSummary(movement))
                    .font(.journal(.caption))
            }
            if !isEditing {
                Button("Performed as planned") {
                    if let plannedWork {
                        workout.movements = plannedWork.movements
                        workConfirmed = true
                        showsMovementDetails = false
                    }
                }
                .disabled(plannedWork == nil)
                .accessibilityIdentifier("workout-as-planned")
                if plannedWork == nil {
                    Text(
                        "Review actual totals below. This plan does not specify a complete quantity to confirm."
                    )
                    .font(.journal(.caption))
                }
            }
            Button("Made changes") {
                workConfirmed = true
                showsMovementDetails = true
            }
            .accessibilityIdentifier("workout-made-changes")
            if workConfirmed { Label("Actual work confirmed", systemImage: "checkmark.circle") }
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            DisclosureGroup("Start and end times") {
                DatePicker(
                    "Started", selection: startBinding,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("workout-started-at")
                DatePicker(
                    "Ended", selection: endBinding,
                    in: workout.startedAt...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("workout-ended-at")
                Button("Use these times") { durationSeconds = workout.durationSeconds }
                    .accessibilityIdentifier("confirm-workout-times")
            }
            WorkoutMinutesField(
                title: "Session duration in minutes", seconds: durationBinding)
            Text(
                "Changing the start preserves duration. Changing the end updates duration. Changing duration moves the end."
            )
            .font(.journal(.caption))
            .foregroundStyle(Color.journalInk.opacity(0.7))
            VStack(alignment: .leading, spacing: 6) {
                Text("Session RPE (1–10)")
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                JournalScaleChipRow(
                    range: 1...10,
                    selected: rpeAnswered ? workout.sessionRPE : nil,
                    accessibilityID: { "session-rpe-chip-\($0)" }
                ) { value in
                    workout.sessionRPE = value
                    rpeAnswered = true
                }
            }
            .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Post-session pain (0–10)")
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                JournalScaleChipRow(
                    range: 0...10,
                    selected: painAnswered ? workout.postSessionPain : nil,
                    selectedFill: .journalRedPen,
                    accessibilityID: { "post-session-pain-chip-\($0)" }
                ) { value in
                    workout.postSessionPain = value
                    painAnswered = true
                }
            }
            .padding(.vertical, 2)
            multilineField("Session notes", text: $workout.notes)
        }
    }

    @ViewBuilder
    private var movementDetails: some View {
        if showsMovementDetails || workout.movements.contains(where: { !$0.hasRecordedQuantity }) {
            Section("Reported result") {
                if workout.reportedResult != nil {
                    WorkoutResultCountField(
                        title: "Completed rounds", value: resultBinding(\.completedRounds))
                    WorkoutResultCountField(
                        title: "Additional reps", value: resultBinding(\.additionalRepetitions))
                    Text(
                        "This score is separate from the actual movement totals below. Editing either does not overwrite the other."
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                    Button("Remove reported result", role: .destructive) {
                        focusedField = nil
                        isRemovingScore = true
                    }
                } else {
                    Button("Add reported result") {
                        workout.reportedResult = WorkoutReportedResult(
                            completedRounds: 0, additionalRepetitions: 0)
                    }
                }
            }

            ForEach(workout.movements) { movement in
                if let index = workout.movements.firstIndex(where: { $0.id == movement.id }) {
                    movementSection(index)
                }
            }
            Section {
                Button("Add actual movement", systemImage: "plus") {
                    focusedField = nil
                    workout.movements.append(
                        CompletedMovement(
                            id: UUID().uuidString.lowercased(), canonicalMovementID: nil,
                            plannedPrescriptionID: nil, displayName: "New movement",
                            actualRepetitions: nil, actualDistanceMeters: nil,
                            actualCalories: nil,
                            actualLoadValue: nil, actualLoadUnit: nil,
                            actualDurationSeconds: nil,
                            modification: "", painDuring: 0, painWasReported: false, notes: ""))
                }
                .accessibilityIdentifier("add-actual-movement")
            }
        }
    }

    private func movementSummary(_ movement: CompletedMovement) -> String {
        var quantities: [String] = []
        if let value = movement.actualRepetitions { quantities.append("\(value) reps") }
        if let value = movement.actualDistanceMeters { quantities.append("\(value) m") }
        if let value = movement.actualCalories { quantities.append("\(value) cal") }
        if let value = movement.actualDurationSeconds {
            quantities.append("\(value.formatted()) sec")
        }
        if let value = movement.actualLoadValue {
            quantities.append("\(value.formatted()) \(movement.actualLoadUnit ?? "")")
        }
        return movement.displayName + " · "
            + (quantities.isEmpty
                ? "Actual quantity not recorded" : quantities.joined(separator: " · "))
    }

    private var draftKey: String {
        (isEditing ? "actual-edit:" : "actual-new:")
            + (isEditing ? workout.id : workout.plannedWorkoutID ?? workout.id)
    }
    private struct Draft: Codable, Equatable {
        var workout: CompletedWorkout
        var duration: Double?
        var rpe: Bool
        var pain: Bool
        var confirmed: Bool
        var details: Bool
    }
    private var draftBinding: Binding<Draft> {
        Binding(
            get: {
                Draft(
                    workout: workout, duration: durationSeconds, rpe: rpeAnswered,
                    pain: painAnswered, confirmed: workConfirmed, details: showsMovementDetails)
            },
            set: {
                workout = $0.workout
                durationSeconds = $0.duration
                rpeAnswered = $0.rpe
                painAnswered = $0.pain
                workConfirmed = $0.confirmed
                showsMovementDetails = $0.details
            })
    }

    private var validationMessage: String? {
        if !workConfirmed { return "Confirm the actual work or choose Made changes." }
        if !rpeAnswered || !painAnswered { return "Select session RPE and post-session pain." }
        return durationSeconds == nil
            ? "Enter the session duration in minutes or confirm the times."
            : workout.validationMessage
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { workout.startedAt },
            set: {
                workout.reschedule(startingAt: $0)
                durationSeconds = workout.durationSeconds
            })
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { workout.endedAt },
            set: {
                workout.endedAt = $0
                durationSeconds = workout.durationSeconds
            })
    }

    private var durationBinding: Binding<Double?> {
        Binding(
            get: { durationSeconds },
            set: { value in
                let wasUnconfirmed = durationSeconds == nil
                durationSeconds = value
                if let value {
                    if !isEditing && wasUnconfirmed {
                        workout.startedAt = Date.now.addingTimeInterval(-value)
                    }
                    workout.setDuration(seconds: value)
                }
            })
    }

    private func resultBinding(_ keyPath: WritableKeyPath<WorkoutReportedResult, Int>) -> Binding<
        Int
    > {
        Binding(
            get: { workout.reportedResult?[keyPath: keyPath] ?? 0 },
            set: { workout.reportedResult?[keyPath: keyPath] = $0 })
    }

    private var movementDeletionIsPresented: Binding<Bool> {
        Binding(
            get: { movementPendingDeletion != nil },
            set: { if !$0 { movementPendingDeletion = nil } })
    }

    private func movementSection(_ index: Int) -> some View {
        Section(workout.movements[index].displayName) {
            textField("Movement name", text: $workout.movements[index].displayName)
            NavigationLink {
                MovementSelectionView(
                    canonicalMovementID: $workout.movements[index].canonicalMovementID,
                    displayName: $workout.movements[index].displayName,
                    definitions: availableMovements, remembersNewMovement: false)
            } label: {
                LabeledContent(
                    "Movement mapping",
                    value: availableMovements.first(where: {
                        $0.id == workout.movements[index].canonicalMovementID
                    })?.canonicalName ?? "Unmapped")
            }
            JournalStepper(
                label: "Actual repetitions",
                value: workout.movements[index].actualRepetitions ?? 0,
                minusAccessibilityID: "actual-reps-minus-\(index)",
                plusAccessibilityID: "actual-reps-plus-\(index)",
                onDecrement: {
                    let current = workout.movements[index].actualRepetitions ?? 0
                    workout.movements[index].actualRepetitions = max(0, current - 1)
                },
                onIncrement: {
                    let current = workout.movements[index].actualRepetitions ?? 0
                    workout.movements[index].actualRepetitions = current + 1
                }
            )
            numberField(
                "Actual distance in meters", value: $workout.movements[index].actualDistanceMeters)
            numberField("Actual calories", value: $workout.movements[index].actualCalories)
            decimalField("Actual load", value: $workout.movements[index].actualLoadValue)
            WorkoutLoadUnitPicker(
                title: "Actual load unit", unit: $workout.movements[index].actualLoadUnit)
            WorkoutMinutesField(
                title: "Actual duration in minutes",
                seconds: $workout.movements[index].actualDurationSeconds)
            VStack(alignment: .leading, spacing: 6) {
                Text("Pain during (0–10)")
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                JournalScaleChipRow(
                    range: 0...10,
                    selected: workout.movements[index].reportedPain,
                    selectedFill: .journalRedPen,
                    accessibilityID: { "movement-pain-chip-\(index)-\($0)" }
                ) { value in
                    workout.movements[index].painDuring = value
                    workout.movements[index].painWasReported = true
                }
            }
            .padding(.vertical, 2)
            Button("Pain not recorded") { workout.movements[index].painWasReported = false }
                .font(.journal(.caption)).frame(minHeight: 44)
            multilineField("Modification from plan", text: $workout.movements[index].modification)
            multilineField("Movement notes", text: $workout.movements[index].notes)
            Menu("Movement actions") {
                Button("Duplicate movement", systemImage: "plus.square.on.square") {
                    focusedField = nil
                    workout.movements.insert(workout.movements[index].duplicated(), at: index + 1)
                }
                Button("Move up", systemImage: "arrow.up") {
                    focusedField = nil
                    workout.movements.swapAt(index, index - 1)
                }.disabled(index == 0)
                Button("Move down", systemImage: "arrow.down") {
                    focusedField = nil
                    workout.movements.swapAt(index, index + 1)
                }.disabled(index == workout.movements.count - 1)
                Button("Remove movement", role: .destructive) {
                    focusedField = nil
                    movementPendingDeletion = workout.movements[index].id
                }
            }
            .accessibilityIdentifier("actual-movement-actions-\(index)")
        }
    }

    @ViewBuilder
    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextField("", text: optionalInteger(value), prompt: Text("Optional"))
                .formKeyboardField()
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(title)
        }
    }

    @ViewBuilder
    private func decimalField(_ title: String, value: Binding<Double?>) -> some View {
        WorkoutDecimalField(title: title, value: value, allowsZero: true)
    }

    @ViewBuilder
    private func textField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextField("", text: text, prompt: Text("Optional"), axis: .vertical)
                .formKeyboardField(singleLineText: text)
                .lineLimit(1...4)
                .accessibilityLabel(title)
                .accessibilityIdentifier(title)
        }
    }

    @ViewBuilder
    private func multilineField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.journal(.subheadline))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            TextField("", text: text, prompt: Text("Optional"), axis: .vertical)
                .formKeyboardField(dismissOnSubmit: false)
                .dictationInput(text)
                .lineLimit(1...4)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 2)
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0).flatMap { $0 >= 0 ? $0 : nil } }
        )
    }

}
