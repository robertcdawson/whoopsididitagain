import ImageIO
import SwiftUI
import Vision
import VisionKit

/// Wraps the VisionKit document camera. Pages come back as JPEG data so the
/// on-device OCR step can run off the main actor without sharing UIKit objects.
struct ProtocolScannerView: UIViewControllerRepresentable {
    let onCompletion: ([Data]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: VNDocumentCameraViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancel: onCancel)
    }

    // VisionKit calls its delegate on the main thread, but the iOS 18 SDK does not
    // annotate the protocol as main-actor-isolated; @preconcurrency moves that
    // check to runtime so the coordinator can stay main-actor-isolated.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onCompletion: ([Data]) -> Void
        let onCancel: () -> Void

        init(onCompletion: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onCompletion = onCompletion
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [Data] = []
            for index in 0..<scan.pageCount {
                if let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.9) {
                    pages.append(data)
                }
            }
            onCompletion(pages)
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}

/// On-device text recognition for scanned PT sheets. The photo data never leaves
/// the process: Vision runs locally and only the recognized text moves on.
enum SheetTextRecognizer {
    static func recognizeText(in pages: [Data]) async throws -> String {
        let text = try await Task.detached(priority: .userInitiated) {
            var pageTexts: [String] = []
            for page in pages {
                guard
                    let source = CGImageSourceCreateWithData(page as CFData, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])
                let observations = request.results ?? []
                let lines =
                    observations
                    .sorted { lhs, rhs in
                        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                            return lhs.boundingBox.midY > rhs.boundingBox.midY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                pageTexts.append(lines.joined(separator: "\n"))
            }
            return pageTexts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }.value
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProtocolParseError.noTextRecognized
        }
        return text
    }
}
