import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportDocumentView: UIViewControllerRepresentable {
    let onURLs: ([URL]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController { var config = PHPickerConfiguration(photoLibrary: .shared()); config.filter = .images; config.selectionLimit = AppConfiguration.maximumScanPages; let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onURLs: onURLs) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onURLs: ([URL]) -> Void
        init(onURLs: @escaping ([URL]) -> Void) { self.onURLs = onURLs }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { picker.dismiss(animated: true); Task { var urls: [URL] = []; for result in results { if let url = await copiedURL(from: result.itemProvider) { urls.append(url) } }; await MainActor.run { self.onURLs(urls) } } }
        private func copiedURL(from provider: NSItemProvider) async -> URL? { await withCheckedContinuation { continuation in provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in guard let url else { continuation.resume(returning: nil); return }; let ext = url.pathExtension.isEmpty ? FileExtension.jpeg : url.pathExtension; let copy = TemporaryFile.importURL(extension: ext); do { try FileManager.default.copyItem(at: url, to: copy); continuation.resume(returning: copy) } catch { continuation.resume(returning: nil) } } } }
    }
}

struct FilesImportView: UIViewControllerRepresentable {
    let onURLs: ([URL]) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf], asCopy: true); picker.allowsMultipleSelection = true; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onURLs: onURLs) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate { let onURLs: ([URL]) -> Void; init(onURLs: @escaping ([URL]) -> Void) { self.onURLs = onURLs }; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onURLs(urls) } }
}
