import SwiftUI

struct DocumentActionsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let pageIndex: Int
    @State private var showText = false
    @State private var showRedaction = false
    @State private var showManualCleanup = false
    @State private var showEdit = false
    @State private var showPageOrganizer = false
    @State private var cleaning = false
    @State private var speech = ReadAllPagesService()

    var body: some View {
        NavigationStack {
            List {
                Section("Text") {
                    Button { showText = true } label: { Label("Extract all text", systemImage: "text.viewfinder") }
                    Button { speech.read(pageTexts, language: .automatic) } label: { Label("Read all pages", systemImage: "speaker.wave.2") }.disabled(pageTexts.allSatisfy(\.isEmpty))
                }
                Section("Codes on this page") {
                    if currentBarcodes.isEmpty { Text("No QR codes or barcodes found").foregroundStyle(.secondary) }
                    ForEach(currentBarcodes) { barcode in
                        Button { ClipboardService.copySensitive(barcode.payload) } label: { VStack(alignment: .leading) { Text(barcode.symbology); Text(barcode.payload).font(.caption).lineLimit(2).foregroundStyle(.secondary) } }
                    }
                }
                Section("Editing") {
                    if (state.document?.pages.count ?? 0) > 1 {
                        Button { showPageOrganizer = true } label: { Label("Reorder pages", systemImage: "rectangle.stack") }
                            .accessibilityIdentifier(AutomationIdentifier.Actions.reorderPages)
                    }
                    Button { showEdit = true } label: { Label("Edit page", systemImage: "slider.horizontal.3") }
                    Button { applySmartCleanup() } label: {
                        Label(
                            cleaning ? String(localized: "Cleaning…") : String(localized: "Smart cleanup"),
                            systemImage: "wand.and.stars"
                        )
                    }
                    .disabled(cleaning)
                    Button { showManualCleanup = true } label: { Label("Manual cleanup", systemImage: "eraser") }
                    Button { showRedaction = true } label: { Label("Secure redaction", systemImage: "rectangle.fill") }
                }
            }
            .navigationTitle("Actions")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { speech.stop(); dismiss() }.accessibilityIdentifier(AutomationIdentifier.Actions.done) } }
            .sheet(isPresented: $showText) { ExtractedTextView(text: pageTexts.joined(separator: "\n\n")) }
            .fullScreenCover(isPresented: $showRedaction) { RedactionEditorView(pageIndex: pageIndex).environmentObject(state) }
            .fullScreenCover(isPresented: $showManualCleanup) { ManualCleanupEditorView(pageIndex: pageIndex).environmentObject(state) }
            .sheet(isPresented: $showEdit) { PageEditView(pageIndex: pageIndex).environmentObject(state) }
            .sheet(isPresented: $showPageOrganizer) { PageOrganizerView().environmentObject(state) }
        }
    }

    private var pageTexts: [String] { state.document?.pages.map { $0.analysis?.tokens.map(\.text).joined(separator: "\n") ?? "" } ?? [] }
    private var currentBarcodes: [RecognizedBarcode] { guard let pages = state.document?.pages, pages.indices.contains(pageIndex) else { return [] }; return pages[pageIndex].analysis?.barcodes ?? [] }

    private func applySmartCleanup() {
        cleaning = true
        Task {
            guard var document = state.document else { cleaning = false; return }
            do { try await CleanupRevisionService().applySmart(to: &document, pageIndex: pageIndex, repository: state.repository); state.document = document; dismiss() }
            catch { state.errorMessage = error.localizedDescription }
            cleaning = false
        }
    }
}

struct ExtractedTextView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    var body: some View { NavigationStack { ScrollView { Text(text.isEmpty ? "No text found" : text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding() }.navigationTitle("Extracted Text").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Copy") { ClipboardService.copySensitive(text) }.disabled(text.isEmpty) } } } }
}
