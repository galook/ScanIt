import Foundation
import CoreGraphics

struct RelativeFileReference: Codable, Hashable, Sendable {
    let path: String
    init(_ path: String) { self.path = path }
    func resolving(in directory: URL) -> URL { directory.appendingPathComponent(path) }
}

enum PageFilter: String, Codable, Hashable, Sendable, CaseIterable { case original, auto, color, grayscale, blackWhite, shadows }

struct NormalizedQuad: Codable, Hashable, Sendable {
    var topLeft: CGPoint; var topRight: CGPoint; var bottomRight: CGPoint; var bottomLeft: CGPoint
}

struct ImageAdjustments: Codable, Hashable, Sendable {
    var brightness: Double = 0; var contrast: Double = 1; var saturation: Double = 1
}

enum AnnotationKind: String, Codable, Hashable, Sendable { case signature, stamp }
struct PageAnnotation: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var kind: AnnotationKind
    var asset: RelativeFileReference
    var center: CGPoint
    var scale: CGFloat
    var rotation: CGFloat
}

struct RedactionStroke: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var points: [CGPoint]
    var width: CGFloat
    var line: Bool
}

struct PageEditState: Codable, Hashable, Sendable {
    var crop: NormalizedQuad?
    var rotation: Double = 0
    var filter: PageFilter = .original
    var adjustments = ImageAdjustments()
    var annotations: [PageAnnotation] = []
    var redactions: [RedactionStroke] = []
}

struct RecognizedToken: Codable, Identifiable, Sendable {
    let id: UUID; let text: String; let bounds: CGRect; let confidence: Float
}
struct RecognizedBarcode: Codable, Identifiable, Sendable {
    let id: UUID; let payload: String; let symbology: String; let bounds: CGRect
}
struct PageAnalysis: Codable, Sendable {
    var tokens: [RecognizedToken] = []; var barcodes: [RecognizedBarcode] = []
    var lineAngles: [Double] = []; var analyzedAt = Date()
    var visualComplexity: Double? = nil
    var mostlyGrayscale: Bool? = nil
    var smallestTextHeight: Double? = nil
}

struct PageRevision: Codable, Hashable, Identifiable, Sendable {
    let id: UUID; let source: RelativeFileReference; var editState: PageEditState
    var parentRevisionID: UUID?; var isRedacted: Bool
}
struct ScanPage: Codable, Identifiable, Sendable {
    let id: UUID; var source: RelativeFileReference; var activeRevisionID: UUID
    var revisions: [PageRevision]; var thumbnail: RelativeFileReference; var analysis: PageAnalysis?
}

extension ScanPage {
    var activeRevision: PageRevision? {
        revisions.first { $0.id == activeRevisionID }
    }
}

enum PDFSizeTarget: Codable, Hashable, Sendable {
    case original, kb200, kb500, mb1, mb5, mb10, mb20, custom(kilobytes: Int)
    private enum Wire {
        static let original = "original"
        static let kb200 = "200_kb"
        static let kb500 = "500_kb"
        static let mb1 = "1_mb"
        static let mb5 = "5_mb"
        static let mb10 = "10_mb"
        static let mb20 = "20_mb"
        static let custom = "custom"
        static let kilobytes = "kb"
        static let megabytes = "mb"
    }
    var maxBytes: Int64? { switch self { case .original: nil; case .kb200: 200_000; case .kb500: 500_000; case .mb1: 1_000_000; case .mb5: 5_000_000; case .mb10: 10_000_000; case .mb20: 20_000_000; case .custom(let kb): Int64(kb) * 1_000 } }
    var wireValue: String { switch self { case .original: Wire.original; case .kb200: Wire.kb200; case .kb500: Wire.kb500; case .mb1: Wire.mb1; case .mb5: Wire.mb5; case .mb10: Wire.mb10; case .mb20: Wire.mb20; case .custom(let kb): "\(Wire.custom)_\(kb)_\(Wire.kilobytes)" } }
    static func decode(_ value: String?) -> PDFSizeTarget {
        guard let value else { return .original }
        switch value { case Wire.kb200: return .kb200; case Wire.kb500: return .kb500; case Wire.mb1: return .mb1; case Wire.mb5: return .mb5; case Wire.mb10: return .mb10; case Wire.mb20: return .mb20; default: let parts = value.split(separator: "_"); if parts.count == 3, parts[0] == Wire.custom, let amount = Int(parts[1]) { if parts[2] == Wire.kilobytes, (1...500_000).contains(amount) { return .custom(kilobytes: amount) }; if parts[2] == Wire.megabytes, (1...500).contains(amount) { return .custom(kilobytes: amount * 1_000) } }; return .original }
    }
}

enum ImageExportFormat: String, Codable, Sendable { case original, jpeg, png }
enum ImageSizePreset: Codable, Hashable, Sendable { case original, high, balanced, small, custom(maxDimension: Int)
    var maxDimension: Int? { switch self { case .original: nil; case .high: 3840; case .balanced: 2560; case .small: 1600; case .custom(let value): value } }
}
struct ExportSettings: Codable, Sendable {
    var pdfTarget: PDFSizeTarget = .original; var pdfBaseName = AppConfiguration.productName; var pdfFolderBookmark: Data?
    var imageFormat: ImageExportFormat = .jpeg; var imageSize: ImageSizePreset = .high; var imageBaseName = AppConfiguration.productName; var imageFolderBookmark: Data?
}
enum TrackedOutputKind: String, Codable, Sendable { case pdf, image }
struct TrackedOutput: Codable, Identifiable, Sendable {
    let id: UUID; var kind: TrackedOutputKind; var filename: String; var bookmark: Data?; var photosAssetIdentifier: String?; var byteCount: Int64; var state: OutputState
    enum OutputState: String, Codable, Hashable, Sendable { case saved, missing }
}
struct ScanDocument: Codable, Identifiable, Sendable {
    let id: UUID; var createdAt: Date; var pages: [ScanPage]; var exportSettings: ExportSettings; var trackedOutputs: [TrackedOutput]
    var directoryName: String { id.uuidString }
}
