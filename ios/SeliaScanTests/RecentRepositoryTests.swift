import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import SeliaScan

final class RecentRepositoryTests: XCTestCase {
    func testMalformedEntriesAreSkipped() async throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root.appendingPathComponent("SeliaScan/Recent/bad"), withIntermediateDirectories: true); let repository = RecentRepository(root: root); let scans = await repository.list(); XCTAssertTrue(scans.isEmpty) }
    func testRecentIsBoundedToEight() async throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); let image = root.appendingPathComponent("fixture.jpg"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try Data([1, 2, 3]).write(to: image); let repository = RecentRepository(root: root); for n in 0..<9 { _ = try await repository.createDocument(from: [image], name: "Scan \(n)") }; let scans = await repository.list(); XCTAssertEqual(scans.count, 8) }
    func testRecentRootExcludedFromBackup() async throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); let repository = RecentRepository(root: root); try await repository.prepare(); let recent = root.appendingPathComponent("SeliaScan/Recent"); XCTAssertEqual(try recent.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true) }
    func testOriginalImageTypeAndExtensionArePreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20)) }
        try XCTUnwrap(image.pngData()).write(to: source)
        let repository = RecentRepository(root: root)
        let document = try await repository.createDocument(from: [source])
        XCTAssertEqual(URL(fileURLWithPath: document.pages[0].source.path).pathExtension, "png")
        let stored = await repository.directory(for: document.id).appendingPathComponent(document.pages[0].source.path)
        let type = CGImageSourceCreateWithURL(stored as CFURL, nil).flatMap(CGImageSourceGetType)
        XCTAssertEqual(type as String?, UTType.png.identifier)
    }
    func testThirtyPageInputIsRejectedAtBoundWithoutCreatingRecentEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.jpg")
        try Data([1]).write(to: source)
        let repository = RecentRepository(root: root)
        do { _ = try await repository.createDocument(from: Array(repeating: source, count: 30)); XCTFail("Expected page bound") }
        catch StorageError.invalidPageCount { }
        let recent = await repository.list()
        XCTAssertTrue(recent.isEmpty)
    }
    func testTrackedFileTransitionsFromSavedToMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("saved.pdf")
        try Data([1, 2, 3]).write(to: output)
        let bookmark = try ExternalOutputStore().bookmark(for: output)
        let revision = PageRevision(id: UUID(), source: .init("originals/page.jpg"), editState: .init(), parentRevisionID: nil, isRedacted: false)
        var document = ScanDocument(id: UUID(), createdAt: .now, pages: [ScanPage(id: UUID(), source: revision.source, activeRevisionID: revision.id, revisions: [revision], thumbnail: .init("thumbnails/page.jpg"), analysis: nil)], exportSettings: .init(), trackedOutputs: [TrackedOutput(id: UUID(), kind: .pdf, filename: output.lastPathComponent, bookmark: bookmark, photosAssetIdentifier: nil, byteCount: 3, state: .saved)])
        let repository = RecentRepository(root: root)
        document = await repository.refreshingOutputStates(document)
        XCTAssertEqual(document.trackedOutputs[0].state, .saved)
        try FileManager.default.removeItem(at: output)
        document = await repository.refreshingOutputStates(document)
        XCTAssertEqual(document.trackedOutputs[0].state, .missing)
    }
}
