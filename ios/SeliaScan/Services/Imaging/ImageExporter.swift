import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageExporter {
    func export(document: ScanDocument, repository: RecentRepository, outputDirectory: URL) async throws -> [URL] {
        let directory = await repository.directory(for: document.id)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, page) in document.pages.enumerated() {
            try Task.checkCancellation()
            let baseName = document.exportSettings.imageBaseName.isEmpty ? document.exportSettings.pdfBaseName : document.exportSettings.imageBaseName
            let suffix = document.pages.count == 1 ? "" : "-\(index + 1)"
            let revision = page.revisions.first(where: { $0.id == page.activeRevisionID }) ?? page.revisions[0]
            let hasEdits = revision.editState.crop != nil || revision.editState.rotation != 0 || revision.editState.filter != .original || revision.editState.adjustments != ImageAdjustments() || !revision.editState.annotations.isEmpty

            if document.exportSettings.imageFormat == .original && !hasEdits {
                let source = revision.source.resolving(in: directory)
                let ext = source.pathExtension.isEmpty ? FileExtension.jpeg : source.pathExtension
                let destination = outputDirectory.appendingPathComponent("\(baseName)\(suffix).\(ext)")
                try replaceCopy(source, at: destination)
                urls.append(destination)
                continue
            }

            let image = try autoreleasepool { try PageRenderer.shared.render(page: page, documentDirectory: directory, maximumPixelSize: document.exportSettings.imageSize.maxDimension) }
            let format = document.exportSettings.imageFormat == .png ? UTType.png : UTType.jpeg
            let destination = outputDirectory.appendingPathComponent("\(baseName)\(suffix).\(format.preferredFilenameExtension ?? FileExtension.jpeg)")
            guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, format.identifier as CFString, 1, nil) else { throw ImagingError.renderFailed }
            let properties: CFDictionary = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary : [:] as CFDictionary
            CGImageDestinationAddImage(writer, image, properties)
            guard CGImageDestinationFinalize(writer) else { throw ImagingError.renderFailed }
            urls.append(destination)
        }
        return urls
    }

    private func replaceCopy(_ source: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
