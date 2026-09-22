import SwiftUI
import UIKit

struct FileExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    let completion: (Result<[URL], Error>) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true); picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<[URL], Error>) -> Void
        init(completion: @escaping (Result<[URL], Error>) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(.success(urls)) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(.success([])) }
    }
}
