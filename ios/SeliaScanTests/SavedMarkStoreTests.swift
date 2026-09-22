import XCTest
import UIKit
@testable import SeliaScan

final class SavedMarkStoreTests: XCTestCase {
    func testImportedStampIsNormalizedSavedAndMaterialized() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedMarkStore(directory: root.appendingPathComponent("marks"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 120)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
            UIColor.red.setFill(); context.fill(CGRect(x: 50, y: 30, width: 100, height: 60))
        }
        let mark = try await store.save(imageData: XCTUnwrap(image.pngData()), name: "Stamp")
        XCTAssertEqual(mark.kind, .stamp)
        let saved = try await store.list()
        XCTAssertEqual(saved.map(\.id), [mark.id])
        let preview = try await store.preview(mark)
        XCTAssertLessThan(preview.size.width, CGFloat(try XCTUnwrap(image.cgImage).width))
        XCTAssertLessThan(preview.size.height, CGFloat(try XCTUnwrap(image.cgImage).height))

        let document = root.appendingPathComponent("document")
        let reference = try await store.materialize(mark, in: document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reference.resolving(in: document).path))
    }

    func testSavedMarkLimitMatchesAndroid() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SavedMarkStore(directory: root.appendingPathComponent("marks"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in UIColor.black.setFill(); context.fill(CGRect(x: 2, y: 2, width: 16, height: 16)) }
        let data = try XCTUnwrap(image.pngData())
        for index in 0..<SavedMarkStore.maximumMarks { _ = try await store.save(imageData: data, name: "Stamp \(index)") }
        do { _ = try await store.save(imageData: data, name: "Too many"); XCTFail("Expected mark limit") }
        catch MarkStoreError.limitReached { }
    }
}
