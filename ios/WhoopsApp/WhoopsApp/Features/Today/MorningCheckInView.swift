import SwiftUI

struct MorningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State private var checkIn: MorningCheckIn
    @State private var isSaving = false
    @State private var isConfirmingDeletion = false
    let isExisting: Bool
    let onSave: (MorningCheckIn) async -> Bool
    let onDelete: (String) async -> Bool

    init(
        checkIn: MorningCheckIn,
        isExisting: Bool,
        onSave: @escaping (MorningCheckIn) async -> Bool,
        onDelete: @escaping (String) async -> Bool
    ) {
        _checkIn = State(initialValue: checkIn)
        self.isExisting = isExisting
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Symptoms") {
                    scoreSlider("Pain at rest", value: $checkIn.painAtRest, range: 0...10)
                    scoreSlider(
                        "Pain with movement",
                        value: $checkIn.painWithMovement,
                        range: 0...10
                    )
                    Toggle("Stiffness", isOn: $checkIn.stiffness)
                    Toggle("Swelling", isOn: $checkIn.swelling)
                    Toggle("Perceived weakness", isOn: $checkIn.perceivedWeakness)
                    Toggle("Illness symptoms", isOn: $checkIn.illnessSymptoms)
                }

                Section("How do you feel?") {
                    scoreSlider("Energy", value: $checkIn.energy, range: 1...5)
                    scoreSlider("Motivation", value: $checkIn.motivation, range: 1...5)
                }

                Section("Optional context") {
                    TextField("Notes", text: $checkIn.notes, axis: .vertical)
                        .formKeyboardField(dismissOnSubmit: false)
                        .accessibilityIdentifier("check-in-notes")
                        .lineLimit(2...5)
                }

                if isExisting {
                    Section {
                        Button("Delete this check-in", role: .destructive) {
                            focusedField = nil
                            isConfirmingDeletion = true
                        }
                    } footer: {
                        Text("Deleting removes your symptom answers for this day.")
                    }
                }
            }
            .navigationTitle("Morning Check-In")
            .formKeyboardScope($focusedField)
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
                            checkIn.timestamp = .now
                            if await onSave(checkIn) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Delete this morning check-in?",
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete check-in", role: .destructive) {
                    Task {
                        if await onDelete(checkIn.day) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your answers will be removed. This cannot be undone.")
            }
        }
    }

    private func scoreSlider(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: "\(value.wrappedValue)")
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
    }
}

struct AssessmentOverrideView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State private var recommendation: ReadinessAssessment.Recommendation
    @State private var note: String
    @State private var isSaving = false
    @State private var isConfirmingRemoval = false
    let hasSavedOverride: Bool
    let onSave: (ReadinessAssessment.Recommendation?, String?) async -> Bool

    init(
        assessment: ReadinessAssessment,
        onSave: @escaping (ReadinessAssessment.Recommendation?, String?) async -> Bool
    ) {
        _recommendation = State(
            initialValue: assessment.userOverride ?? assessment.recommendation
        )
        _note = State(initialValue: assessment.overrideNote ?? "")
        hasSavedOverride = assessment.userOverride != nil || assessment.overrideNote != nil
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your decision") {
                    Picker("Recommendation", selection: $recommendation) {
                        ForEach(ReadinessAssessment.Recommendation.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    TextField("Why are you overriding it?", text: $note, axis: .vertical)
                        .formKeyboardField(dismissOnSubmit: false)
                        .lineLimit(2...5)
                }
                if hasSavedOverride {
                    Section {
                        Button("Remove override", role: .destructive) {
                            focusedField = nil
                            isConfirmingRemoval = true
                        }
                    } footer: {
                        Text("The app will use its calculated recommendation again.")
                    }
                }
            }
            .navigationTitle("Override Recommendation")
            .formKeyboardScope($focusedField)
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
                            if await onSave(recommendation, note) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(
                "Remove your override?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove override", role: .destructive) {
                    Task {
                        isSaving = true
                        if await onSave(nil, nil) { dismiss() }
                        isSaving = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your override and note will be deleted.")
            }
        }
    }
}
