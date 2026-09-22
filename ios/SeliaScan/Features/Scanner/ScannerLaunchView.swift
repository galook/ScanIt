import SwiftUI

struct ScannerLaunchView: View {
    @EnvironmentObject private var state: AppState
    @State private var started = false
    var body: some View { ZStack { Color(.systemBackground).ignoresSafeArea(); ProgressView("Opening scanner…") }.task { guard !started else { return }; started = true; state.startScan() } }
}
struct FallbackView: View {
    @EnvironmentObject private var state: AppState
    @State private var showPhotos = false; @State private var showFiles = false
    var body: some View { NavigationStack { VStack(spacing: 16) { Image(systemName: SystemImageName.scanDocument).font(.system(size: 48)); Text("Ready to scan").font(.title2); Button("New Scan", action: state.startScan).buttonStyle(.borderedProminent); Menu("Import") { Button("Photos") { showPhotos = true }; Button("Files") { showFiles = true } }.buttonStyle(.bordered); HStack { Button("Recent", action: state.showRecent); Button("Settings") { state.route = .settings } }.buttonStyle(.bordered) }.padding().navigationTitle(AppConfiguration.productName) }.sheet(isPresented: $showPhotos) { ImportDocumentView { state.importDocuments($0) } }.sheet(isPresented: $showFiles) { FilesImportView { state.importDocuments($0) } } }
}
