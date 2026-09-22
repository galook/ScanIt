import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var privacyCovered = false
    var body: some View {
        Group {
            switch state.route {
            case .scanner: ScannerLaunchView()
            case .fallback: FallbackView()
            case .result: ResultView()
            case .recent: RecentView()
            case .settings: SettingsView()
            case .viewer: ViewerView()
            }
        }
        .alert(AppConfiguration.productName, isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.dismissError() } })) { Button("OK", role: .cancel) {} } message: { Text(state.errorMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in privacyCovered = phase != .active; if phase == .active { state.consumePendingIntent() } }
        .overlay { if privacyCovered { Color(.systemBackground).ignoresSafeArea().overlay { Image(systemName: "lock.fill").font(.largeTitle) } } }
    }
}
