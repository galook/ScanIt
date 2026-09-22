import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareCoordinator: NSObject, UIActivityItemSource {
    let url: URL; let subject: String
    init(url: URL, subject: String) { self.url = url; self.subject = subject }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String { subject }
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { UTType.pdf.identifier }
}

@MainActor func presentShareSheet(url: URL, subject: String = AppConfiguration.defaultShareSubject) {
    presentShareSheet(urls: [url], subject: subject)
}

@MainActor func presentShareSheet(urls: [URL], subject: String = AppConfiguration.defaultShareSubject) {
    let items: [Any] = urls.enumerated().map { index, url -> Any in
        if index == 0 && url.pathExtension.lowercased() == FileExtension.pdf { return ShareCoordinator(url: url, subject: subject) }
        return url
    }
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.completionWithItemsHandler = { _, _, _, _ in cleanupTemporaryFiles(urls) }
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first, var presenter = scene.keyWindow?.rootViewController else { return }
    while let presented = presenter.presentedViewController { presenter = presented }
    if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
    }
    presenter.present(controller, animated: true)
}

func cleanupTemporaryFiles(_ urls: [URL]) {
    let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
    for url in urls where url.standardizedFileURL.path.hasPrefix(temporary + "/") {
        try? FileManager.default.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix(TemporaryFile.imageExportDirectoryPrefix) { try? FileManager.default.removeItem(at: parent) }
    }
}
