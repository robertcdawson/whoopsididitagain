import SwiftUI
import UniformTypeIdentifiers

struct MovementLibraryView: View {
    let repository: any MovementLibraryRepository

    @State private var summaries: [MovementUsageSummary] = []
    @State private var archivedMovements: [MovementDefinition] = []
    @State private var searchText = ""
    @State private var showsArchived = false
    @State private var isImporting = false
    @State private var importPreview: MovementLibraryImportPreview?
    @State private var editingMovement: MovementDefinition?
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    var body: some View {
        List {
            if searchText.isEmpty, !recentMovements.isEmpty {
                Section("Recent") {
                    ForEach(recentMovements) { row($0) }
                }
            }

            Section(searchText.isEmpty ? "All Movements" : "Results") {
                if filteredMovements.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredMovements) { row($0) }
                }
            }

            if showsArchived, !filteredArchivedMovements.isEmpty {
                Section("Archived") {
                    ForEach(filteredArchivedMovements) { archivedRow($0) }
                }
            }
        }
        .navigationTitle("Your Movements")
        .searchable(text: $searchText, prompt: "Name, alias, or equipment")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Import WOD Lab", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                .accessibilityIdentifier("import-wod-lab")
                Button("Add Movement", systemImage: "plus") {
                    editingMovement = .custom(name: "")
                }
                .accessibilityIdentifier("add-movement")
                Button(
                    showsArchived ? "Hide Archived" : "Show Archived",
                    systemImage: "archivebox"
                ) {
                    showsArchived.toggle()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingMovement) { movement in
            NavigationStack {
                MovementDefinitionEditor(movement: movement) { saved in
                    await save(saved)
                }
            }
        }
        .sheet(item: $importPreview) { preview in
            NavigationStack {
                MovementImportPreviewView(preview: preview) {
                    await importMovements(preview.data)
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            Task { await prepareImport(result) }
        }
        .alert("Movement Library", isPresented: messageIsPresented) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                resultMessage = nil
            }
        } message: {
            Text(errorMessage ?? resultMessage ?? "")
        }
    }

    private var recentMovements: [MovementUsageSummary] {
        Array(summaries.filter { $0.lastUsedAt != nil }.prefix(5))
    }

    private var filteredMovements: [MovementUsageSummary] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return summaries.sorted {
                $0.movement.canonicalName.localizedCaseInsensitiveCompare(
                    $1.movement.canonicalName
                ) == .orderedAscending
            }
        }
        let query = searchText.lowercased()
        return summaries.filter { summary in
            let movement = summary.movement
            return movement.canonicalName.lowercased().contains(query)
                || movement.aliases.contains { $0.lowercased().contains(query) }
                || movement.equipment.contains { $0.lowercased().contains(query) }
        }
    }

    private var filteredArchivedMovements: [MovementDefinition] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return archivedMovements
        }
        let query = searchText.lowercased()
        return archivedMovements.filter {
            $0.canonicalName.lowercased().contains(query)
                || $0.aliases.contains { $0.lowercased().contains(query) }
        }
    }

    @ViewBuilder
    private func row(_ summary: MovementUsageSummary) -> some View {
        Button {
            editingMovement = summary.movement
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(summary.movement.canonicalName)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(summary.movement.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(originLabel(summary.movement.origin))
                    if summary.appearanceCount > 0 {
                        Text("Used \(summary.appearanceCount)×")
                    }
                    if let lastUsedAt = summary.lastUsedAt {
                        Text(lastUsedAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Archive", role: .destructive) {
                Task { await setArchived(true, movement: summary.movement) }
            }
        }
    }

    @ViewBuilder
    private func archivedRow(_ movement: MovementDefinition) -> some View {
        Button {
            editingMovement = movement
        } label: {
            LabeledContent(movement.canonicalName, value: movement.category.displayName)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Restore") {
                Task { await setArchived(false, movement: movement) }
            }
            .tint(.accentColor)
        }
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || resultMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                    resultMessage = nil
                }
            }
        )
    }

    @MainActor
    private func load() async {
        do {
            try await repository.prepareDefaults()
            summaries = try await repository.usageSummaries()
            archivedMovements = try await repository.movements(includeArchived: true)
                .filter(\.isArchived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save(_ movement: MovementDefinition) async -> Bool {
        do {
            try await repository.saveMovement(movement)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func setArchived(_ archived: Bool, movement: MovementDefinition) async {
        do {
            try await repository.setArchived(archived, movementID: movement.id)
            await load()
            if archived {
                resultMessage =
                    "This movement was archived instead of deleted so saved workouts keep their details. It no longer appears in the active library."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func prepareImport(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            importPreview = try await repository.previewWODLabImport(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importMovements(_ data: Data) async -> Bool {
        do {
            let result = try await repository.importWODLab(data)
            resultMessage =
                "Added \(result.addedCount), matched \(result.matchedCount), and skipped \(result.skippedCount) movements."
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func originLabel(_ origin: MovementOrigin) -> String {
        switch origin {
        case .builtIn: "Built in"
        case .custom: "Personal"
        case .wodLab: "WOD Lab"
        }
    }
}

private struct MovementDefinitionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var movement: MovementDefinition
    @State private var aliasesText: String
    @State private var equipmentText: String
    @State private var isSaving = false

    let onSave: (MovementDefinition) async -> Bool

    init(
        movement: MovementDefinition,
        onSave: @escaping (MovementDefinition) async -> Bool
    ) {
        _movement = State(initialValue: movement)
        _aliasesText = State(initialValue: movement.aliases.joined(separator: ", "))
        _equipmentText = State(initialValue: movement.equipment.joined(separator: ", "))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Movement name", text: $movement.canonicalName)
                    .accessibilityIdentifier("movement-name")
                TextField("Aliases, separated by commas", text: $aliasesText, axis: .vertical)
                Picker("Category", selection: $movement.category) {
                    ForEach(MovementCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                TextField("Equipment, separated by commas", text: $equipmentText)
            }

            Section {
                ForEach(MovementMeasurement.allCases) { measurement in
                    Toggle(
                        measurement.displayName,
                        isOn: member(measurement, in: $movement.supportedMeasurements)
                    )
                }
                TextField(
                    "Preferred unit (optional)", text: optionalString($movement.preferredUnit))
            } header: {
                Text("Measurements")
            } footer: {
                Text("These describe what can be recorded, not a prescription for future workouts.")
            }

            Section {
                ForEach(MovementDemand.allCases) { demand in
                    Toggle(demand.displayName, isOn: member(demand, in: $movement.demandTags))
                }
            } header: {
                Text("Restriction Demands")
            } footer: {
                Text(
                    "Review these carefully. An untagged personal movement is not treated as proven safe for an active restriction."
                )
            }
        }
        .navigationTitle(movement.canonicalName.isEmpty ? "New Movement" : "Edit Movement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(
                        isSaving
                            || movement.canonicalName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                    .accessibilityIdentifier("save-movement")
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        movement.aliases = split(aliasesText)
        movement.equipment = split(equipmentText)
        movement.movementFamily = movement.category.rawValue
        if await onSave(movement) { dismiss() }
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private func member<Value: Hashable>(
        _ value: Value,
        in set: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { enabled in
                if enabled {
                    set.wrappedValue.insert(value)
                } else {
                    set.wrappedValue.remove(value)
                }
            }
        )
    }

    private func optionalString(_ value: Binding<String?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue ?? "" },
            set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct MovementImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: MovementLibraryImportPreview
    let onImport: () async -> Bool
    @State private var isImporting = false

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("New movements", value: "\(preview.additions.count)")
                LabeledContent("Already matched", value: "\(preview.matchedCount)")
                LabeledContent("Skipped", value: "\(preview.skippedCount)")
            }
            if !preview.additions.isEmpty {
                Section("Will Add") {
                    ForEach(preview.additions) { movement in
                        LabeledContent(
                            movement.canonicalName,
                            value: movement.category.displayName
                        )
                    }
                }
            }
            if !preview.issues.isEmpty {
                Section("Notes") {
                    ForEach(Array(preview.issues.enumerated()), id: \.offset) { _, issue in
                        Text(issue).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Review Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    Task {
                        isImporting = true
                        if await onImport() { dismiss() }
                        isImporting = false
                    }
                }
                .disabled(isImporting || !preview.canImport)
            }
        }
    }
}

extension MovementLibraryImportPreview: Identifiable {
    var id: String {
        additions.map(\.id).joined(separator: ":") + ":\(matchedCount):\(skippedCount)"
    }
}
