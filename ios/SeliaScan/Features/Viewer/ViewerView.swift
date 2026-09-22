import SwiftUI

struct ViewerView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let doc = state.document {
                    TabView(selection: $state.selectedPageIndex) {
                        ForEach(Array(doc.pages.enumerated()), id: \.element.id) { i, page in
                            PagePreview(page: page, document: doc, repository: state.repository, allowsZoom: true).tag(i)
                        }
                    }
                    .tabViewStyle(.page)
                    .overlay(alignment: .bottom) {
                        Text("Page \(state.selectedPageIndex + 1) of \(doc.pages.count)")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.bottom, 12)
                            .accessibilityIdentifier(AutomationIdentifier.Viewer.pageIndicator)
                            .accessibilityValue("\(state.selectedPageIndex + 1)/\(doc.pages.count)")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { state.route = .result }
                        .foregroundStyle(.white)
                        .accessibilityIdentifier(AutomationIdentifier.Viewer.done)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .statusBarHidden(true)
    }
}
