import SwiftUI
import UIKit

struct PageEditView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let pageIndex: Int
    @State private var page: ScanPage?
    @State private var documentID: UUID?
    @State private var draft = PageEditState()
    @State private var undoStack: [PageEditState] = []
    @State private var redoStack: [PageEditState] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let page, let documentID {
                        PageEditPreview(page: page, documentID: documentID, draft: draft, repository: state.repository)
                            .frame(height: 320)
                            .listRowInsets(EdgeInsets())
                    } else {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .frame(height: 240)
                    }
                }
                Section("Appearance") {
                    Picker("Filter", selection: binding(\.filter)) { ForEach(PageFilter.allCases, id: \.self) { Text(label(for: $0)).tag($0) } }
                    adjustmentControl("Brightness", value: binding(\.adjustments.brightness), range: -0.3...0.3)
                    adjustmentControl("Contrast", value: binding(\.adjustments.contrast), range: 0.6...1.8)
                    adjustmentControl("Saturation", value: binding(\.adjustments.saturation), range: 0...1.5)
                }
                Section("Rotation") {
                    ViewThatFits(in: .horizontal) {
                        HStack { rotationButtons }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack { rotationButtons }
                    }
                }
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack { historyButtons }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack { historyButtons }
                    }
                }
            }
            .navigationTitle("Edit Page")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() } } }
            .task { await load() }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<PageEditState, T>) -> Binding<T> { Binding(get: { draft[keyPath: path] }, set: { value in mutate { $0[keyPath: path] = value } }) }
    private func mutate(_ change: (inout PageEditState) -> Void) { undoStack.append(draft); if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }; redoStack.removeAll(); change(&draft) }
    private func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(draft); draft = previous }
    private func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(draft); draft = next }
    private func label(for filter: PageFilter) -> LocalizedStringKey { switch filter { case .original: "Original"; case .auto: "Auto"; case .color: "Color"; case .grayscale: "Grayscale"; case .blackWhite: "Black & White"; case .shadows: "Shadows" } }

    private func adjustmentControl(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Slider(value: value, in: range)
        }
    }

    @ViewBuilder private var rotationButtons: some View {
        Button("Rotate Left") { mutate { $0.rotation -= 90 } }
            .frame(maxWidth: .infinity)
        Button("Rotate Right") { mutate { $0.rotation += 90 } }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var historyButtons: some View {
        Button("Undo", action: undo)
            .disabled(undoStack.isEmpty)
            .keyboardShortcut(AppKeyboardShortcut.undo, modifiers: .command)
            .frame(maxWidth: .infinity)
        Button("Redo", action: redo)
            .disabled(redoStack.isEmpty)
            .keyboardShortcut(AppKeyboardShortcut.undo, modifiers: [.command, .shift])
            .frame(maxWidth: .infinity)
    }

    private func load() async {
        guard let document = state.document, document.pages.indices.contains(pageIndex), let revision = document.pages[pageIndex].revisions.first(where: { $0.id == document.pages[pageIndex].activeRevisionID }) else { return }
        draft = revision.editState
        page = document.pages[pageIndex]
        documentID = document.id
    }

    private func apply() { Task { guard var document = state.document, document.pages.indices.contains(pageIndex), let revision = document.pages[pageIndex].revisions.firstIndex(where: { $0.id == document.pages[pageIndex].activeRevisionID }) else { return }; document.pages[pageIndex].revisions[revision].editState = draft; do { try await state.repository.update(document); state.document = document; dismiss() } catch { state.errorMessage = error.localizedDescription } } }
}

private struct PageEditPreview: View {
    let page: ScanPage
    let documentID: UUID
    let draft: PageEditState
    let repository: RecentRepository
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else if failed {
                ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .task(id: draft) {
            image = nil
            failed = false
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let directory = await repository.directory(for: documentID)
            var previewPage = page
            guard let revisionIndex = previewPage.revisions.firstIndex(where: { $0.id == previewPage.activeRevisionID }) else {
                failed = true
                return
            }
            previewPage.revisions[revisionIndex].editState = draft
            let rendered = try? await PageRenderer.shared.renderOffMain(page: previewPage, documentDirectory: directory, maximumPixelSize: 1_200)
            guard !Task.isCancelled else { return }
            if let rendered { image = UIImage(cgImage: rendered) }
            else { failed = true }
        }
        .accessibilityLabel("Edited page preview")
    }
}
