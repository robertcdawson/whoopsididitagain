import SwiftUI

struct PainLogEditorRequest: Identifiable {
    let id = UUID()
    var entry: PainLogEntry?
    var preselectedBodyAreaID: String?

    init(entry: PainLogEntry? = nil, preselectedBodyAreaID: String? = nil) {
        self.entry = entry
        self.preselectedBodyAreaID = preselectedBodyAreaID
    }
}

struct PainLogEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: UUID?
    @State private var occurredAt: Date
    @State private var selectedAreaID: String?
    @State private var intensity: Int?
    @State private var note: String
    @State private var suggestedAreaIDs: [String] = []
    @State private var showingAreaPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    let repository: any AssessmentRepository
    let entry: PainLogEntry?
    let onSaved: (PainLogEntry) -> Void

    init(
        repository: any AssessmentRepository,
        entry: PainLogEntry? = nil,
        preselectedBodyAreaID: String? = nil,
        onSaved: @escaping (PainLogEntry) -> Void = { _ in }
    ) {
        self.repository = repository
        self.entry = entry
        self.onSaved = onSaved
        _occurredAt = State(initialValue: entry?.occurredAt ?? .now)
        _selectedAreaID = State(initialValue: entry?.bodyAreaID ?? preselectedBodyAreaID)
        _intensity = State(initialValue: entry?.intensity)
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("ow. where?")
                        .font(.journal(.title2, weight: .bold))
                        .accessibilityAddTraits(.isHeader)

                    JournalChipLayout {
                        ForEach(suggestedAreas) { area in
                            JournalChip(
                                label: area.shortLabel,
                                isSelected: selectedAreaID == area.id,
                                selectedFill: Color.journalRedPen,
                                accessibilityID: "pain-log-area-\(area.id)"
                            ) {
                                selectedAreaID = area.id
                            }
                        }
                        JournalChip(
                            label: "somewhere new",
                            isProminent: suggestedAreas.isEmpty,
                            accessibilityID: "pain-log-new-area"
                        ) {
                            focusedField = nil
                            showingAreaPicker = true
                        }
                    }

                    if let area = selectedArea {
                        Text("selected · \(area.label)")
                            .font(.journal(.footnote))
                            .foregroundStyle(Color.journalInk.opacity(0.7))
                            .accessibilityIdentifier("pain-log-selected-area")
                    }

                    JournalSection(title: "how much?") {
                        JournalScaleChipRow(
                            range: 0...10,
                            selected: intensity,
                            selectedFill: Color.journalRedPen,
                            accessibilityID: { "pain-log-intensity-\($0)" }
                        ) { intensity = $0 }
                    }

                    JournalSection(title: "what were you doing? (talk, optional)") {
                        TextField("Optional note", text: $note, axis: .vertical)
                            .lineLimit(3...7).journalInput()
                            .formKeyboardField(dismissOnSubmit: false)
                            .accessibilityIdentifier("pain-log-note")
                            .dictationInput($note)
                        Text("transcribed on this phone. edit anything it misheard.")
                            .font(.journal(.caption))
                            .foregroundStyle(Color.journalInk.opacity(0.6))
                    }

                    DatePicker("Occurred", selection: $occurredAt, in: ...Date.now)
                        .accessibilityIdentifier("pain-log-occurred-at")
                    Button("Now") { occurredAt = .now }
                    Text("lands in your Body story · open the pain log there to amend or remove")
                        .font(.journal(.caption))
                        .italic()
                        .foregroundStyle(Color.journalInk.opacity(0.65))
                }
                .padding(22)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(
                    entry == nil ? "Log pain" : "Save changes"
                ) {
                    save()
                }
                .buttonStyle(JournalPrimaryButtonStyle())
                .disabled(selectedAreaID == nil || intensity == nil || isSaving)
                .accessibilityIdentifier("pain-log-save")
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color.journalPaper)
            }
            .recoverableDraft(key: draftKey, value: draftBinding)
            .navigationTitle(entry == nil ? "Log Pain" : "Edit Pain")
            .navigationBarTitleDisplayMode(.inline)
            .journalForm()
            .formKeyboardScope($focusedField)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAreaPicker) {
                PainAreaPicker { area in
                    selectedAreaID = area.id
                    if !suggestedAreaIDs.contains(area.id) {
                        suggestedAreaIDs.insert(area.id, at: 0)
                    }
                }
            }
            .alert("Couldn’t log pain", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .presentationDetents([.large])

    }

    private var selectedArea: BodyAreaDefinition? {
        selectedAreaID.flatMap(BodyAreaCatalog.definition)
    }

    private var suggestedAreas: [BodyAreaDefinition] {
        var ids = suggestedAreaIDs
        if let selectedAreaID, !ids.contains(selectedAreaID) { ids.insert(selectedAreaID, at: 0) }
        return BodyAreaCatalog.definitions(for: Array(ids.prefix(5)))
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    @MainActor
    private func loadSuggestions() async {
        do {
            async let restrictions = repository.restrictions()
            async let logs = repository.painLogs()
            let candidateIDs =
                try await restrictions
                .filter(\.isActive)
                .flatMap(\.affectedAreaIDs) + logs.map(\.bodyAreaID)
            var seen = Set<String>()
            suggestedAreaIDs = candidateIDs.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var draftKey: String { "pain:" + (entry?.id ?? "new") }
    private struct Draft: Codable, Equatable {
        var area: String?
        var intensity: Int?
        var note: String
        var date: Date
    }
    private var draftBinding: Binding<Draft> {
        Binding(
            get: {
                Draft(area: selectedAreaID, intensity: intensity, note: note, date: occurredAt)
            },
            set: {
                selectedAreaID = $0.area
                intensity = $0.intensity
                note = $0.note
                occurredAt = $0.date
            })
    }

    private func save() {
        focusedField = nil
        guard let selectedAreaID, let intensity, occurredAt <= Date.now else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let saved = try PainLogEntry(
                    id: entry?.id ?? UUID().uuidString,
                    occurredAt: occurredAt,
                    bodyAreaID: selectedAreaID,
                    intensity: intensity,
                    note: note
                )
                try await repository.savePainLog(saved)
                try? EditorDraftStore.shared.finish(key: draftKey)
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PainLogHistoryView: View {
    let repository: any AssessmentRepository
    let onChange: ([PainLogEntry]) -> Void
    @State private var entries: [PainLogEntry] = []
    @State private var editingEntry: PainLogEntry?
    @State private var pendingDeletion: PainLogEntry?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Ad-hoc pain") {
                if entries.isEmpty {
                    Text("No standalone pain entries yet.")
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                } else {
                    ForEach(entries) { entry in
                        PainLogRow(entry: entry)
                            .onTapGesture { editingEntry = entry }
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 24).onEnded { value in
                                    guard value.translation.width < -60,
                                        abs(value.translation.width) > abs(value.translation.height)
                                    else { return }
                                    pendingDeletion = entry
                                }
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { editingEntry = entry }
                            .accessibilityAction(named: "Delete pain entry") {
                                pendingDeletion = entry
                            }
                            .accessibilityIdentifier("pain-log-history-row-\(entry.id)")
                    }
                }
            }
            .listRowBackground(Color.clear)
            Section {
                Text("These are your reported observations, not a diagnosis or proof of cause.")
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .journalForm()
        .navigationTitle("Pain log")
        .task { await load() }
        .sheet(item: $editingEntry) { entry in
            PainLogEditorView(repository: repository, entry: entry) { _ in
                Task { await load() }
            }
        }
        .confirmationDialog(
            "Delete this pain entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete pain entry", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await delete(entry) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the entry from local history and can’t be undone.")
        }
        .alert("Couldn’t update pain log", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    @MainActor
    private func load() async {
        do {
            entries = try await repository.painLogs()
            onChange(entries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ entry: PainLogEntry) async {
        do {
            try await repository.deletePainLog(id: entry.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PainLogRow: View {
    let entry: PainLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.bodyArea?.shortLabel ?? "Unknown area")
                    .font(.journal(.headline))
                Spacer()
                Text("\(entry.intensity)/10")
                    .font(.journal(.headline, weight: .bold))
                    .foregroundStyle(Color.journalRedPen)
            }
            Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.65))
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PainAreaPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (BodyAreaDefinition) -> Void

    var body: some View {
        NavigationStack {
            JournalList {
                ForEach(focuses) { focus in
                    Section(focus.displayName) {
                        ForEach(BodyAreaCatalog.all.filter { $0.focus == focus }) { area in
                            Button {
                                onSelect(area)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(area.shortLabel)
                                    if let view = area.viewLabel {
                                        Text(view)
                                            .font(.journal(.caption))
                                            .foregroundStyle(Color.journalInk.opacity(0.65))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pain-area-row-\(area.id)")
                        }
                    }
                }
            }
            .navigationTitle("Where does it hurt?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private let focuses = [
        BodyMapFocus(region: .headNeck, side: .midline),
        BodyMapFocus(region: .arm, side: .left),
        BodyMapFocus(region: .arm, side: .right),
        BodyMapFocus(region: .torso, side: .midline),
        BodyMapFocus(region: .leg, side: .left),
        BodyMapFocus(region: .leg, side: .right),
    ]
}
