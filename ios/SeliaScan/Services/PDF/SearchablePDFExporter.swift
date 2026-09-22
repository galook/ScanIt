import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

struct PDFExportResult: Sendable {
    let url: URL
    let byteCount: Int64
    let targetMet: Bool
    let iterations: Int
}

struct SearchablePDFExporter {
    private let compressor = PageAwareCompressor()

    func export(document: ScanDocument, repository: RecentRepository, targetURL: URL, progress: (@Sendable (Int) -> Void)? = nil) async throws -> PDFExportResult {
        let directory = await repository.directory(for: document.id)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("\(TemporaryFile.exportDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        guard let targetBytes = document.exportSettings.pdfTarget.maxBytes else {
            let pages = try renderPages(document.pages, directory: directory, work: work, maximumDimension: nil, quality: 0.98)
            let staging = work.appendingPathComponent("original.\(FileExtension.pdf)")
            try writePDF(pages: pages, documentPages: document.pages, to: staging, progress: progress)
            let bytes = try fileSize(staging)
            try publish(staging, to: targetURL)
            return PDFExportResult(url: targetURL, byteCount: bytes, targetMet: true, iterations: 1)
        }

        let dimension = compressor.maximumDimension(for: document.pages, targetBytes: targetBytes)
        let renderedDirectory = work.appendingPathComponent("rendered-pages", isDirectory: true)
        try FileManager.default.createDirectory(at: renderedDirectory, withIntermediateDirectories: true)
        let renderedPages = try renderPages(document.pages, directory: directory, work: renderedDirectory, maximumDimension: dimension, quality: 1)
        var low: CGFloat = 0.42
        var high: CGFloat = 0.96
        var bestUnder: (url: URL, bytes: Int64)?
        var bestReadable: (url: URL, bytes: Int64)?
        var iterations = 0

        for iteration in 0..<compressor.maximumIterations {
            try Task.checkCancellation()
            iterations = iteration + 1
            let quality = (low + high) / 2
            let iterationDirectory = work.appendingPathComponent("candidate-\(iteration)", isDirectory: true)
            try FileManager.default.createDirectory(at: iterationDirectory, withIntermediateDirectories: true)
            let pages = try transcodePages(renderedPages, documentPages: document.pages, work: iterationDirectory, quality: quality)
            let readable = try zip(document.pages, pages).allSatisfy { page, candidate in
                try compressor.preservesBarcodes(page.analysis?.barcodes ?? [], in: candidate)
            }
            guard readable else {
                low = quality
                try? FileManager.default.removeItem(at: iterationDirectory)
                continue
            }

            let pdf = iterationDirectory.appendingPathComponent("document.\(FileExtension.pdf)")
            try writePDF(pages: pages, documentPages: document.pages, to: pdf, progress: progress)
            let bytes = try fileSize(pdf)
            if bestReadable.map({ bytes < $0.bytes }) ?? true {
                let saved = work.appendingPathComponent("best-readable.\(FileExtension.pdf)")
                try replaceCopy(pdf, at: saved)
                bestReadable = (saved, bytes)
            }
            if bytes <= targetBytes {
                let saved = work.appendingPathComponent("best-under.\(FileExtension.pdf)")
                try replaceCopy(pdf, at: saved)
                bestUnder = (saved, bytes)
                low = quality
            } else {
                high = quality
            }
            try? FileManager.default.removeItem(at: iterationDirectory)
        }

        guard let selected = bestUnder ?? bestReadable else { throw PDFExportError.creationFailed }
        try publish(selected.url, to: targetURL)
        return PDFExportResult(url: targetURL, byteCount: selected.bytes, targetMet: selected.bytes <= targetBytes, iterations: iterations)
    }

    private func renderPages(_ pages: [ScanPage], directory: URL, work: URL, maximumDimension: Int?, quality: CGFloat) throws -> [URL] {
        var output: [URL] = []
        output.reserveCapacity(pages.count)
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let image = try autoreleasepool { try PageRenderer.shared.render(page: page, documentDirectory: directory, maximumPixelSize: maximumDimension) }
            let url = work.appendingPathComponent("page-\(index).\(FileExtension.jpeg)")
            try writeJPEG(image, to: url, quality: compressor.quality(for: page, baseQuality: quality))
            output.append(url)
        }
        return output
    }

    private func transcodePages(_ sources: [URL], documentPages: [ScanPage], work: URL, quality: CGFloat) throws -> [URL] {
        var output: [URL] = []
        output.reserveCapacity(sources.count)
        for (index, sourceURL) in sources.enumerated() {
            try Task.checkCancellation()
            let page = documentPages[index]
            let url = work.appendingPathComponent("page-\(index).\(FileExtension.jpeg)")
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PDFExportError.creationFailed }
                try writeJPEG(image, to: url, quality: compressor.quality(for: page, baseQuality: quality))
            }
            output.append(url)
        }
        return output
    }

    private func writePDF(pages: [URL], documentPages: [ScanPage], to destination: URL, progress: (@Sendable (Int) -> Void)?) throws {
        guard let consumer = CGDataConsumer(url: destination as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw PDFExportError.creationFailed }
        for (index, url) in pages.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PDFExportError.creationFailed }
                var media = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                context.beginPage(mediaBox: &media)
                context.draw(image, in: media)
                if documentPages.indices.contains(index), let tokens = documentPages[index].analysis?.tokens {
                    let revision = documentPages[index].revisions.first(where: { $0.id == documentPages[index].activeRevisionID })
                    let mapped = tokens.compactMap { token -> RecognizedToken? in guard let bounds = PDFCoordinateMapper.map(token.bounds, through: revision?.editState ?? PageEditState()) else { return nil }; return RecognizedToken(id: token.id, text: token.text, bounds: bounds, confidence: token.confidence) }
                    drawInvisibleText(mapped, in: media, context: context)
                }
                context.endPage()
            }
            progress?(index + 1)
        }
        context.closePDF()
    }

    private func drawInvisibleText(_ tokens: [RecognizedToken], in media: CGRect, context: CGContext) {
        context.saveGState()
        context.setFillColor(UIColor.clear.cgColor)
        context.textMatrix = .identity
        for token in tokens {
            let rect = CGRect(x: token.bounds.minX * media.width, y: token.bounds.minY * media.height, width: token.bounds.width * media.width, height: token.bounds.height * media.height)
            let font = CTFontCreateWithName("Helvetica" as CFString, max(6, rect.height * 0.8), nil)
            let text = NSAttributedString(string: token.text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: UIColor.clear])
            context.textPosition = rect.origin
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        context.restoreGState()
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw PDFExportError.creationFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PDFExportError.creationFailed }
    }

    private func replaceCopy(_ source: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func publish(_ source: URL, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).\(FileExtension.temporary)")
        try FileManager.default.copyItem(at: source, to: staging)
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging) }
        else { try FileManager.default.moveItem(at: staging, to: destination) }
    }

    private func fileSize(_ url: URL) throws -> Int64 { Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
}

enum PDFExportError: LocalizedError { case creationFailed; var errorDescription: String? { String(localized: "Could not create the PDF.") } }

struct PageAwareCompressor {
    let maximumIterations = 7

    func maximumDimension(for pages: [ScanPage], targetBytes: Int64) -> Int {
        let perPage = targetBytes / Int64(max(1, pages.count))
        let baseline: Int = perPage < 100_000 ? 1_280 : perPage < 300_000 ? 1_600 : perPage < 800_000 ? 2_200 : 3_200
        let containsBarcode = pages.contains { !($0.analysis?.barcodes.isEmpty ?? true) }
        let containsTinyText = pages.contains { ($0.analysis?.smallestTextHeight ?? 1) < 0.018 }
        return (containsBarcode || containsTinyText) ? max(2_400, baseline) : baseline
    }

    func quality(for page: ScanPage, baseQuality: CGFloat) -> CGFloat {
        let tokenComplexity = min(1, CGFloat(page.analysis?.tokens.count ?? 0) / 120)
        let visualComplexity = CGFloat(page.analysis?.visualComplexity ?? 0.35)
        let barcodeBoost: CGFloat = (page.analysis?.barcodes.isEmpty ?? true) ? 0 : 0.12
        let tinyTextBoost: CGFloat = (page.analysis?.smallestTextHeight ?? 1) < 0.018 ? 0.08 : 0
        let grayscaleSaving: CGFloat = page.analysis?.mostlyGrayscale == true && barcodeBoost == 0 ? 0.025 : 0
        return min(0.98, max(0.42, baseQuality + tokenComplexity * 0.06 + visualComplexity * 0.10 + barcodeBoost + tinyTextBoost - grayscaleSaving))
    }

    func preservesBarcodes(_ originals: [RecognizedBarcode], in candidate: URL) throws -> Bool {
        guard !originals.isEmpty else { return true }
        let request = VNDetectBarcodesRequest()
        request.symbologies = Array(Set(originals.compactMap { VNBarcodeSymbology(rawValue: $0.symbology) }))
        do { try VNImageRequestHandler(url: candidate).perform([request]) }
        catch { return candidateRetainsBarcodePixelFloor(originals, at: candidate) }
        let payloads = Set((request.results ?? []).compactMap(\.payloadStringValue))
        return originals.allSatisfy { payloads.contains($0.payload) }
    }

    private func candidateRetainsBarcodePixelFloor(_ barcodes: [RecognizedBarcode], at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return barcodes.allSatisfy { barcode in
            barcode.bounds.width * CGFloat(truncating: width) >= 240 && barcode.bounds.height * CGFloat(truncating: height) >= 240
        }
    }

    func barcodePreserved(before: [RecognizedBarcode], after: [RecognizedBarcode]) -> Bool {
        let payloads = Set(after.map(\.payload))
        return before.allSatisfy { payloads.contains($0.payload) }
    }
}
