import Foundation

struct ExternalOutputStore {
    func bookmark(for url: URL) throws -> Data { try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: [.fileSizeKey, .contentModificationDateKey], relativeTo: nil) }
    func folderBookmark(for url: URL) throws -> Data { try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: [.isDirectoryKey, .nameKey], relativeTo: nil) }
    func resolve(_ bookmark: Data) throws -> URL { var stale = false; let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale); guard !stale else { throw OutputError.stalePermission }; return url }
    func withAccess<T>(to bookmark: Data, operation: (URL) throws -> T) throws -> T { let url = try resolve(bookmark); guard url.startAccessingSecurityScopedResource() else { throw OutputError.permissionDenied }; defer { url.stopAccessingSecurityScopedResource() }; return try operation(url) }
    func deleteExact(_ output: TrackedOutput) throws { guard let bookmark = output.bookmark else { throw OutputError.missingIdentity }; try withAccess(to: bookmark) { url in guard FileManager.default.fileExists(atPath: url.path) else { throw OutputError.missing }; try FileManager.default.removeItem(at: url) } }
    func copy(_ source: URL, toFolder bookmark: Data) throws -> URL {
        try withAccess(to: bookmark) { folder in
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw OutputError.missing }
            let destination = availableDestination(in: folder, filename: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
    }
    func copyAndBookmark(_ source: URL, toFolder bookmark: Data) throws -> (url: URL, bookmark: Data) {
        try withAccess(to: bookmark) { folder in
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw OutputError.missing }
            let destination = availableDestination(in: folder, filename: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            do { return (destination, try self.bookmark(for: destination)) }
            catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
    }

    private func availableDestination(in folder: URL, filename: String) -> URL {
        let safeName = FilenameSanitizer.sanitize(filename)
        var candidate = folder.appendingPathComponent(safeName)
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = folder.appendingPathComponent(name)
            suffix += 1
        }
        return candidate
    }
}
enum OutputError: LocalizedError { case stalePermission, permissionDenied, missingIdentity, missing
    var errorDescription: String? { switch self { case .stalePermission: String(localized: "The saved folder permission expired. Choose the folder again."); case .permissionDenied: String(localized: "FruitySelia no longer has access to this location."); case .missingIdentity: String(localized: "The exact saved file could not be identified."); case .missing: String(localized: "The saved file was moved or deleted.") } }
}

struct DestinationPreferences {
    private let defaults: UserDefaults
    private static let pdfKey = UserDefaultsKey.defaultPDFFolderBookmark
    private static let imageKey = UserDefaultsKey.defaultImageFolderBookmark
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var pdfBookmark: Data? { get { defaults.data(forKey: Self.pdfKey) } nonmutating set { defaults.set(newValue, forKey: Self.pdfKey) } }
    var imageBookmark: Data? { get { defaults.data(forKey: Self.imageKey) } nonmutating set { defaults.set(newValue, forKey: Self.imageKey) } }
}
