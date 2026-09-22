import SwiftUI

private enum PDFTargetSelection: CaseIterable, Identifiable {
    case original, kb200, kb500, mb1, mb5, mb10, mb20, custom

    var id: Self { self }
    var label: LocalizedStringKey {
        switch self {
        case .original: "Original"
        case .kb200: "200 KB"
        case .kb500: "500 KB"
        case .mb1: "1 MB"
        case .mb5: "5 MB"
        case .mb10: "10 MB"
        case .mb20: "20 MB"
        case .custom: "Custom"
        }
    }

    init(_ target: PDFSizeTarget) {
        switch target {
        case .original: self = .original
        case .kb200: self = .kb200
        case .kb500: self = .kb500
        case .mb1: self = .mb1
        case .mb5: self = .mb5
        case .mb10: self = .mb10
        case .mb20: self = .mb20
        case .custom: self = .custom
        }
    }

    var target: PDFSizeTarget? {
        switch self {
        case .original: .original
        case .kb200: .kb200
        case .kb500: .kb500
        case .mb1: .mb1
        case .mb5: .mb5
        case .mb10: .mb10
        case .mb20: .mb20
        case .custom: nil
        }
    }
}

struct ExportSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pdfName = AppConfiguration.productName
    @State private var targetSelection = PDFTargetSelection.original
    @State private var customKilobytes = "1000"
    @State private var imageFormat = ImageExportFormat.jpeg
    @State private var imageSize = ImageSizePreset.high
    @State private var pdfFolderBookmark: Data?
    @State private var imageFolderBookmark: Data?
    @State private var showPDFFolderPicker = false
    @State private var showImageFolderPicker = false
    @State private var deleteOutput: TrackedOutput?

    var body: some View {
        NavigationStack {
            Form {
                Section("PDF") {
                    TextField("File name", text: $pdfName)
                    Picker("Target size", selection: $targetSelection) { ForEach(PDFTargetSelection.allCases) { Text($0.label).tag($0) } }
                    if targetSelection == .custom { TextField("Kilobytes", text: $customKilobytes).keyboardType(.numberPad) }
                    Text("Searchable text is included when OCR succeeds.").font(.footnote).foregroundStyle(.secondary)
                    destinationRow(bookmark: pdfFolderBookmark, choose: { showPDFFolderPicker = true }, clear: { pdfFolderBookmark = nil })
                }
                Section("Images") {
                    Picker("Format", selection: $imageFormat) { Text("Original").tag(ImageExportFormat.original); Text("JPEG").tag(ImageExportFormat.jpeg); Text("PNG").tag(ImageExportFormat.png) }
                    Picker("Size", selection: $imageSize) { Text("Original").tag(ImageSizePreset.original); Text("High").tag(ImageSizePreset.high); Text("Balanced").tag(ImageSizePreset.balanced); Text("Small").tag(ImageSizePreset.small) }
                    destinationRow(bookmark: imageFolderBookmark, choose: { showImageFolderPicker = true }, clear: { imageFolderBookmark = nil })
                }
                if let outputs = state.document?.trackedOutputs, !outputs.isEmpty {
                    Section("Saved outputs") {
                        ForEach(outputs) { output in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(output.filename).lineLimit(1)
                                    if output.state == .saved { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                                    else { Text("Deleted or missing").font(.caption).foregroundStyle(.red) }
                                }
                                Spacer()
                                if output.state == .saved { Button(role: .destructive) { deleteOutput = output } label: { Image(systemName: "trash") }.accessibilityLabel("Delete exact saved output") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("File Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AutomationIdentifier.FileDetails.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier(AutomationIdentifier.FileDetails.save)
                }
            }
            .onAppear { guard let settings = state.document?.exportSettings else { return }; pdfName = settings.pdfBaseName; targetSelection = PDFTargetSelection(settings.pdfTarget); imageFormat = settings.imageFormat; imageSize = settings.imageSize; pdfFolderBookmark = settings.pdfFolderBookmark; imageFolderBookmark = settings.imageFolderBookmark }
            .sheet(isPresented: $showPDFFolderPicker) { FolderPicker { selectFolder($0, pdf: true) } }
            .sheet(isPresented: $showImageFolderPicker) { FolderPicker { selectFolder($0, pdf: false) } }
            .confirmationDialog("Delete this exact saved output?", isPresented: Binding(get: { deleteOutput != nil }, set: { if !$0 { deleteOutput = nil } }), titleVisibility: .visible) { Button("Delete", role: .destructive) { performDelete() }; Button("Cancel", role: .cancel) { deleteOutput = nil } }
        }
    }

    @ViewBuilder private func destinationRow(bookmark: Data?, choose: @escaping () -> Void, clear: @escaping () -> Void) -> some View {
        LabeledContent("Automatic Folder", value: folderName(bookmark) ?? String(localized: "Ask Every Time"))
        Button("Choose Folder", action: choose)
        if bookmark != nil { Button("Clear Folder", role: .destructive, action: clear) }
    }

    private func folderName(_ bookmark: Data?) -> String? {
        guard let bookmark, let url = try? ExternalOutputStore().resolve(bookmark) else { return nil }
        return url.lastPathComponent
    }

    private func selectFolder(_ result: Result<URL, Error>, pdf: Bool) {
        guard case .success(let url) = result else { if case .failure(let error) = result { state.errorMessage = error.localizedDescription }; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try ExternalOutputStore().folderBookmark(for: url)
            if pdf { pdfFolderBookmark = bookmark } else { imageFolderBookmark = bookmark }
        } catch { state.errorMessage = error.localizedDescription }
    }

    private func save() {
        Task {
            guard var document = state.document else { return }
            let normalized = pdfName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(96)
            document.exportSettings.pdfBaseName = normalized.isEmpty ? AppConfiguration.productName : String(normalized)
            document.exportSettings.pdfTarget = targetSelection.target ?? .custom(kilobytes: min(500_000, max(1, Int(customKilobytes) ?? 1_000)))
            document.exportSettings.imageFormat = imageFormat
            document.exportSettings.imageSize = imageSize
            document.exportSettings.pdfFolderBookmark = pdfFolderBookmark
            document.exportSettings.imageFolderBookmark = imageFolderBookmark
            do { try await state.repository.update(document); state.document = document; dismiss() }
            catch { state.errorMessage = error.localizedDescription }
        }
    }

    private func performDelete() {
        guard let output = deleteOutput else { return }
        deleteOutput = nil
        Task {
            do {
                try await TrackedOutputDeletionService().delete(output)
                guard var document = state.document, let index = document.trackedOutputs.firstIndex(where: { $0.id == output.id }) else { return }
                document.trackedOutputs[index].state = .missing
                try await state.repository.update(document)
                state.document = document
            } catch { state.errorMessage = error.localizedDescription }
        }
    }
}
