import SwiftUI

struct RecentView: View {
    @EnvironmentObject private var state: AppState
    var body: some View { NavigationSplitView { List(state.recent) { doc in Button { state.openRecent(doc) } label: { HStack { Image(systemName: "doc.text.image"); VStack(alignment: .leading) { Text(doc.exportSettings.pdfBaseName).lineLimit(1); Text("\(doc.pages.count) pages · \(doc.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) } } }.accessibilityLabel("Open \(doc.exportSettings.pdfBaseName)") } .accessibilityIdentifier(AutomationIdentifier.Recent.list).navigationTitle("Recent").toolbar { ToolbarItem(placement: .topBarLeading) { Button("New Scan", action: state.startScan) }; ToolbarItem(placement: .topBarTrailing) { Button("Settings") { state.route = .settings } } }.task { state.recent = await state.repository.list() } } detail: { Text("Select a scan").foregroundStyle(.secondary) } }
}
