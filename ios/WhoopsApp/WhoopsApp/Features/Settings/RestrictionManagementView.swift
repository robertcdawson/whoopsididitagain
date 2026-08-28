import SwiftUI

struct RestrictionManagementView: View {
    let repository: any AssessmentRepository

    @State private var profiles: [RestrictionProfile] = []
    @State private var editingProfile: RestrictionProfile?
    @State private var profilePendingDeletion: RestrictionProfile?
    @State private var errorMessage: String?

    var body: some View {
        List {
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(profile.level.displayName)
                                    .foregroundStyle(profile.level.isHard ? .red : .secondary)
                                Text(profile.isActive ? "Active" : "Inactive")
                                    .font(.caption)
                                    .foregroundStyle(profile.isActive ? .orange : .secondary)
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
    @State private var profile: RestrictionProfile
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
            Form {
                Section("Injury") {
                    TextField("Name", text: $profile.injuryName)
                    TextField("Body region", text: $profile.bodyRegion)
                    TextField("Side", text: $profile.side)
                }
                Section("Restriction") {
                    Toggle("Active", isOn: $profile.isActive)
                    TextField("Movement or demand", text: $profile.movementTag)
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
                }
            }
            .navigationTitle("Restriction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
