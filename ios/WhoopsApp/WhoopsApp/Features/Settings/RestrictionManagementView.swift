import SwiftUI

struct RestrictionManagementView: View {
    let repository: any AssessmentRepository

    @State private var profiles: [RestrictionProfile] = []
    @State private var editingProfile: RestrictionProfile?
    @State private var profilePendingDeletion: RestrictionProfile?
    @State private var errorMessage: String?

    var body: some View {
        JournalList {
            Section {
                ForEach(profiles) { profile in
                    Button {
                        editingProfile = profile
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.injuryName)
                                    .foregroundStyle(.primary)
                                Text(profile.movementTag)
                                    .font(.journal(.caption))
                                    .foregroundStyle(Color.journalInk.opacity(0.7))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(profile.level.displayName)
                                    .foregroundStyle(
                                        profile.level.isHard
                                            ? Color.journalRedPen : .journalInk.opacity(0.7))
                                Text(profile.isActive ? "Active" : "Inactive")
                                    .font(.journal(.caption))
                                    .foregroundStyle(
                                        profile.isActive
                                            ? Color.journalAmberText : .journalInk.opacity(0.7))
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            profilePendingDeletion = profile
                        }
                    }
                }
            } footer: {
                Text(
                    "An active Avoid restriction forces a Modify recommendation even when systemic recovery is high."
                )
            }
        }
        .navigationTitle("Restrictions")
        .toolbar {
            Button("Add", systemImage: "plus") {
                editingProfile = RestrictionProfile(
                    id: UUID().uuidString.lowercased(),
                    injuryName: "",
                    bodyRegion: "",
                    side: "",
                    movementTag: "",
                    level: .monitor,
                    painThreshold: 3,
                    rationale: "",
                    isActive: true
                )
            }
        }
        .task { await load() }
        .sheet(item: $editingProfile) { profile in
            RestrictionEditorView(profile: profile) { saved in
                await save(saved)
            }
        }
        .alert("Couldn’t update restrictions", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Delete this restriction?",
            isPresented: deletionIsPresented,
            titleVisibility: .visible,
            presenting: profilePendingDeletion
        ) { profile in
            Button("Delete restriction", role: .destructive) {
                Task { await delete(profile) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the restriction and its injury entry. This cannot be undone.")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { if !$0 { profilePendingDeletion = nil } }
        )
    }

    @MainActor
    private func load() async {
        do {
            try await repository.prepareDefaults()
            profiles = try await repository.restrictions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save(_ profile: RestrictionProfile) async {
        do {
            try await repository.saveRestriction(profile)
            profiles = try await repository.restrictions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ profile: RestrictionProfile) async {
        do {
            try await repository.deleteRestriction(id: profile.id)
            profilePendingDeletion = nil
            profiles = try await repository.restrictions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RestrictionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?
    @State private var profile: RestrictionProfile
    @State private var showsBodyAreaPicker = false
    let onSave: (RestrictionProfile) async -> Void

    init(
        profile: RestrictionProfile,
        onSave: @escaping (RestrictionProfile) async -> Void
    ) {
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            JournalForm {
                Section("Injury") {
                    TextField("Name", text: $profile.injuryName)
                        .formKeyboardField()
                    TextField("Body region", text: $profile.bodyRegion)
                        .formKeyboardField()
                    TextField("Side", text: $profile.side)
                        .formKeyboardField()
                }
                Section {
                    if profile.affectedAreaIDs.isEmpty {
                        Text("No areas mapped yet")
                            .foregroundStyle(Color.journalInk.opacity(0.65))
                    } else {
                        ForEach(BodyAreaCatalog.definitions(for: profile.affectedAreaIDs)) { area in
                            Label(area.label, systemImage: "mappin.and.ellipse")
                        }
                    }
                    Button {
                        focusedField = nil
                        showsBodyAreaPicker = true
                    } label: {
                        Label(
                            profile.affectedAreaIDs.isEmpty
                                ? "Choose affected areas" : "Edit affected areas",
                            systemImage: "figure.stand"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("restriction-affected-areas")
                } header: {
                    Text("Affected areas")
                } footer: {
                    Text(
                        "You choose these locations directly. The app never guesses anatomy from the name or notes."
                    )
                }
                Section("Restriction") {
                    Toggle("Active", isOn: $profile.isActive)
                    TextField("Movement or demand", text: $profile.movementTag)
                        .formKeyboardField()
                    Picker("Level", selection: $profile.level) {
                        ForEach(RestrictionLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Stepper(
                        "Pain threshold: \(profile.painThreshold)/10",
                        value: $profile.painThreshold,
                        in: 0...10
                    )
                    TextField("Rationale", text: $profile.rationale, axis: .vertical)
                        .formKeyboardField(dismissOnSubmit: false)
                }
            }
            .navigationTitle("Restriction")
            .formKeyboardScope($focusedField)
            .sheet(isPresented: $showsBodyAreaPicker) {
                BodyAreaPicker(initialAreaIDs: profile.affectedAreaIDs) { ids in
                    profile.affectedAreaIDs = ids
                }
            }
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
                            await onSave(profile)
                            dismiss()
                        }
                    }
                    .disabled(
                        profile.injuryName.trimmingCharacters(in: .whitespaces).isEmpty
                            || profile.movementTag.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RestrictionManagementView(repository: PreviewAssessmentRepository())
    }
}
