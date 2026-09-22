import SwiftUI
import PencilKit
import UIKit
import ImageIO

struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    func makeUIView(context: Context) -> PKCanvasView { let view = PKCanvasView(); view.drawingPolicy = .anyInput; view.tool = PKInkingTool(.pen, color: .label, width: 3); view.backgroundColor = .clear; view.delegate = context.coordinator; return view }
    func updateUIView(_ view: PKCanvasView, context: Context) { if view.drawing != drawing { view.drawing = drawing } }
    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }
    final class Coordinator: NSObject, PKCanvasViewDelegate { var drawing: Binding<PKDrawing>; init(drawing: Binding<PKDrawing>) { self.drawing = drawing }; func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing.wrappedValue = canvasView.drawing } }
}

struct SavedMark: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var kind: AnnotationKind
    var pencilKitData: Data?
    var image: RelativeFileReference?
}

actor SavedMarkStore {
    static let maximumMarks = 12
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(StorageLayout.appDirectory, isDirectory: true)
            .appendingPathComponent(StorageLayout.marksDirectory, isDirectory: true)
    }

    func list() throws -> [SavedMark] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == FileExtension.json }
            .compactMap { url -> (SavedMark, Date)? in
                guard let data = try? Data(contentsOf: url), let mark = try? JSONDecoder().decode(SavedMark.self, from: data) else { return nil }
                return (mark, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func save(drawing: PKDrawing, name: String) throws -> SavedMark {
        try validate(drawing)
        let mark = SavedMark(id: UUID(), name: name, kind: .signature, pencilKitData: drawing.dataRepresentation(), image: nil)
        try saveMetadata(mark)
        return mark
    }

    func save(imageData: Data, name: String) throws -> SavedMark {
        try prepare()
        try enforceLimit()
        guard imageData.count <= 20_000_000, let normalized = normalizedMarkPNG(from: imageData) else { throw MarkStoreError.invalidImage }
        let id = UUID()
        let imageReference = RelativeFileReference("\(id.uuidString).\(FileExtension.png)")
        let imageURL = imageReference.resolving(in: directory)
        try normalized.write(to: imageURL, options: .atomic)
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: imageURL.path)
        let mark = SavedMark(id: id, name: name, kind: .stamp, pencilKitData: nil, image: imageReference)
        do { try writeMetadata(mark) } catch { try? FileManager.default.removeItem(at: imageURL); throw error }
        return mark
    }

    func preview(_ mark: SavedMark, maximumSide: CGFloat = 1_024) throws -> UIImage {
        if let data = mark.pencilKitData, let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
            let scale = max(1, maximumSide / max(drawing.bounds.width, drawing.bounds.height))
            return drawing.image(from: drawing.bounds, scale: scale)
        }
        guard let reference = mark.image, let image = UIImage(contentsOfFile: reference.resolving(in: directory).path) else { throw MarkStoreError.invalidImage }
        return image
    }

    func materialize(_ mark: SavedMark, in documentDirectory: URL) throws -> RelativeFileReference {
        let marks = documentDirectory.appendingPathComponent(StorageLayout.revisionMarksDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: marks, withIntermediateDirectories: true)
        let ext = mark.kind == .signature ? FileExtension.drawing : FileExtension.png
        let reference = StorageLayout.markReference(id: UUID(), extension: ext)
        let destination = reference.resolving(in: documentDirectory)
        if let data = mark.pencilKitData { try data.write(to: destination, options: .atomic) }
        else if let image = mark.image { try FileManager.default.copyItem(at: image.resolving(in: directory), to: destination) }
        else { throw MarkStoreError.invalidImage }
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: destination.path)
        return reference
    }

    func materialize(drawingData: Data, in documentDirectory: URL) throws -> RelativeFileReference {
        guard let drawing = try? PKDrawing(data: drawingData), !drawing.bounds.isEmpty else { throw MarkStoreError.invalidImage }
        try validate(drawing)
        let marks = documentDirectory.appendingPathComponent(StorageLayout.revisionMarksDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: marks, withIntermediateDirectories: true)
        let reference = StorageLayout.markReference(id: UUID(), extension: FileExtension.drawing)
        try drawingData.write(to: reference.resolving(in: documentDirectory), options: .atomic)
        return reference
    }

    func materialize(imageData: Data, in documentDirectory: URL) throws -> RelativeFileReference {
        guard imageData.count <= 20_000_000, let normalized = normalizedMarkPNG(from: imageData) else { throw MarkStoreError.invalidImage }
        let marks = documentDirectory.appendingPathComponent(StorageLayout.revisionMarksDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: marks, withIntermediateDirectories: true)
        let reference = StorageLayout.markReference(id: UUID(), extension: FileExtension.png)
        try normalized.write(to: reference.resolving(in: documentDirectory), options: .atomic)
        return reference
    }

    func preview(imageData: Data) throws -> UIImage {
        guard imageData.count <= 20_000_000, let normalized = normalizedMarkPNG(from: imageData), let image = UIImage(data: normalized) else { throw MarkStoreError.invalidImage }
        return image
    }

    func delete(_ mark: SavedMark) throws {
        try prepare()
        if let image = mark.image { try? FileManager.default.removeItem(at: image.resolving(in: directory)) }
        let metadata = directory.appendingPathComponent(StorageLayout.savedMarkMetadataFilename(id: mark.id))
        guard FileManager.default.fileExists(atPath: metadata.path) else { throw MarkStoreError.missing }
        try FileManager.default.removeItem(at: metadata)
    }

    private func saveMetadata(_ mark: SavedMark) throws {
        try prepare()
        try enforceLimit()
        try writeMetadata(mark)
    }

    private func writeMetadata(_ mark: SavedMark) throws {
        let url = directory.appendingPathComponent(StorageLayout.savedMarkMetadataFilename(id: mark.id))
        try JSONEncoder().encode(mark).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: url.path)
    }

    private func enforceLimit() throws {
        if try list().count >= Self.maximumMarks { throw MarkStoreError.limitReached }
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: directory.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; var mutable = directory; try? mutable.setResourceValues(values)
    }

    private func validate(_ drawing: PKDrawing) throws {
        guard !drawing.strokes.isEmpty, drawing.strokes.count <= AppConfiguration.maximumMarkStrokes, drawing.dataRepresentation().count <= 20_000_000 else { throw MarkStoreError.invalidImage }
    }
}

private func normalizedMarkPNG(from data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
            kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary) else { return nil }
    let width = image.width, height = image.height, bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let paper = min(pixels[offset], min(pixels[offset + 1], pixels[offset + 2]))
            let originalAlpha = pixels[offset + 3]
            let inkAlpha: UInt8 = paper >= 245 ? 0 : (paper <= 220 ? 255 : UInt8((245 - Int(paper)) * 255 / 25))
            let alpha = UInt8(Int(originalAlpha) * Int(inkAlpha) / 255)
            pixels[offset + 3] = alpha
            if alpha >= 16 { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    guard let processed = context.makeImage(), let cropped = processed.cropping(to: CGRect(x: minX, y: height - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
    return UIImage(cgImage: cropped).pngData()
}

enum MarkStoreError: LocalizedError {
    case invalidImage, limitReached, missing
    var errorDescription: String? {
        switch self {
        case .invalidImage: String(localized: "The selected signature or stamp has no usable ink.")
        case .limitReached: String(localized: "You can save up to 12 signatures and stamps.")
        case .missing: String(localized: "The saved signature or stamp is missing.")
        }
    }
}
