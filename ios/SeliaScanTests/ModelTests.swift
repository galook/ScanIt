import XCTest
@testable import SeliaScan

final class ModelTests: XCTestCase {
    func testManifestRoundTrip() throws {
        let revision = PageRevision(id: UUID(), source: .init("originals/page.jpg"), editState: .init(), parentRevisionID: nil, isRedacted: false)
        let page = ScanPage(id: UUID(), source: revision.source, activeRevisionID: revision.id, revisions: [revision], thumbnail: .init("thumbnails/page.jpg"), analysis: nil)
        let document = ScanDocument(id: UUID(), createdAt: .now, pages: [page], exportSettings: .init(), trackedOutputs: [])
        XCTAssertEqual(try JSONDecoder().decode(ScanDocument.self, from: JSONEncoder().encode(document)).pages.count, 1)
    }
    func testRelativePathResolution() { XCTAssertEqual(RelativeFileReference("originals/a.jpg").resolving(in: URL(fileURLWithPath: "/tmp/document")).path, "/tmp/document/originals/a.jpg") }
    func testPDFTargets() { XCTAssertEqual(PDFSizeTarget.decode("500_kb").maxBytes, 500_000); XCTAssertEqual(PDFSizeTarget.decode("custom_1234_kb").maxBytes, 1_234_000) }
    func testConservativeOrientation() { XCTAssertEqual(conservativeOrientation(from: [91, 89, 94, 92, 90, 88], readableCharacters: 12), 270); XCTAssertEqual(conservativeOrientation(from: [4], readableCharacters: 2), 0) }
    func testBarcodePreservation() { let code = RecognizedBarcode(id: UUID(), payload: "secret", symbology: "QR", bounds: .zero); XCTAssertTrue(PageAwareCompressor().barcodePreserved(before: [code], after: [code])); XCTAssertFalse(PageAwareCompressor().barcodePreserved(before: [code], after: [])) }
    func testActiveRevisionIdentityChangesWhenEditsChange() {
        let revision = PageRevision(id: UUID(), source: .init("originals/page.jpg"), editState: .init(), parentRevisionID: nil, isRedacted: false)
        var page = ScanPage(id: UUID(), source: revision.source, activeRevisionID: revision.id, revisions: [revision], thumbnail: .init("thumbnails/page.jpg"), analysis: nil)
        let original = page.activeRevision
        page.revisions[0].editState.adjustments.brightness = 0.2
        XCTAssertNotEqual(original, page.activeRevision)
    }
}
