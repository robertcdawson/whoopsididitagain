import AVFoundation
import Speech
import SwiftUI

/// Live dictation for protocol intake. Recognition is required to run on-device;
/// when the device cannot do that, dictation declines and points at paste instead
/// so the sheet's text never leaves the phone.
@MainActor
final class ProtocolDictationModel: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var statusMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        statusMessage = nil
        guard await requestPermissions() else {
            statusMessage = "Microphone or speech permission was declined. Paste the text instead."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            statusMessage = "Speech recognition isn't available right now. Paste the text instead."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            statusMessage =
                "This device can't transcribe on-device, so nothing was recorded. Paste instead."
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
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
            engine.prepare()
            try engine.start()
        } catch {
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if failed || isFinal { self.stopRecording() }
            }
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
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
    @StateObject private var model = ProtocolDictationModel()
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
                .padding()
            }
            .journalForm()
            .formKeyboardScope($focusedField)
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
        .onDisappear { model.stopRecording() }
    }
}
