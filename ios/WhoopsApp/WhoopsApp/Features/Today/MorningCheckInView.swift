import SwiftUI

struct MorningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checkIn: MorningCheckIn
    @State private var isSaving = false
    let onSave: (MorningCheckIn) async -> Bool

    init(
        checkIn: MorningCheckIn,
        onSave: @escaping (MorningCheckIn) async -> Bool
    ) {
        _checkIn = State(initialValue: checkIn)
        self.onSave = onSave
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
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Morning Check-In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
    @State private var recommendation: ReadinessAssessment.Recommendation
    @State private var note: String
    @State private var isSaving = false
    let onSave: (ReadinessAssessment.Recommendation, String) async -> Bool

    init(
        assessment: ReadinessAssessment,
        onSave: @escaping (ReadinessAssessment.Recommendation, String) async -> Bool
    ) {
        _recommendation = State(
            initialValue: assessment.userOverride ?? assessment.recommendation
        )
        _note = State(initialValue: assessment.overrideNote ?? "")
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
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Override Recommendation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            if await onSave(recommendation, note) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
