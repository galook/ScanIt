import Foundation
import SwiftUI
import VisionKit
import UIKit

struct ScannedDocumentInput: Sendable { let imageURLs: [URL] }
protocol DocumentScanning: Sendable { @MainActor func scan() async throws -> ScannedDocumentInput }
enum ScannerError: LocalizedError { case unavailable, cancelled, failed(String)
    var errorDescription: String? { switch self { case .unavailable: String(localized: "Document scanning is not available on this device."); case .cancelled: String(localized: "Scan cancelled."); case .failed(let message): message } }
}

struct VisionKitDocumentScanner: DocumentScanning {
    @MainActor func scan() async throws -> ScannedDocumentInput {
        guard VNDocumentCameraViewController.isSupported else { throw ScannerError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = ScannerCoordinator(continuation: continuation)
            let controller = VNDocumentCameraViewController(); controller.delegate = coordinator
            ScannerPresentation.shared.present(controller, coordinator: coordinator)
        }
    }
}

@MainActor private final class ScannerPresentation {
    static let shared = ScannerPresentation(); private var retainedCoordinator: ScannerCoordinator?
    func present(_ controller: UIViewController, coordinator: ScannerCoordinator) {
        retainedCoordinator = coordinator
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var presenter = scene.keyWindow?.rootViewController else { coordinator.finish(.failure(ScannerError.unavailable)); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(controller, animated: true)
    }
    func release(_ coordinator: ScannerCoordinator) { if retainedCoordinator === coordinator { retainedCoordinator = nil } }
}
@MainActor private final class ScannerCoordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    var continuation: CheckedContinuation<ScannedDocumentInput, Error>?
    init(continuation: CheckedContinuation<ScannedDocumentInput, Error>) { self.continuation = continuation }
    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { controller.dismiss(animated: true); finish(.failure(ScannerError.cancelled)) }
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { controller.dismiss(animated: true); finish(.failure(ScannerError.failed(error.localizedDescription))) }
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        guard scan.pageCount <= AppConfiguration.maximumScanPages else {
            controller.dismiss(animated: true)
            finish(.failure(ScannerError.failed(String(localized: "A scan can contain at most 20 pages."))))
            return
        }
        let images = (0..<scan.pageCount).map(scan.imageOfPage(at:))
        controller.dismiss(animated: true)
        Task.detached(priority: .userInitiated) {
            let result = Result { try Self.archive(images) }
            await MainActor.run { self.finish(result) }
        }
    }

    nonisolated private static func archive(_ images: [UIImage]) throws -> ScannedDocumentInput {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(TemporaryFile.scanDirectoryPrefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        do {
            for (index, image) in images.enumerated() {
                try Task.checkCancellation()
                let url = directory.appendingPathComponent(StorageLayout.originalPageFilename(index: index, extension: FileExtension.jpeg))
                guard let data = image.jpegData(compressionQuality: 0.98) else { throw ScannerError.failed(String(localized: "Could not archive scanned page.")) }
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return ScannedDocumentInput(imageURLs: urls)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    func finish(_ result: Result<ScannedDocumentInput, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        Task { @MainActor in ScannerPresentation.shared.release(self) }
    }
}

struct FixtureDocumentScanner: DocumentScanning {
    let urls: [URL]
    func scan() async throws -> ScannedDocumentInput { guard !urls.isEmpty else { throw ScannerError.unavailable }; return ScannedDocumentInput(imageURLs: urls) }
}
