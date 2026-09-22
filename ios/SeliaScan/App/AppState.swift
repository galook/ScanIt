import Foundation
import SwiftUI
import UIKit
import LocalAuthentication

@MainActor final class AppState: ObservableObject {
    @Published var route: Route = .scanner
    @Published var document: ScanDocument?
    @Published var selectedPageIndex = 0
    @Published var recent: [ScanDocument] = []
    @Published var errorMessage: String?
    let repository = RecentRepository(); let scanner: DocumentScanning; let analyzer: DocumentAnalyzing
    private var activeDocumentOperation = UUID()
    private var analysisTask: Task<Void, Never>?
    enum Route: Hashable { case scanner, fallback, result, recent, settings, viewer }
    init(scanner: DocumentScanning? = nil, analyzer: DocumentAnalyzing = VisionDocumentAnalyzer()) { self.scanner = scanner ?? Self.defaultScanner(); self.analyzer = analyzer }
    private static func defaultScanner() -> DocumentScanning {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(LaunchArgument.fixtureScanner), let urls = try? FixtureFactory.makePages() { return FixtureDocumentScanner(urls: urls) }
        #endif
        return VisionKitDocumentScanner()
    }
    func launch() { route = .scanner }
    func startScan() {
        let operation = UUID()
        activeDocumentOperation = operation
        analysisTask?.cancel()
        Task { await performScan(operation: operation) }
    }
    func performScan(operation: UUID? = nil) async {
        let operation = operation ?? activeDocumentOperation
        do { let input = try await scanner.scan(); defer { cleanupDocumentInputs(input.imageURLs) }; try Task.checkCancellation(); guard activeDocumentOperation == operation else { return }; let created = try await repository.createDocument(from: input.imageURLs); guard activeDocumentOperation == operation else { return }; selectedPageIndex = 0; document = created; route = .result; recent = await repository.list(); analyze(created) }
        catch ScannerError.cancelled { if activeDocumentOperation == operation { route = .fallback } }
        catch { if activeDocumentOperation == operation { errorMessage = error.localizedDescription; route = .fallback } }
    }
    func importDocuments(_ urls: [URL]) {
        let operation = UUID()
        activeDocumentOperation = operation
        analysisTask?.cancel()
        Task {
            do {
                var images: [URL] = []
                defer { cleanupDocumentInputs(images) }
                for url in urls.prefix(AppConfiguration.maximumScanPages) {
                    try Task.checkCancellation()
                    guard images.count < AppConfiguration.maximumScanPages else { break }
                    let scoped = url.startAccessingSecurityScopedResource()
                    do {
                        if url.pathExtension.lowercased() == FileExtension.pdf {
                            let remaining = AppConfiguration.maximumScanPages - images.count
                            images.append(contentsOf: try await PDFImportService().renderPages(from: url, limit: remaining))
                        } else {
                            let ext = url.pathExtension.isEmpty ? FileExtension.jpeg : url.pathExtension
                            let copy = TemporaryFile.importURL(extension: ext)
                            images.append(try await Task.detached(priority: .userInitiated) {
                                try Task.checkCancellation()
                                try FileManager.default.copyItem(at: url, to: copy)
                                return copy
                            }.value)
                        }
                    } catch {
                        if scoped { url.stopAccessingSecurityScopedResource() }
                        throw error
                    }
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                guard activeDocumentOperation == operation else { return }
                let created = try await repository.createDocument(from: images)
                guard activeDocumentOperation == operation else { return }
                selectedPageIndex = 0
                document = created
                route = .result
                recent = await repository.list()
                analyze(created)
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func analyze(_ doc: ScanDocument) {
        analysisTask?.cancel()
        analysisTask = Task {
            var updated = doc
            do {
                for index in updated.pages.indices {
                    try Task.checkCancellation()
                    let page = updated.pages[index]
                    let directory = await repository.directory(for: updated.id)
                    if let analysis = try? await analyzer.analyze(pageAt: page.source.resolving(in: directory)) {
                        updated.pages[index].analysis = analysis
                        let characters = analysis.tokens.reduce(0) { $0 + $1.text.count }
                        let correction = conservativeOrientation(from: analysis.lineAngles, readableCharacters: characters)
                        if correction != 0, let revision = updated.pages[index].revisions.firstIndex(where: { $0.id == updated.pages[index].activeRevisionID }) { updated.pages[index].revisions[revision].editState.rotation += Double(correction) }
                    }
                }
                try Task.checkCancellation()
                try await repository.update(updated)
                if document?.id == updated.id { document = updated }
            } catch is CancellationError { }
            catch { if document?.id == updated.id { errorMessage = error.localizedDescription } }
        }
    }
    func openRecent(_ doc: ScanDocument) { activeDocumentOperation = UUID(); analysisTask?.cancel(); Task { let refreshed = await repository.refreshingOutputStates(doc); selectedPageIndex = 0; document = refreshed; try? await repository.update(refreshed); route = .result } }
    func showRecent() {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKey.protectRecent) else { Task { recent = await repository.list(); route = .recent }; return }
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open Recent Scans") { success, error in
            Task { @MainActor in if success { self.recent = await self.repository.list(); self.route = .recent } else { self.errorMessage = error?.localizedDescription ?? "Authentication failed." } }
        }
    }
    func handle(url: URL) {
        if url.isFileURL { importDocuments([url]) }
        else if url.host == AppRouteURL.newScanHost { route = .scanner; startScan() }
    }
    func consumePendingIntent() { guard UserDefaults.standard.bool(forKey: UserDefaultsKey.pendingNewScanIntent) else { return }; UserDefaults.standard.removeObject(forKey: UserDefaultsKey.pendingNewScanIntent); route = .scanner; startScan() }
    func dismissError() { errorMessage = nil }
}

private func cleanupDocumentInputs(_ urls: [URL]) {
    let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
    for url in urls where url.standardizedFileURL.path.hasPrefix(temporary + "/") {
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix(TemporaryFile.scanDirectoryPrefix) {
            try? FileManager.default.removeItem(at: parent)
        } else if url.lastPathComponent.hasPrefix(TemporaryFile.importPrefix) ||
                    url.lastPathComponent.hasPrefix(TemporaryFile.pdfPagePrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

#if DEBUG
private enum FixtureFactory {
    static func makePages() throws -> [URL] {
        try (1...2).map { number in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1_200))
            let image = renderer.image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1_200))
                let title = "\(String(localized: "FruitySelia sample page")) \(number)" as NSString
                title.draw(at: CGPoint(x: 80, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 42, weight: .bold), .foregroundColor: UIColor.black])
                (String(localized: "Private, on-device document scan") as NSString).draw(at: CGPoint(x: 80, y: 180), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black])
            }
            guard let data = image.jpegData(compressionQuality: 0.96) else { throw StorageError.unavailable }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(TemporaryFile.fixturePrefix)\(number)-\(UUID().uuidString).\(FileExtension.jpeg)")
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
#endif
