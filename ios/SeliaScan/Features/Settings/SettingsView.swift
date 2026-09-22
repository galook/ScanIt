import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(UserDefaultsKey.protectRecent) private var protectRecent = false
    @AppStorage(UserDefaultsKey.shareSubject) private var shareSubject = AppConfiguration.defaultShareSubject
    @State private var pdfFolderBookmark: Data?
    @State private var imageFolderBookmark: Data?
    @State private var showPDFFolderPicker = false
    @State private var showImageFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Text(AppConfiguration.productName)
                    Text("Scan → save → share").foregroundStyle(.secondary)
                }
                Section("Saving") {
                    destinationRow("Default PDF Folder", bookmark: pdfFolderBookmark, choose: { showPDFFolderPicker = true }, clear: { setFolder(nil, pdf: true) })
                    destinationRow("Default Image Folder", bookmark: imageFolderBookmark, choose: { showImageFolderPicker = true }, clear: { setFolder(nil, pdf: false) })
                    Text("Each scan can override these folders in File Details.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Toggle("Protect Recent Scans", isOn: $protectRecent)
                        .onChange(of: protectRecent) { _, enabled in if enabled { authenticate() } }
                }
                Section("Scanning") { Text("Pages are processed on-device") }
                Section("Sharing") { TextField("Email subject", text: $shareSubject) }
                Section("Advanced") { Text("OCR: English, Czech, German, Spanish, Simplified Chinese") }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { state.route = .fallback } } }
            .sheet(isPresented: $showPDFFolderPicker) { FolderPicker { selectFolder($0, pdf: true) } }
            .sheet(isPresented: $showImageFolderPicker) { FolderPicker { selectFolder($0, pdf: false) } }
            .onAppear {
                let preferences = DestinationPreferences()
                pdfFolderBookmark = preferences.pdfBookmark
                imageFolderBookmark = preferences.imageBookmark
            }
        }
    }

    @ViewBuilder private func destinationRow(_ title: LocalizedStringKey, bookmark: Data?, choose: @escaping () -> Void, clear: @escaping () -> Void) -> some View {
        LabeledContent(title, value: folderName(bookmark) ?? String(localized: "Ask Every Time"))
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
        do { setFolder(try ExternalOutputStore().folderBookmark(for: url), pdf: pdf) }
        catch { state.errorMessage = error.localizedDescription }
    }

    private func setFolder(_ bookmark: Data?, pdf: Bool) {
        let preferences = DestinationPreferences()
        if pdf { preferences.pdfBookmark = bookmark; pdfFolderBookmark = bookmark }
        else { preferences.imageBookmark = bookmark; imageFolderBookmark = bookmark }
    }

    private func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Protect Recent Scans") { success, _ in
            if !success { Task { @MainActor in protectRecent = false } }
        }
    }
}
