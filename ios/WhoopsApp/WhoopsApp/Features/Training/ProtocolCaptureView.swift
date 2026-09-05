import SwiftUI
import VisionKit

/// Protocol intake: three equal paths — camera, paste, dictation — into the same
/// deterministic parser. OCR and dictation stay on-device; the sheet never leaves
/// the phone.
struct ProtocolCaptureView: View {
    let parser: any ProtocolParser
    let scalingEngine: any WorkoutScalingEngine
    let movementLibrary: any MovementLibraryRepository
    let protocolRepository: any ProtocolRepository
    let restrictions: [RestrictionProfile]
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingScanner = false
    @State private var isShowingPaste = false
    @State private var isShowingDictation = false
    @State private var isProcessing = false
    @State private var reviewing: ParsedProtocol?
    @State private var errorMessage: String?

    private var isCameraSupported: Bool { VNDocumentCameraViewController.isSupported }

    var body: some View {
        NavigationStack {
            captureScreen
                .recoverableDraft(key: "protocol-capture:new", value: $reviewing)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Color.journalCaptureGold)
                            .accessibilityIdentifier("protocol-capture-close")
                    }
                }
                .navigationDestination(item: $reviewing) { parsed in
                    ProtocolParseReviewView(
                        parsed: parsed,
                        scalingEngine: scalingEngine,
                        movementLibrary: movementLibrary,
                        protocolRepository: protocolRepository,
                        restrictions: restrictions
                    ) {
                        try? EditorDraftStore.shared.finish(key: "protocol-capture:new")
                        try? EditorDraftStore.shared.finish(key: "protocol-paste:new")
                        try? EditorDraftStore.shared.finish(key: "protocol-dictation:new")
                        await onSaved()
                        dismiss()
                    }
                }
                .fullScreenCover(isPresented: $isShowingScanner) {
                    ProtocolScannerView(
                        onCompletion: { pages in handleScannedPages(pages) },
                        onCancel: { isShowingScanner = false }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $isShowingPaste) {
                    ProtocolPasteSheet { text in
                        isShowingPaste = false
                        parse(text: text, source: .paste)
                    }
                    .preferredColorScheme(.light)
                }
                .sheet(isPresented: $isShowingDictation) {
                    ProtocolDictationSheet { text in
                        isShowingDictation = false
                        parse(text: text, source: .dictation)
                    }
                    .preferredColorScheme(.light)
                }
                .alert("Couldn't read the protocol", isPresented: errorIsPresented) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "Unknown error")
                }
        }
        .preferredColorScheme(reviewing == nil ? .dark : .light)
    }

    private var captureScreen: some View {
        ZStack {
            Color.journalCaptureBackground.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    captureContent
                        .frame(minHeight: geometry.size.height)
                }
            }

            if isProcessing {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("reading the sheet…")
                        .font(.journal(.callout))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var captureContent: some View {
        VStack(spacing: 0) {
            Text("point it at the PT sheet")
                .font(.journal(.title2, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 12)

            sheetFrame
                .frame(height: 360)
                .padding(.top, 22)
                .padding(.horizontal, 34)

            Text("read on this phone. parsed by math.")
                .font(.journal(.callout))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 14)
            Text(
                isCameraSupported
                    ? "the sheet never leaves the device"
                    : "camera scanning isn't available here — paste instead"
            )
            .font(.journal(.footnote))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, 2)

            Spacer(minLength: 12)

            shutterButton

            HStack(spacing: 26) {
                captureLink("paste instead", identifier: "protocol-paste-link") {
                    isShowingPaste = true
                }
                captureLink("read it aloud", identifier: "protocol-dictate-link") {
                    isShowingDictation = true
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 16)
        }
        .padding(.horizontal)

    }

    private var sheetFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
            SheetIllustration()
                .frame(width: 190, height: 270)
                .rotationEffect(.degrees(-2))
                .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
            CornerBrackets()
                .stroke(
                    Color.journalCaptureGold,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .padding(6)
        }
        .frame(maxHeight: 420)
        .accessibilityHidden(true)
    }

    private var shutterButton: some View {
        Button {
            if isCameraSupported {
                isShowingScanner = true
            } else {
                errorMessage =
                    "Camera scanning isn't available on this device. Paste the text instead."
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(Color.white.opacity(isCameraSupported ? 0.95 : 0.35))
                    .frame(width: 60, height: 60)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan the PT sheet with the camera")
        .accessibilityIdentifier("protocol-scan")
    }

    private func captureLink(
        _ label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.journal(.body))
                .foregroundStyle(Color.journalCaptureGold)
                .underline()
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func handleScannedPages(_ pages: [Data]) {
        isShowingScanner = false
        guard !pages.isEmpty else { return }
        isProcessing = true
        Task { @MainActor in
            defer { isProcessing = false }
            do {
                let text = try await SheetTextRecognizer.recognizeText(in: pages)
                reviewing = try await parser.parse(rawText: text, source: .photo)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func parse(text: String, source: ProtocolSource) {
        isProcessing = true
        Task { @MainActor in
            defer { isProcessing = false }
            do {
                reviewing = try await parser.parse(rawText: text, source: source)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Simplified "paper sheet" illustration inside the camera frame.
private struct SheetIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.95, green: 0.94, blue: 0.90))
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.journalDot.opacity(0.55))
                    .frame(width: 110, height: 11)
                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .fill(Color.journalDot.opacity(0.4))
                        .frame(width: index.isMultiple(of: 3) ? 150 : 120, height: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }
}

/// The four gold corner brackets from the capture mockup.
private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm: CGFloat = 28
        let inset: CGFloat = 10
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset
        path.move(to: CGPoint(x: minX, y: minY + arm))
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX + arm, y: minY))
        path.move(to: CGPoint(x: maxX - arm, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY + arm))
        path.move(to: CGPoint(x: maxX, y: maxY - arm))
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - arm, y: maxY))
        path.move(to: CGPoint(x: minX + arm, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: maxY - arm))
        return path
    }
}

/// Paste (and share-sheet fallback) path into the parser.
private struct ProtocolPasteSheet: View {
    @State private var text = ""
    @FocusState private var focusedField: UUID?
    @Environment(\.dismiss) private var dismiss
    let onUse: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("paste the protocol text — one item per line works best.")
                        .font(.journal(.subheadline))
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextEditor(text: $text)
                        .font(.journal(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .journalInput()
                        .formKeyboardField(dismissOnSubmit: false)
                        .accessibilityIdentifier("protocol-paste-entry")

                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first {
                            text = pasted
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .tint(Color.journalInk)

                    Spacer()

                }
                .padding()
            }
            .journalSaveBar {
                Button {
                    focusedField = nil
                    onUse(text)
                } label: {
                    Text("parse it")
                        .font(.journal(.title3, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(JournalPrimaryButtonStyle())
                .tint(Color.journalInk)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("protocol-paste-use")
            }
            .journalForm()
            .formKeyboardScope($focusedField)
            .recoverableDraft(key: "protocol-paste:new", value: $text)
            .navigationTitle("Paste the Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ProtocolCaptureView(
        parser: DeterministicProtocolParser(),
        scalingEngine: DeterministicWorkoutScalingEngine(),
        movementLibrary: PreviewMovementLibraryRepository(),
        protocolRepository: PreviewProtocolRepository(),
        restrictions: [],
        onSaved: {}
    )
}
