import XCTest
import UIKit
import PDFKit
import ImageIO
import CoreImage.CIFilterBuiltins
import Vision
@testable import SeliaScan

final class SecurityGeometryTests: XCTestCase {
    func testNormalizedCoordinatesStayBounded() { let token = RecognizedToken(id: UUID(), text: "SECRET", bounds: CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.1), confidence: 1); XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(token.bounds)) }
    func testCompressionIterationLimitIsBounded() { XCTAssertLessThanOrEqual(PageAwareCompressor().maximumIterations, 10) }
    func testPDFCoordinateMappingForRotationAndCrop() throws {
        var edits = PageEditState(); edits.rotation = 90
        let rotated = try XCTUnwrap(PDFCoordinateMapper.map(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), through: edits)); XCTAssertEqual(rotated.minX, 0.4, accuracy: 0.0001); XCTAssertEqual(rotated.minY, 0.1, accuracy: 0.0001); XCTAssertEqual(rotated.width, 0.4, accuracy: 0.0001); XCTAssertEqual(rotated.height, 0.3, accuracy: 0.0001)
        edits.rotation = 0; edits.crop = NormalizedQuad(topLeft: CGPoint(x: 0.25, y: 0.75), topRight: CGPoint(x: 0.75, y: 0.75), bottomRight: CGPoint(x: 0.75, y: 0.25), bottomLeft: CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(PDFCoordinateMapper.map(CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25), through: edits), CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
    }
    func testPageAwareAllocationProtectsBarcode() {
        let revision = PageRevision(id: UUID(), source: .init("a.jpg"), editState: .init(), parentRevisionID: nil, isRedacted: false)
        let plain = ScanPage(id: UUID(), source: revision.source, activeRevisionID: revision.id, revisions: [revision], thumbnail: .init("t.jpg"), analysis: PageAnalysis())
        var barcodePage = plain; barcodePage.analysis?.barcodes = [RecognizedBarcode(id: UUID(), payload: "123", symbology: "VNBarcodeSymbologyQR", bounds: .zero)]
        let compressor = PageAwareCompressor()
        XCTAssertGreaterThan(compressor.quality(for: barcodePage, baseQuality: 0.5), compressor.quality(for: plain, baseQuality: 0.5))
        XCTAssertGreaterThanOrEqual(compressor.maximumDimension(for: [barcodePage], targetBytes: 200_000), 2_400)
    }
    func testPageAwareQualityWeightsVisualComplexityAndTinyText() {
        let revision = PageRevision(id: UUID(), source: .init("a.jpg"), editState: .init(), parentRevisionID: nil, isRedacted: false)
        func page(complexity: Double, textHeight: Double) -> ScanPage {
            ScanPage(id: UUID(), source: revision.source, activeRevisionID: revision.id, revisions: [revision], thumbnail: .init("t.jpg"), analysis: PageAnalysis(visualComplexity: complexity, mostlyGrayscale: true, smallestTextHeight: textHeight))
        }
        let compressor = PageAwareCompressor()
        XCTAssertGreaterThan(compressor.quality(for: page(complexity: 0.9, textHeight: 0.01), baseQuality: 0.5), compressor.quality(for: page(complexity: 0.05, textHeight: 0.04), baseQuality: 0.5))
        XCTAssertGreaterThanOrEqual(compressor.maximumDimension(for: [page(complexity: 0.1, textHeight: 0.01)], targetBytes: 100_000), 2_400)
    }
    func testAppliedRedactionRemovesSearchableSecret() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); let source = root.appendingPathComponent("source.jpg"); let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400)); ("SECRET" as NSString).draw(at: CGPoint(x: 60, y: 180), withAttributes: [.foregroundColor: UIColor.black]) }; try image.jpegData(compressionQuality: 1)!.write(to: source)
        let repository = RecentRepository(root: root); var document = try await repository.createDocument(from: [source]); document.pages[0].analysis = PageAnalysis(tokens: [RecognizedToken(id: UUID(), text: "SECRET", bounds: CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.1), confidence: 1)], barcodes: [], lineAngles: [], analyzedAt: .now)
        let stroke = RedactionStroke(id: UUID(), points: [CGPoint(x: 0.15, y: 0.45), CGPoint(x: 0.6, y: 0.45)], width: 0.12, line: true); try await SecureRedactionService().apply(to: &document, pageIndex: 0, strokes: [stroke], repository: repository); XCTAssertFalse(document.pages[0].analysis!.tokens.contains { $0.text == "SECRET" })
        let output = root.appendingPathComponent("redacted.pdf"); _ = try await SearchablePDFExporter().export(document: document, repository: repository, targetURL: output); XCTAssertFalse(PDFDocument(url: output)?.string?.contains("SECRET") ?? true)
    }
    func testImpossibleTargetReturnsBestReadablePDFWithinIterationLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("page.jpg"); let image = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 1_400)).image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 1_400)); for row in 0..<30 { ("Readable document line \(row)" as NSString).draw(at: CGPoint(x: 80, y: 50 + row * 40), withAttributes: [.foregroundColor: UIColor.black]) } }; try image.jpegData(compressionQuality: 1)!.write(to: source)
        let repository = RecentRepository(root: root); var document = try await repository.createDocument(from: [source]); document.exportSettings.pdfTarget = .custom(kilobytes: 1)
        let output = root.appendingPathComponent("tiny.pdf"); let result = try await SearchablePDFExporter().export(document: document, repository: repository, targetURL: output)
        XCTAssertFalse(result.targetMet); XCTAssertLessThanOrEqual(result.iterations, PageAwareCompressor().maximumIterations); XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }
    func testSearchablePDFContainsTextRendersAndPreservesPageOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sources = try ["FIRST", "SECOND"].enumerated().map { index, word -> URL in
            let url = root.appendingPathComponent("page-\(index).png")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
                (word as NSString).draw(at: CGPoint(x: 50, y: 160), withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
            }
            try XCTUnwrap(image.pngData()).write(to: url)
            return url
        }
        let repository = RecentRepository(root: root)
        var document = try await repository.createDocument(from: sources)
        for index in document.pages.indices {
            document.pages[index].analysis = PageAnalysis(tokens: [RecognizedToken(id: UUID(), text: index == 0 ? "FIRST" : "SECOND", bounds: CGRect(x: 0.15, y: 0.4, width: 0.5, height: 0.12), confidence: 1)])
        }
        let output = root.appendingPathComponent("searchable.pdf")
        _ = try await SearchablePDFExporter().export(document: document, repository: repository, targetURL: output)
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertNotNil(pdf.page(at: 0)?.thumbnail(of: CGSize(width: 100, height: 100), for: .mediaBox).cgImage)
        let text = try XCTUnwrap(pdf.string)
        let first = try XCTUnwrap(text.range(of: "FIRST"))
        let second = try XCTUnwrap(text.range(of: "SECOND"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
    }
    func testPDFImportRendersAllRequestedPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for word in ["FIRST", "SECOND"] {
                context.beginPage()
                (word as NSString).draw(at: CGPoint(x: 40, y: 160), withAttributes: [.foregroundColor: UIColor.black])
            }
        }
        try data.write(to: source)
        let pages = try await PDFImportService().renderPages(from: source, limit: 20, maximumDimension: 200)
        defer { pages.forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertEqual(pages.count, 2)
        for page in pages {
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(page as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
            let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? NSNumber).intValue
            let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? NSNumber).intValue
            XCTAssertLessThanOrEqual(max(width, height), 200)
        }
    }
    func testTargetSizeExportKeepsDeterministicQRCodeReadable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = "seliascan-barcode-fixture"
        let qr = CIFilter.qrCodeGenerator(); qr.message = Data(payload.utf8); qr.correctionLevel = "H"
        let qrImage = try XCTUnwrap(CIContext().createCGImage(try XCTUnwrap(qr.outputImage), from: try XCTUnwrap(qr.outputImage).extent))
        let source = root.appendingPathComponent("qr.png")
        let imageFormat = UIGraphicsImageRendererFormat()
        imageFormat.scale = 1
        imageFormat.opaque = true
        let page = UIGraphicsImageRenderer(
            size: CGSize(width: 1_200, height: 1_600),
            format: imageFormat
        ).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_600))
            context.cgContext.interpolationQuality = .none
            context.cgContext.draw(qrImage, in: CGRect(x: 350, y: 550, width: 500, height: 500))
        }
        try XCTUnwrap(page.pngData()).write(to: source)
        let preflight = VNDetectBarcodesRequest(); preflight.symbologies = [.qr]
        do { try VNImageRequestHandler(cgImage: try XCTUnwrap(page.cgImage)).perform([preflight]) }
        catch { throw XCTSkip("Vision barcode inference is unavailable in this Simulator runtime: \(error.localizedDescription)") }
        guard (preflight.results ?? []).contains(where: { $0.payloadStringValue == payload }) else {
            throw XCTSkip("Vision barcode inference does not recognize the deterministic fixture in this Simulator runtime.")
        }
        let repository = RecentRepository(root: root)
        var document = try await repository.createDocument(from: [source])
        document.pages[0].analysis = PageAnalysis(barcodes: [RecognizedBarcode(id: UUID(), payload: payload, symbology: VNBarcodeSymbology.qr.rawValue, bounds: CGRect(x: 350.0 / 1_200, y: 550.0 / 1_600, width: 500.0 / 1_200, height: 500.0 / 1_600))], visualComplexity: 0.4, mostlyGrayscale: true)
        document.exportSettings.pdfTarget = .kb500
        let output = root.appendingPathComponent("qr.pdf")
        let result = try await SearchablePDFExporter().export(document: document, repository: repository, targetURL: output)
        XCTAssertLessThanOrEqual(result.iterations, PageAwareCompressor().maximumIterations)
        let rendered = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0)?.thumbnail(of: CGSize(width: 1_200, height: 1_600), for: .mediaBox).cgImage)
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        do { try VNImageRequestHandler(cgImage: rendered).perform([request]) }
        catch { throw XCTSkip("Vision barcode inference is unavailable in this Simulator runtime: \(error.localizedDescription)") }
        XCTAssertTrue((request.results ?? []).contains { $0.payloadStringValue == payload })
    }

    func testAnnotationUsesSameTopDownVerticalPositionAsPreview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageFormat = UIGraphicsImageRendererFormat()
        imageFormat.scale = 1
        imageFormat.opaque = true

        let sourceURL = root.appendingPathComponent("source.png")
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: imageFormat).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        try XCTUnwrap(source.pngData()).write(to: sourceURL)

        let markURL = root.appendingPathComponent("mark.png")
        let mark = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: imageFormat).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        try XCTUnwrap(mark.pngData()).write(to: markURL)

        var edits = PageEditState()
        edits.annotations = [PageAnnotation(id: UUID(), kind: .stamp, asset: .init("mark.png"), center: CGPoint(x: 0.5, y: 0.25), scale: 0.2, rotation: 0)]
        let revision = PageRevision(id: UUID(), source: .init("source.png"), editState: edits, parentRevisionID: nil, isRedacted: false)
        let page = ScanPage(id: UUID(), source: revision.source, activeRevisionID: revision.id, revisions: [revision], thumbnail: .init("source.png"), analysis: nil)
        let rendered = try PageRenderer.shared.render(page: page, documentDirectory: root)
        XCTAssertLessThan(try luminance(rendered, x: 100, y: 50), 0.2)
        XCTAssertGreaterThan(try luminance(rendered, x: 100, y: 150), 0.8)
    }

    private func luminance(_ image: CGImage, x: Int, y: Int) throws -> Double {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let displayed = UIImage(cgImage: image)
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in
            displayed.draw(at: CGPoint(x: CGFloat(-x), y: CGFloat(-y)))
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try XCTUnwrap(sample.cgImage), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }
}
