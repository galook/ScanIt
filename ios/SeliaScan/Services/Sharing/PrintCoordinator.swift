import Foundation
import UIKit

@MainActor func printPDF(at url: URL) {
    guard UIPrintInteractionController.isPrintingAvailable else { return }
    let controller = UIPrintInteractionController.shared; let info = UIPrintInfo(dictionary: nil); info.outputType = .general; info.jobName = url.deletingPathExtension().lastPathComponent; controller.printInfo = info; controller.printingItem = url
    controller.present(animated: true) { _, _, _ in cleanupTemporaryFiles([url]) }
}
