import Foundation
import ImageIO
import UniformTypeIdentifiers
import Photos

actor RecentRepository {
    private let root: URL
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.root = base
            .appendingPathComponent(StorageLayout.appDirectory, isDirectory: true)
            .appendingPathComponent(StorageLayout.recentDirectory, isDirectory: true)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: root.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; var mutableRoot = root; try? mutableRoot.setResourceValues(values)
    }

    func createDocument(from images: [URL], name: String = AppConfiguration.productName) throws -> ScanDocument {
        guard !images.isEmpty, images.count <= AppConfiguration.maximumScanPages else { throw StorageError.invalidPageCount }
        try prepare()
        let destinations = DestinationPreferences()
        let document = ScanDocument(
            id: UUID(),
            createdAt: Date(),
            pages: [],
            exportSettings: ExportSettings(pdfBaseName: name, pdfFolderBookmark: destinations.pdfBookmark, imageBaseName: name, imageFolderBookmark: destinations.imageBookmark),
            trackedOutputs: []
        )
        let directory = root.appendingPathComponent(document.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: directory) } }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(StorageLayout.originalsDirectory), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(StorageLayout.revisionsDirectory), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(StorageLayout.thumbnailsDirectory), withIntermediateDirectories: true)
        var result = document
        result.pages = try images.enumerated().map { index, input in
            let values = try input.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0, Int64(size) <= AppConfiguration.maximumSourcePageBytes else { throw StorageError.sourceTooLarge }
            let id = UUID()
            let filename = StorageLayout.originalPageFilename(index: index, extension: imageExtension(for: input))
            let rel = RelativeFileReference("\(StorageLayout.originalsDirectory)/\(filename)")
            let dest = rel.resolving(in: directory); try FileManager.default.copyItem(at: input, to: dest)
            try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: dest.path)
            let thumbnail = StorageLayout.thumbnailReference(index: index); if let source = CGImageSourceCreateWithURL(dest as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let writer = CGImageDestinationCreateWithURL(thumbnail.resolving(in: directory) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) { CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary); if CGImageDestinationFinalize(writer) { try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: thumbnail.resolving(in: directory).path) } }
            let revision = PageRevision(id: UUID(), source: rel, editState: PageEditState(), parentRevisionID: nil, isRedacted: false)
            return ScanPage(id: id, source: rel, activeRevisionID: revision.id, revisions: [revision], thumbnail: thumbnail, analysis: nil)
        }
        try writeManifest(result, in: directory)
        try evictIfNeeded(except: document.id)
        published = true
        return result
    }

    func load(_ id: UUID) throws -> ScanDocument { let dir = root.appendingPathComponent(id.uuidString); let data = try Data(contentsOf: dir.appendingPathComponent(StorageLayout.manifestFilename)); return try decoder.decode(ScanDocument.self, from: data) }
    func list() -> [ScanDocument] { guard (try? prepare()) != nil else { return [] }; return (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?.compactMap { try? loadSync($0) }.sorted { $0.createdAt > $1.createdAt } ?? [] }
    func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func update(_ document: ScanDocument) throws { try writeManifest(document, in: directory(for: document.id)) }

    func refreshingOutputStates(_ input: ScanDocument) -> ScanDocument {
        var document = input
        for i in document.trackedOutputs.indices {
            let output = document.trackedOutputs[i]
            if let bookmark = output.bookmark {
                var stale = false
                let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
                let exists = url.map { resolved -> Bool in
                    let scoped = resolved.startAccessingSecurityScopedResource()
                    defer { if scoped { resolved.stopAccessingSecurityScopedResource() } }
                    return FileManager.default.fileExists(atPath: resolved.path)
                } ?? false
                document.trackedOutputs[i].state = (!stale && exists) ? .saved : .missing
            } else if let identifier = output.photosAssetIdentifier {
                document.trackedOutputs[i].state = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).count == 1 ? .saved : .missing
            }
        }
        return document
    }

    private func writeManifest(_ document: ScanDocument, in directory: URL) throws {
        let data = try encoder.encode(document); let temp = directory.appendingPathComponent(StorageLayout.temporaryManifestFilename); let manifest = directory.appendingPathComponent(StorageLayout.manifestFilename); try data.write(to: temp, options: .atomic); if FileManager.default.fileExists(atPath: manifest.path) { _ = try FileManager.default.replaceItemAt(manifest, withItemAt: temp) } else { try FileManager.default.moveItem(at: temp, to: manifest) }
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: manifest.path)
    }
    private func loadSync(_ directory: URL) throws -> ScanDocument { try decoder.decode(ScanDocument.self, from: Data(contentsOf: directory.appendingPathComponent(StorageLayout.manifestFilename))) }
    private func evictIfNeeded(except id: UUID) throws {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]))?.compactMap { url -> (URL, Date)? in guard let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return nil }; return (url, date) }.sorted { $0.1 < $1.1 } ?? []
        var keep = entries
        while keep.count > AppConfiguration.maximumRecentDocuments {
            guard let index = keep.firstIndex(where: { $0.0.lastPathComponent != id.uuidString }) else { break }
            let candidate = keep.remove(at: index)
            try? FileManager.default.removeItem(at: candidate.0)
        }
    }

    private func imageExtension(for url: URL) -> String {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension { return ext }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? FileExtension.jpeg : ext
    }
}

enum StorageError: LocalizedError { case invalidPageCount, sourceTooLarge, unavailable, corrupt
    var errorDescription: String? { switch self { case .invalidPageCount: String(localized: "A scan must contain between 1 and 20 pages."); case .sourceTooLarge: String(localized: "A source page is too large to process safely."); case .unavailable: String(localized: "Recent scans are unavailable."); case .corrupt: String(localized: "This scan is incomplete and was skipped.") } }
}
