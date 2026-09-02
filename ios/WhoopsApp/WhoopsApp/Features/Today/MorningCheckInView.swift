import SwiftUI

struct MorningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("30 seconds, tops").font(.journal(.footnote)).italic()
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                    JournalSection(title: "") {
                        scoreChipRow(
                            "Pain at rest",
                            value: $checkIn.painAtRest,
                            range: 0...10,
                            selectedFill: Color.journalRedPen,
                            idPrefix: "checkin-pain-at-rest-chip"
                        )
                        scoreChipRow(
                            "Pain with movement",
                            value: $checkIn.painWithMovement,
                            range: 0...10,
                            selectedFill: Color.journalRedPen,
                            idPrefix: "checkin-pain-with-movement-chip"
                        )
                        Text("feels like… (tap all that apply)").font(.journal(.subheadline))
                        JournalChipLayout {
                            symptomChip("stiff", value: $checkIn.stiffness)
                            symptomChip("swollen", value: $checkIn.swelling)
                            symptomChip("weak", value: $checkIn.perceivedWeakness)
                            symptomChip("sick-ish", value: $checkIn.illnessSymptoms)
                        }
                    }

                    JournalSection(title: "How do you feel?") {
                        scoreChipRow(
                            "Energy",
                            value: $checkIn.energy,
                            range: 1...5,
                            idPrefix: "checkin-energy-chip"
                        )
                        scoreChipRow(
                            "Motivation",
                            value: $checkIn.motivation,
                            range: 1...5,
                            idPrefix: "checkin-motivation-chip"
                        )
                    }

                    JournalSection(title: "anything else?") {
                        TextField("Notes", text: $checkIn.notes, axis: .vertical)
                            .formKeyboardField(dismissOnSubmit: false)
                            .accessibilityIdentifier("check-in-notes")
                            .lineLimit(2...5)
                    }

                    if isExisting {
                        Group {
                            Button("Delete this check-in", role: .destructive) {
                                focusedField = nil
                                isConfirmingDeletion = true
                            }
                        }
                    }
                }
                .padding(22)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(
                    dynamicTypeSize.isAccessibilitySize ? "Save" : "done — go make coffee"
                ) { save() }
                .buttonStyle(JournalPrimaryButtonStyle())
                .disabled(isSaving)
                .accessibilityLabel("Save check-in")
                .accessibilityIdentifier("check-in-save")
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color.journalPaper)
            }
            .navigationTitle("Morning Check-In")
            .journalForm()
            .formKeyboardScope($focusedField)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        dismiss()
                    }
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
        .presentationCornerRadius(22)
        .presentationDragIndicator(.visible)
    }

    private func scoreChipRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        selectedFill: Color = .journalInk,
        idPrefix: String
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: "\(value.wrappedValue)")
            JournalScaleChipRow(
                range: range,
                selected: value.wrappedValue,
                selectedFill: selectedFill,
                accessibilityID: { "\(idPrefix)-\($0)" }
            ) { newValue in
                value.wrappedValue = newValue
            }
        }
    }

    private func symptomChip(_ title: String, value: Binding<Bool>) -> some View {
        JournalChip(label: title, isSelected: value.wrappedValue) { value.wrappedValue.toggle() }
            .accessibilityValue(value.wrappedValue ? "Selected" : "Not selected")
    }

    private func save() {
        guard !isSaving else { return }
        focusedField = nil
        isSaving = true
        Task {
            checkIn.timestamp = .now
            if await onSave(checkIn) { dismiss() }
            isSaving = false
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
            JournalForm {
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
