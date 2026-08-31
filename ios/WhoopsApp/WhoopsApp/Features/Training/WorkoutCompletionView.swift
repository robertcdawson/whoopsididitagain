import SwiftUI

struct WorkoutCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State private var workout: CompletedWorkout
    @State private var durationSeconds: Double?
    @State private var isSaving = false
    @State private var isShowingSaveError = false
    @State private var availableMovements = MovementDefinition.bundled
    @State private var movementPendingDeletion: String?
    @State private var isRemovingScore = false
    let isEditing: Bool
    let introduction: String
    let movementLibrary: any MovementLibraryRepository
    let onSave: (CompletedWorkout) async -> Bool

    init(
        plan: WorkoutPlan,
        movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (CompletedWorkout) async -> Bool
    ) {
        isEditing = false
        introduction =
            plan.hasReportedRepetitions
            ? "Review the score and actual movement totals before saving. Changing the score does not replace movement totals."
            : "The values below are copied from the plan. Edit them to record what actually happened."
        self.movementLibrary = movementLibrary
        self.onSave = onSave
        let draft = CompletedWorkout(plan: plan)
        _workout = State(initialValue: draft)
        _durationSeconds = State(initialValue: draft.durationSeconds)
    }

    init(
        workout: CompletedWorkout,
        movementLibrary: any MovementLibraryRepository,
        onSave: @escaping (CompletedWorkout) async -> Bool
    ) {
        isEditing = true
        introduction =
            "Edit what actually happened. Saving updates this workout, not its original plan or another copy."
        self.movementLibrary = movementLibrary
        self.onSave = onSave
        _workout = State(initialValue: workout)
        _durationSeconds = State(initialValue: workout.durationSeconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    textField("Workout title", text: $workout.title)
                    Text(introduction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Session") {
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
                    WorkoutMinutesField(
                        title: "Session duration in minutes", seconds: durationBinding)
                    Text(
                        "Changing the start preserves duration. Changing the end updates duration. Changing duration moves the end."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Stepper(
                        "Session RPE: \(workout.sessionRPE)/10", value: $workout.sessionRPE,
                        in: 1...10
                    )
                    .accessibilityIdentifier("session-rpe")
                    Stepper(
                        "Post-session pain: \(workout.postSessionPain)/10",
                        value: $workout.postSessionPain,
                        in: 0...10
                    )
                    .accessibilityIdentifier("post-session-pain")
                    multilineField("Session notes", text: $workout.notes)
                }

                Section("Reported result") {
                    if workout.reportedResult != nil {
                        WorkoutResultCountField(
                            title: "Completed rounds", value: resultBinding(\.completedRounds))
                        WorkoutResultCountField(
                            title: "Additional reps", value: resultBinding(\.additionalRepetitions))
                        Text(
                            "This score is separate from the actual movement totals below. Editing either does not overwrite the other."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                                modification: "", painDuring: 0, notes: ""))
                    }
                    .accessibilityIdentifier("add-actual-movement")
                }
                if let message = validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(
                            .orange)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Workout" : "Record Actual Work")
            .navigationBarTitleDisplayMode(.inline)
            .formKeyboardScope($focusedField, doneIdentifier: "dismiss-workout-keyboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focusedField = nil
                        Task {
                            isSaving = true
                            if await onSave(workout) {
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

    private var validationMessage: String? {
        durationSeconds == nil
            ? "Enter the session duration in minutes." : workout.validationMessage
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
                durationSeconds = value
                if let value { workout.setDuration(seconds: value) }
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
            numberField("Actual repetitions", value: $workout.movements[index].actualRepetitions)
            numberField(
                "Actual distance in meters", value: $workout.movements[index].actualDistanceMeters)
            numberField("Actual calories", value: $workout.movements[index].actualCalories)
            decimalField("Actual load", value: $workout.movements[index].actualLoadValue)
            WorkoutLoadUnitPicker(
                title: "Actual load unit", unit: $workout.movements[index].actualLoadUnit)
            WorkoutMinutesField(
                title: "Actual duration in minutes",
                seconds: $workout.movements[index].actualDurationSeconds)
            Stepper(
                "Pain during: \(workout.movements[index].painDuring)/10",
                value: $workout.movements[index].painDuring, in: 0...10)
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
        LabeledContent(title) {
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
        LabeledContent(title) {
            TextField("", text: text, prompt: Text("Optional"))
                .formKeyboardField()
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(title)
        }
    }

    @ViewBuilder
    private func multilineField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text("Optional"), axis: .vertical)
                .formKeyboardField(dismissOnSubmit: false)
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
