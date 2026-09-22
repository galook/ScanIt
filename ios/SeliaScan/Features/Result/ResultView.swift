import SwiftUI
import UIKit

struct ResultView: View {
    @EnvironmentObject private var state: AppState
    @State private var showActions = false
    @State private var showSignature = false
    @State private var showDetails = false
    @State private var exporting = false
    @State private var exportMessage: String?
    @State private var fileExport: FileExportRequest?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let document = state.document {
                    TabView(selection: $state.selectedPageIndex) {
                        ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                            PagePreview(page: page, document: document, repository: state.repository, allowsZoom: false).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .overlay(alignment: .topTrailing) {
                        Button { state.route = .viewer } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Open full-screen viewer")
                        .accessibilityIdentifier(AutomationIdentifier.Result.openViewer)
                        .padding(8)
                    }
                    Text("Page \(state.selectedPageIndex + 1) of \(document.pages.count)")
                        .font(.footnote)
                        .accessibilityIdentifier(AutomationIdentifier.Result.pageIndicator)
                        .accessibilityValue("\(state.selectedPageIndex + 1)/\(document.pages.count)")
                    ViewThatFits(in: .horizontal) {
                        actionRow(document)
                            .fixedSize(horizontal: true, vertical: false)
                        actionGrid(document)
                            .fixedSize(horizontal: true, vertical: false)
                        actionColumn(document)
                    }
                } else {
                    ContentUnavailableView("No scan", systemImage: "doc")
                }
            }
            .padding()
            .navigationTitle("Result")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Recent", action: state.showRecent)
                        .accessibilityIdentifier(AutomationIdentifier.Result.recent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDetails = true } label: { Label("File Details", systemImage: "info.circle") }
                        .accessibilityIdentifier(AutomationIdentifier.Result.fileDetails)
                }
            }
            .overlay { if exporting { ZStack { Color.black.opacity(0.2).ignoresSafeArea(); ProgressView("Preparing PDF…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } } }
            .sheet(isPresented: $showActions) { DocumentActionsView(pageIndex: state.selectedPageIndex).environmentObject(state) }
            .sheet(isPresented: $showSignature) { SignatureEditorView(pageIndex: state.selectedPageIndex).environmentObject(state) }
            .sheet(isPresented: $showDetails) { ExportSettingsView().environmentObject(state) }
            .sheet(item: $fileExport) { request in FileExportPicker(urls: request.urls) { result in trackFileExport(result, kind: request.kind); cleanupTemporaryFiles(request.urls) } }
            .alert("Export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(exportMessage ?? "") }
        }
    }

    private func actionRow(_ document: ScanDocument) -> some View {
        HStack {
            rescanButton()
            signButton()
            actionsButton()
            shareMenu(document)
        }
    }

    private func actionGrid(_ document: ScanDocument) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                rescanButton()
                signButton()
            }
            GridRow {
                actionsButton()
                shareMenu(document)
            }
        }
    }

    private func actionColumn(_ document: ScanDocument) -> some View {
        VStack(spacing: 8) {
            rescanButton(expands: true)
            signButton(expands: true)
            actionsButton(expands: true)
            shareMenu(document, expands: true)
        }
    }

    private func rescanButton(expands: Bool = false) -> some View {
        Button { state.startScan() } label: {
            Label("Rescan", systemImage: "camera").frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(.bordered)
    }

    private func signButton(expands: Bool = false) -> some View {
        Button { showSignature = true } label: {
            Label("Sign / Stamp", systemImage: SystemImageName.signature).frame(maxWidth: expands ? .infinity : nil)
        }
        .accessibilityIdentifier(AutomationIdentifier.Result.signStamp)
        .buttonStyle(.bordered)
    }

    private func actionsButton(expands: Bool = false) -> some View {
        Button { showActions = true } label: {
            Label("Actions", systemImage: "ellipsis.circle").frame(maxWidth: expands ? .infinity : nil)
        }
        .accessibilityIdentifier(AutomationIdentifier.Result.actions)
        .buttonStyle(.bordered)
    }

    private func shareMenu(_ document: ScanDocument, expands: Bool = false) -> some View {
        Menu {
            Button("Share PDF") { exportPDFAndShare(document) }
            Button("Share Images") { exportImagesAndShare(document) }
            Button("Share PDF + Images") { exportCombined(document) }
            Divider()
            Button("Save PDF to Files") { savePDFToFiles(document) }
            Button("Save Images to Files") { saveImagesToFiles(document) }
            Button("Save Images to Photos") { saveImagesToPhotos(document) }
            Button("Print") { exportAndPrint(document) }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: expands ? .infinity : nil)
        }
        .accessibilityIdentifier(AutomationIdentifier.Result.share)
        .buttonStyle(.borderedProminent)
        .disabled(exporting)
    }

    private func exportPDFAndShare(_ document: ScanDocument) {
        exporting = true
        Task {
            do {
                let result = try await preparePDF(document)
                exporting = false
                presentShareSheet(url: result.url, subject: document.exportSettings.pdfBaseName)
            } catch { exporting = false; state.errorMessage = error.localizedDescription }
        }
    }

    private func exportImagesAndShare(_ document: ScanDocument) {
        exporting = true
        Task { do { let urls = try await prepareImages(document); exporting = false; presentShareSheet(urls: urls, subject: document.exportSettings.imageBaseName) } catch { exporting = false; state.errorMessage = error.localizedDescription } }
    }

    private func exportCombined(_ document: ScanDocument) {
        exporting = true
        Task { do { let pdf = try await preparePDF(document); let images = try await prepareImages(document); exporting = false; presentShareSheet(urls: [pdf.url] + images, subject: document.exportSettings.pdfBaseName) } catch { exporting = false; state.errorMessage = error.localizedDescription } }
    }

    private func saveImagesToPhotos(_ document: ScanDocument) {
        exporting = true
        Task { do { let urls = try await prepareImages(document); defer { cleanupTemporaryFiles(urls) }; let result = try await PhotosSaver().save(imagesAt: urls); var updated = document; for (index, identifier) in result.identifiers.enumerated() { let bytes = urls.indices.contains(index) ? Int64((try? urls[index].resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) : 0; updated.trackedOutputs.append(TrackedOutput(id: UUID(), kind: .image, filename: urls.indices.contains(index) ? urls[index].lastPathComponent : String(localized: "Image"), bookmark: nil, photosAssetIdentifier: identifier, byteCount: bytes, state: .saved)) }; try await state.repository.update(updated); state.document = updated; exporting = false; exportMessage = String(localized: "Saved \(result.identifiers.count) image(s) to Photos.") } catch { exporting = false; state.errorMessage = error.localizedDescription } }
    }

    private func exportAndPrint(_ document: ScanDocument) {
        exporting = true
        Task { do { let result = try await preparePDF(document); exporting = false; printPDF(at: result.url) } catch { exporting = false; state.errorMessage = error.localizedDescription } }
    }

    private func preparePDF(_ document: ScanDocument) async throws -> PDFExportResult {
        let safeName = FilenameSanitizer.sanitize(document.exportSettings.pdfBaseName)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).\(FileExtension.pdf)")
        let result = try await SearchablePDFExporter().export(document: document, repository: state.repository, targetURL: url)
        if !result.targetMet { exportMessage = String(localized: "Readable PDF is \(ByteCountFormatter.string(fromByteCount: result.byteCount, countStyle: .file)); selected target could not be met.") }
        return result
    }

    private func prepareImages(_ document: ScanDocument) async throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(TemporaryFile.imageExportDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        return try await ImageExporter().export(document: document, repository: state.repository, outputDirectory: directory)
    }

    private func savePDFToFiles(_ document: ScanDocument) {
        exporting = true
        Task {
            do {
                let result = try await preparePDF(document)
                if let folder = document.exportSettings.pdfFolderBookmark {
                    defer { cleanupTemporaryFiles([result.url]) }
                    let output = try ExternalOutputStore().copyAndBookmark(result.url, toFolder: folder)
                    try await trackDirectOutputs([output], kind: .pdf)
                    exportMessage = String(localized: "Saved PDF to \(output.url.lastPathComponent).")
                } else {
                    fileExport = FileExportRequest(urls: [result.url], kind: .pdf)
                }
                exporting = false
            } catch { exporting = false; state.errorMessage = error.localizedDescription }
        }
    }

    private func saveImagesToFiles(_ document: ScanDocument) {
        exporting = true
        Task {
            do {
                let urls = try await prepareImages(document)
                if let folder = document.exportSettings.imageFolderBookmark {
                    defer { cleanupTemporaryFiles(urls) }
                    var outputs: [(url: URL, bookmark: Data)] = []
                    do {
                        for url in urls {
                            try Task.checkCancellation()
                            outputs.append(try ExternalOutputStore().copyAndBookmark(url, toFolder: folder))
                        }
                    } catch {
                        for output in outputs {
                            let tracked = TrackedOutput(id: UUID(), kind: .image, filename: output.url.lastPathComponent, bookmark: output.bookmark, photosAssetIdentifier: nil, byteCount: 0, state: .saved)
                            try? ExternalOutputStore().deleteExact(tracked)
                        }
                        throw error
                    }
                    try await trackDirectOutputs(outputs, kind: .image)
                    exportMessage = String(localized: "Saved \(outputs.count) image(s).")
                } else {
                    fileExport = FileExportRequest(urls: urls, kind: .image)
                }
                exporting = false
            } catch { exporting = false; state.errorMessage = error.localizedDescription }
        }
    }

    private func trackDirectOutputs(_ outputs: [(url: URL, bookmark: Data)], kind: TrackedOutputKind) async throws {
        guard var document = state.document else { return }
        for output in outputs {
            let bytes = Int64((try? output.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            document.trackedOutputs.append(TrackedOutput(id: UUID(), kind: kind, filename: output.url.lastPathComponent, bookmark: output.bookmark, photosAssetIdentifier: nil, byteCount: bytes, state: .saved))
        }
        try await state.repository.update(document)
        state.document = document
    }

    private func trackFileExport(_ result: Result<[URL], Error>, kind: TrackedOutputKind) {
        guard case .success(let urls) = result, !urls.isEmpty else { if case .failure(let error) = result { state.errorMessage = error.localizedDescription }; return }
        Task {
            guard var document = state.document else { return }
            for url in urls {
                let bookmark = try? ExternalOutputStore().bookmark(for: url)
                let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                document.trackedOutputs.append(TrackedOutput(id: UUID(), kind: kind, filename: url.lastPathComponent, bookmark: bookmark, photosAssetIdentifier: nil, byteCount: bytes, state: .saved))
            }
            try? await state.repository.update(document)
            state.document = document
        }
    }
}

private struct FileExportRequest: Identifiable { let id = UUID(); let urls: [URL]; let kind: TrackedOutputKind }

struct PagePreview: View {
    let page: ScanPage
    let document: ScanDocument
    let repository: RecentRepository
    let allowsZoom: Bool
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                LiveTextImageView(image: image, allowsZoom: allowsZoom)
            } else if failed {
                ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
            .task(id: page.activeRevision) {
                image = nil
                failed = false
                let directory = await repository.directory(for: document.id)
                if let rendered = try? await PageRenderer.shared.renderOffMain(page: page, documentDirectory: directory, maximumPixelSize: 1_600) {
                    guard !Task.isCancelled else { return }
                    image = UIImage(cgImage: rendered)
                } else {
                    failed = true
                }
            }
            .accessibilityLabel("Scanned page")
            .accessibilityIdentifier(AutomationIdentifier.Result.pagePreview)
    }
}
