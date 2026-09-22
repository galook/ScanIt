import Foundation
import PDFKit
import UIKit

struct PDFImportService {
    func pageCount(at url: URL) throws -> Int { guard let document = PDFDocument(url: url) else { throw PDFExportError.creationFailed }; return document.pageCount }

    func renderPages(from url: URL, limit: Int, maximumDimension: CGFloat = 2_400) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else { throw PDFExportError.creationFailed }
            let count = min(document.pageCount, max(0, limit))
            var outputs: [URL] = []
            outputs.reserveCapacity(count)
            do {
                for index in 0..<count {
                    try Task.checkCancellation()
                    guard let page = document.page(at: index) else { throw PDFExportError.creationFailed }
                    outputs.append(try Self.render(page: page, maximumDimension: maximumDimension))
                }
                return outputs
            } catch {
                outputs.forEach { try? FileManager.default.removeItem(at: $0) }
                throw error
            }
        }.value
    }

    private static func render(page: PDFPage, maximumDimension: CGFloat) throws -> URL {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(1, maximumDimension / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(TemporaryFile.pdfPagePrefix)\(UUID().uuidString).\(FileExtension.jpeg)")
        guard let data = image.jpegData(compressionQuality: 0.98) else { throw PDFExportError.creationFailed }
        try data.write(to: output, options: .atomic)
        return output
    }
}
