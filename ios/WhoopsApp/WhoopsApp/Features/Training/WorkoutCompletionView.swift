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
        _workout = State(initialValue: CompletedWorkout(plan: plan))
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
                    multilineField("Session notes", text: $workout.notes)
                }

                ForEach(workout.movements.indices, id: \.self) { index in
                    Section(workout.movements[index].displayName) {
                        numberField(
                            "Actual repetitions", value: $workout.movements[index].actualRepetitions
                        )
                        numberField(
                            "Actual distance in meters",
                            value: $workout.movements[index].actualDistanceMeters)
                        numberField(
                            "Actual calories", value: $workout.movements[index].actualCalories)
                        decimalField(
                            "Actual load", value: $workout.movements[index].actualLoadValue)
                        textField(
                            "Actual load unit",
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
                        multilineField(
                            "Modification from plan",
                            text: $workout.movements[index].modification
                        )
                        multilineField("Movement notes", text: $workout.movements[index].notes)
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
        LabeledContent(title) {
            TextField("", text: optionalInteger(value), prompt: Text("Optional"))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func decimalField(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField("", text: optionalDouble(value), prompt: Text("Optional"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func textField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("", text: text, prompt: Text("Optional"))
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func multilineField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text("Optional"), axis: .vertical)
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
