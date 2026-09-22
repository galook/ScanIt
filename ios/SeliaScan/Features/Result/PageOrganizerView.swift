import SwiftUI

struct PageOrganizerView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [ScanPage] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    HStack(spacing: 12) {
                        PageThumbnail(page: page)
                            .frame(width: 54, height: 72)
                        Text("Page \(index + 1)")
                    }
                    .accessibilityLabel("Page \(index + 1)")
                }
                .onMove(perform: move)
            }
            .accessibilityIdentifier(AutomationIdentifier.Organizer.list)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Pages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier(AutomationIdentifier.Organizer.done) } }
            .onAppear { pages = state.document?.pages ?? [] }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
        guard var document = state.document else { return }
        document.pages = pages
        state.document = document
        Task {
            do { try await state.repository.update(document) }
            catch { state.errorMessage = error.localizedDescription }
        }
    }
}

private struct PageThumbnail: View {
    @EnvironmentObject private var state: AppState
    let page: ScanPage
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView() }
        }
        .task(id: page.activeRevision) {
            guard let document = state.document else { return }
            let directory = await state.repository.directory(for: document.id)
            guard let rendered = try? await PageRenderer.shared.renderOffMain(page: page, documentDirectory: directory, maximumPixelSize: 320),
                  !Task.isCancelled else { return }
            image = UIImage(cgImage: rendered)
        }
    }
}
