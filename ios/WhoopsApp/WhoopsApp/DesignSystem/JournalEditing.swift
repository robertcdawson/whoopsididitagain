import CryptoKit
import SwiftUI

/// Drafts are separate from the clinical store and never participate in calculations.
@MainActor
final class EditorDraftStore {
    static let shared = EditorDraftStore()
    static let finished = Notification.Name("JournalEditorFinished")
    let directory: URL
    struct Envelope: Codable {
        var version = 1
        var key: String
        var updatedAt: Date
        var payload: Data
    }

    init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EditorDrafts", isDirectory: true)
            .appendingPathComponent(
                ProcessInfo.processInfo.environment["WHOOPS_DRAFT_NAMESPACE"].flatMap {
                    UUID(uuidString: $0)?.uuidString
                } ?? "personal", isDirectory: true)
    }

    private func url(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }

    func load<Value: Decodable>(_ type: Value.Type, key: String) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url(key).path) else { return nil }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url(key)))
        guard envelope.version == 1, envelope.key == key else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try JSONDecoder().decode(type, from: envelope.payload)
    }

    func save<Value: Encodable>(_ value: Value, key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = Envelope(key: key, updatedAt: .now, payload: try JSONEncoder().encode(value))
        try JSONEncoder().encode(envelope).write(
            to: url(key), options: [.atomic, .completeFileProtection])
    }

    func delete(key: String) throws {
        if FileManager.default.fileExists(atPath: url(key).path) {
            try FileManager.default.removeItem(at: url(key))
        }
    }

    func finish(key: String) throws {
        try delete(key: key)
        NotificationCenter.default.post(name: Self.finished, object: key)
    }

    func deleteSource(_ sourceID: String) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        {
            let data = try Data(contentsOf: file)
            // An unreadable payload cannot be restored and must not prevent deleting
            // an unrelated clinical record. Leave it intact for explicit recovery.
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
                continue
            }
            if envelope.key == sourceID || envelope.key.hasSuffix(":" + sourceID)
                || envelope.key.contains(":" + sourceID + ":")
            {
                try finish(key: envelope.key)
            }
        }
    }
}

extension View {
    func journalSaveBar<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            action().buttonStyle(JournalPrimaryButtonStyle())
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.journalPaper)
        }
    }

    func recoverableDraft<Value: Codable & Equatable>(
        key: String, value: Binding<Value>, ready: Bool = true
    ) -> some View {
        modifier(RecoverableDraft(key: key, value: value, ready: ready)).id(key)
    }

    func dictationInput(_ text: Binding<String>) -> some View {
        modifier(DictationInput(text: text))
    }
}

private struct RecoverableDraft<Value: Codable & Equatable>: ViewModifier {
    let key: String
    @Binding var value: Value
    var ready: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var initial: Value?
    @State private var pending: Value?
    @State private var loaded = false
    @State private var readFailed = false
    @State private var finished = false
    @State private var restoring = false
    @State private var confirmingDiscard = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .task(id: ready) {
                guard ready, !loaded else { return }
                initial = value
                do { pending = try EditorDraftStore.shared.load(Value.self, key: key) } catch {
                    readFailed = true
                    errorMessage = "Couldn't read your saved draft. It has not been deleted."
                }
                loaded = true
                restoring = pending != nil
            }
            .sheet(isPresented: $restoring) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Resume unfinished entry?").font(.journal(.title2, weight: .bold))
                    Text("Your unfinished changes are saved on this phone.").font(.journal(.body))
                    if let errorMessage { Text(errorMessage).foregroundStyle(Color.journalRedPen) }
                    Spacer(minLength: 0)
                    Button("Resume") {
                        if let pending { value = pending }
                        pending = nil
                        restoring = false
                    }.buttonStyle(JournalPrimaryButtonStyle())
                    Button("Discard draft", role: .destructive) { confirmingDiscard = true }
                        .buttonStyle(JournalLinkButtonStyle()).frame(maxWidth: .infinity)
                }
                .padding(22).background(Color.journalPaper)
                .presentationDetents(
                    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
                )
                .interactiveDismissDisabled()
                .alert("Discard this unfinished entry?", isPresented: $confirmingDiscard) {
                    Button("Discard draft", role: .destructive) {
                        do {
                            try EditorDraftStore.shared.delete(key: key)
                            pending = nil
                            restoring = false
                        } catch { errorMessage = error.localizedDescription }
                    }
                    Button("Keep draft", role: .cancel) {}
                }
            }
            .alert(
                "Draft recovery",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: value) { _, _ in
                if finished { finished = false }
                saveTask?.cancel()
                saveTask = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                    persist()
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
            .onDisappear {
                saveTask?.cancel()
                persist()
            }
            .onReceive(NotificationCenter.default.publisher(for: EditorDraftStore.finished)) {
                note in
                if note.object as? String == key {
                    initial = value
                    finished = true
                    saveTask?.cancel()
                }
            }
    }

    private func persist() {
        guard loaded, !readFailed, !finished, pending == nil, !confirmingDiscard
        else { return }
        do {
            if value == initial {
                try EditorDraftStore.shared.delete(key: key)
            } else {
                try EditorDraftStore.shared.save(value, key: key)
            }
        } catch {
            errorMessage = "Couldn't save the draft: \(error.localizedDescription)"
        }
    }
}

private struct DictationInput: ViewModifier {
    @Binding var text: String
    @StateObject private var model = OnDeviceDictationModel()
    @AppStorage("journalLeftHanded") private var leftHanded = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var prefix = ""

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if leftHanded { microphone }
                content
                if !leftHanded { microphone }
            }
            if let status = model.statusMessage {
                Text(status).font(.journal(.caption)).foregroundStyle(Color.journalRedPen)
            }
        }
        .onChange(of: model.transcript) { _, transcript in
            if !transcript.isEmpty { text = prefix + transcript }
        }
        .onDisappear { model.stopRecording() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.stopRecording() } }
    }

    private var microphone: some View {
        Button {
            if !model.isRecording {
                prefix = text.isEmpty ? "" : text + "\n"
                model.transcript = ""
            }
            Task { await model.toggleRecording() }
        } label: {
            Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                .frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(model.isRecording ? "Stop dictating note" : "Dictate note")
    }
}
