import SwiftUI

struct WorkoutCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workout: CompletedWorkout
    @State private var isSaving = false
    let plan: WorkoutPlan
    let onSave: (CompletedWorkout) async -> Bool

    init(
        plan: WorkoutPlan,
        onSave: @escaping (CompletedWorkout) async -> Bool
    ) {
        self.plan = plan
        self.onSave = onSave
        let movements = plan.movements.map { movement in
            CompletedMovement(
                id: UUID().uuidString.lowercased(),
                canonicalMovementID: movement.canonicalMovementID,
                plannedPrescriptionID: movement.id,
                displayName: movement.displayName,
                actualRepetitions: movement.repetitions,
                actualDistanceMeters: movement.distanceMeters,
                actualLoadValue: movement.loadValue,
                actualLoadUnit: movement.loadUnit,
                actualDurationSeconds: movement.durationSeconds,
                modification: "",
                painDuring: 0,
                notes: ""
            )
        }
        _workout = State(
            initialValue: CompletedWorkout(
                id: UUID().uuidString.lowercased(),
                plannedWorkoutID: plan.id,
                title: plan.title,
                startedAt: .now.addingTimeInterval(-3_600),
                endedAt: .now,
                sessionRPE: 5,
                postSessionPain: 0,
                notes: "",
                movements: movements
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(plan.title)
                        .font(.headline)
                    Text(
                        "The values below are a copy of the plan. Edit them to record what actually happened."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Planned → actual")
                }

                Section("Session") {
                    DatePicker("Started", selection: $workout.startedAt)
                    DatePicker("Ended", selection: $workout.endedAt)
                    Stepper(
                        "Session RPE: \(workout.sessionRPE)/10", value: $workout.sessionRPE,
                        in: 1...10)
                    Stepper(
                        "Post-session pain: \(workout.postSessionPain)/10",
                        value: $workout.postSessionPain,
                        in: 0...10
                    )
                    TextField("Session notes", text: $workout.notes, axis: .vertical)
                }

                ForEach(workout.movements.indices, id: \.self) { index in
                    Section(workout.movements[index].displayName) {
                        numberField(
                            "Actual repetitions", value: $workout.movements[index].actualRepetitions
                        )
                        numberField(
                            "Actual distance in meters",
                            value: $workout.movements[index].actualDistanceMeters)
                        decimalField(
                            "Actual load", value: $workout.movements[index].actualLoadValue)
                        TextField(
                            "Load unit",
                            text: optionalString($workout.movements[index].actualLoadUnit)
                        )
                        numberField(
                            "Actual duration in seconds",
                            value: $workout.movements[index].actualDurationSeconds)
                        Stepper(
                            "Pain during: \(workout.movements[index].painDuring)/10",
                            value: $workout.movements[index].painDuring,
                            in: 0...10
                        )
                        TextField(
                            "Modification from plan",
                            text: $workout.movements[index].modification,
                            axis: .vertical
                        )
                        TextField("Notes", text: $workout.movements[index].notes, axis: .vertical)
                    }
                }
            }
            .navigationTitle("Record Actual Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            if await onSave(workout) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || workout.endedAt < workout.startedAt)
                }
            }
        }
    }

    @ViewBuilder
    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, text: optionalInteger(value))
            .keyboardType(.numberPad)
    }

    @ViewBuilder
    private func decimalField(_ title: String, value: Binding<Double?>) -> some View {
        TextField(title, text: optionalDouble(value))
            .keyboardType(.decimalPad)
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0).flatMap { $0 >= 0 ? $0 : nil } }
        )
    }

    private func optionalDouble(_ value: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map { $0.formatted() } ?? "" },
            set: { value.wrappedValue = Double($0).flatMap { $0 >= 0 ? $0 : nil } }
        )
    }

    private func optionalString(_ value: Binding<String?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
