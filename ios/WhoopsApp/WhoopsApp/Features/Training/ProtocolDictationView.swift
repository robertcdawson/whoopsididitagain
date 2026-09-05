import AVFoundation
import Speech
import SwiftUI

/// Reusable live dictation for short, user-authored text. Recognition is required
/// to run on-device so health and protocol notes never leave the phone.
@MainActor
final class OnDeviceDictationModel: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var statusMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingID: UUID?

    func toggleRecording() async {
        if recordingID != nil {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard recordingID == nil else { return }
        let requestID = UUID()
        recordingID = requestID
        defer { if !isRecording, recordingID == requestID { recordingID = nil } }
        statusMessage = nil
        let permitted = await requestPermissions()
        guard recordingID == requestID, !Task.isCancelled else { return }
        guard permitted else {
            statusMessage = "Microphone or speech permission was declined. Type the text instead."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            statusMessage = "Speech recognition isn't available right now. Type the text instead."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            statusMessage =
                "This device can't transcribe on-device, so nothing was recorded. Type instead."
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        var installedTap = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            nonisolated(unsafe) let bufferRequest = request
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                bufferRequest.append(buffer)
            }
            installedTap = true
            engine.prepare()
            try engine.start()
        } catch {
            engine.stop()
            if installedTap { engine.inputNode.removeTap(onBus: 0) }
            request.endAudio()
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
            statusMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        audioEngine = engine
        recognitionRequest = request
        isRecording = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            let failureMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.recordingID == requestID else { return }
                if let text { self.transcript = text }
                if let failureMessage {
                    self.statusMessage =
                        "Dictation stopped: \(failureMessage). You can keep editing the text."
                }
                if failed || isFinal { self.stopRecording() }
            }
        }
    }

    func stopRecording() {
        recordingID = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

struct ProtocolDictationSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = OnDeviceDictationModel()
    @FocusState private var focusedField: UUID?
    @Environment(\.dismiss) private var dismiss
    let onUse: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("read the sheet aloud — movement, sets, reps.")
                        .font(.journal(.subheadline))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Task { await model.toggleRecording() }
                    } label: {
                        Label(
                            model.isRecording ? "stop listening" : "start listening",
                            systemImage: model.isRecording ? "mic.fill" : "mic"
                        )
                        .font(.journal(.title3, weight: .semibold))
                        .foregroundStyle(Color.journalPaper)
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isRecording ? Color.journalRedPen : Color.journalInk)
                    .accessibilityIdentifier("protocol-dictation-toggle")

                    if let status = model.statusMessage {
                        Text(status)
                            .font(.journal(.footnote))
                            .foregroundStyle(Color.journalRedPen)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    TextEditor(text: $model.transcript)
                        .font(.journal(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .journalInput()
                        .formKeyboardField(dismissOnSubmit: false)
                        .accessibilityIdentifier("protocol-dictation-transcript")

                    Text("transcribed on this phone. edit anything it misheard.")
                        .font(.journal(.footnote))
                        .foregroundStyle(Color.journalInk.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                }
                .padding()
            }
            .journalSaveBar {
                Button {
                    focusedField = nil
                    model.stopRecording()
                    onUse(model.transcript)
                } label: {
                    Text("use this text")
                        .font(.journal(.title3, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(JournalPrimaryButtonStyle())
                .tint(Color.journalInk)
                .disabled(
                    model.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("protocol-dictation-use")
            }
            .journalForm()
            .formKeyboardScope($focusedField)
            .recoverableDraft(key: "protocol-dictation:new", value: $model.transcript)
            .navigationTitle("Read It Aloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        model.stopRecording()
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.stopRecording() } }
        .onDisappear { model.stopRecording() }
    }
}
