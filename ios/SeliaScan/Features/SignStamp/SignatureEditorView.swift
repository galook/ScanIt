import SwiftUI
import PencilKit
import PhotosUI
import UniformTypeIdentifiers

struct SignatureEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let pageIndex: Int

    @State private var drawing = PKDrawing()
    @State private var draft: MarkDraft?
    @State private var markImage: UIImage?
    @State private var savedMarks: [SavedMark] = []
    @State private var center = CGPoint(x: 0.5, y: 0.75)
    @State private var widthFraction = 0.35
    @State private var rotation = 0.0
    @State private var saveForReuse = true
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var applying = false
    @State private var markToDelete: SavedMark?

    private let store = SavedMarkStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let markImage {
                        MarkPlacementPreview(pageIndex: pageIndex, mark: markImage, center: $center, widthFraction: $widthFraction, rotation: $rotation)
                            .frame(height: 390)
                        Text("Drag to move. Pinch to resize and rotate.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        SignatureCanvas(drawing: $drawing)
                            .frame(minHeight: 240)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Signature drawing area")
                        Button { useDrawing() } label: { Label("Use Drawing", systemImage: SystemImageName.signature) }
                            .buttonStyle(.borderedProminent)
                            .disabled(drawing.strokes.isEmpty)
                    }

                    creationActions
                    savedMarkPicker

                    if draft != nil {
                        GroupBox("Manual Position") {
                            VStack {
                                positionSlider("Horizontal Position", value: Binding(get: { center.x }, set: { center.x = $0 }), range: 0...1)
                                positionSlider("Vertical Position", value: Binding(get: { center.y }, set: { center.y = $0 }), range: 0...1)
                                positionSlider("Size", value: $widthFraction, range: 0.1...0.8)
                                positionSlider("Rotation", value: $rotation, range: -180...180, degrees: true)
                            }
                        }
                        if case .saved(let mark) = draft {
                            Button("Delete Saved Mark", role: .destructive) { markToDelete = mark }
                        } else {
                            Toggle("Save mark for reuse", isOn: $saveForReuse)
                        }
                    }

                    Text("This adds only a visual signature or stamp. It does not verify identity or document integrity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Sign / Stamp")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier(AutomationIdentifier.MarkEditor.cancel) }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Clear") { drawing = PKDrawing(); draft = nil; markImage = nil }
                    Spacer()
                    Button("Apply") { apply() }.disabled(draft == nil || applying)
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                Task { await importFile(url) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .task { await reloadSavedMarks() }
            .confirmationDialog("Delete saved mark?", isPresented: Binding(get: { markToDelete != nil }, set: { if !$0 { markToDelete = nil } })) {
                Button("Delete", role: .destructive) { deleteSelectedMark() }
                Button("Cancel", role: .cancel) { markToDelete = nil }
            }
        }
    }

    private var creationActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack { markActionButtons }
            VStack { markActionButtons }
        }
    }

    @ViewBuilder private var markActionButtons: some View {
        PhotosPicker(selection: $photoItem, matching: .images) { Label("Import Stamp", systemImage: "photo") }
            .buttonStyle(.bordered)
        Button { showFileImporter = true } label: { Label("Files", systemImage: "folder") }
            .buttonStyle(.bordered)
        Button { scanMark() } label: { Label("Scan Stamp", systemImage: SystemImageName.scanDocument) }
            .buttonStyle(.bordered)
    }

    private var savedMarkPicker: some View {
        GroupBox("Saved Signatures and Stamps") {
            if savedMarks.isEmpty {
                Text("No saved signature or stamp yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(savedMarks) { mark in
                            SavedMarkButton(mark: mark, store: store, selected: draft?.savedID == mark.id) {
                                select(mark)
                            } onDelete: {
                                markToDelete = mark
                            }
                        }
                    }
                }
            }
        }
    }

    private func positionSlider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, degrees: Bool = false) -> some View {
        HStack {
            Text(title).frame(width: 126, alignment: .leading)
            Slider(value: value, in: range)
            if degrees { Text("\(Int(value.wrappedValue))°").monospacedDigit().frame(width: 48) }
        }
    }

    private func useDrawing() {
        guard !drawing.strokes.isEmpty else { return }
        let data = drawing.dataRepresentation()
        draft = .drawing(data)
        let bounds = drawing.bounds
        markImage = drawing.image(from: bounds, scale: max(1, 1_024 / max(bounds.width, bounds.height)))
    }

    private func select(_ mark: SavedMark) {
        Task {
            do { markImage = try await store.preview(mark); draft = .saved(mark) }
            catch { state.errorMessage = error.localizedDescription }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw MarkStoreError.invalidImage }
            try await selectImageData(data)
        } catch { state.errorMessage = error.localizedDescription }
    }

    private func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try await selectImageData(Data(contentsOf: url, options: .mappedIfSafe)) }
        catch { state.errorMessage = error.localizedDescription }
    }

    private func scanMark() {
        Task {
            do {
                let scan = try await state.scanner.scan()
                guard let url = scan.imageURLs.first else { throw MarkStoreError.invalidImage }
                try await selectImageData(Data(contentsOf: url, options: .mappedIfSafe))
            } catch ScannerError.cancelled { }
            catch { state.errorMessage = error.localizedDescription }
        }
    }

    private func selectImageData(_ data: Data) async throws {
        markImage = try await store.preview(imageData: data)
        draft = .image(data)
    }

    private func reloadSavedMarks() async {
        do { savedMarks = try await store.list() }
        catch { state.errorMessage = error.localizedDescription }
    }

    private func deleteSelectedMark() {
        guard let mark = markToDelete else { return }
        markToDelete = nil
        Task {
            do {
                try await store.delete(mark)
                if draft?.savedID == mark.id { draft = nil; markImage = nil }
                await reloadSavedMarks()
            } catch { state.errorMessage = error.localizedDescription }
        }
    }

    private func apply() {
        guard let draft else { return }
        applying = true
        Task {
            guard var document = state.document, document.pages.indices.contains(pageIndex) else { applying = false; return }
            let directory = await state.repository.directory(for: document.id)
            do {
                let reference: RelativeFileReference
                let kind: AnnotationKind
                switch draft {
                case .saved(let mark):
                    reference = try await store.materialize(mark, in: directory)
                    kind = mark.kind
                case .drawing(let data):
                    reference = try await store.materialize(drawingData: data, in: directory)
                    kind = .signature
                    if saveForReuse, let drawing = try? PKDrawing(data: data) { _ = try await store.save(drawing: drawing, name: "Signature") }
                case .image(let data):
                    reference = try await store.materialize(imageData: data, in: directory)
                    kind = .stamp
                    if saveForReuse { _ = try await store.save(imageData: data, name: "Stamp") }
                }
                guard let revisionIndex = document.pages[pageIndex].revisions.firstIndex(where: { $0.id == document.pages[pageIndex].activeRevisionID }) else { throw StorageError.corrupt }
                document.pages[pageIndex].revisions[revisionIndex].editState.annotations.append(PageAnnotation(id: UUID(), kind: kind, asset: reference, center: center, scale: widthFraction, rotation: rotation * .pi / 180))
                try await state.repository.update(document)
                state.document = document
                dismiss()
            } catch { applying = false; state.errorMessage = error.localizedDescription }
        }
    }
}

private enum MarkDraft {
    case drawing(Data)
    case image(Data)
    case saved(SavedMark)
    var savedID: UUID? { if case .saved(let mark) = self { mark.id } else { nil } }
}

private struct SavedMarkButton: View {
    let mark: SavedMark
    let store: SavedMarkStore
    let selected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: onSelect) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { ProgressView() }
            }
            .frame(width: 84, height: 64)
            .padding(6)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .secondary, lineWidth: selected ? 3 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { Button("Delete", role: .destructive, action: onDelete) }
        .task(id: mark.id) { image = try? await store.preview(mark, maximumSide: 256) }
    }
}

private struct MarkPlacementPreview: View {
    @EnvironmentObject private var state: AppState
    let pageIndex: Int
    let mark: UIImage
    @Binding var center: CGPoint
    @Binding var widthFraction: Double
    @Binding var rotation: Double
    @State private var page: UIImage?
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification = 1.0
    @GestureState private var rotationDelta = Angle.zero

    var body: some View {
        GeometryReader { geometry in
            let pageRect = fittedPageRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color(.secondarySystemBackground)
                if let page { Image(uiImage: page).resizable().frame(width: pageRect.width, height: pageRect.height).position(x: pageRect.midX, y: pageRect.midY) }
                else { ProgressView().position(x: geometry.size.width / 2, y: geometry.size.height / 2) }
                Image(uiImage: mark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: pageRect.width * clampedWidth)
                    .rotationEffect(.degrees(rotation) + rotationDelta)
                    .position(x: pageRect.minX + center.x * pageRect.width, y: pageRect.minY + center.y * pageRect.height)
                    .offset(drag)
                    .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }.onEnded { value in
                        center.x = min(1, max(0, center.x + value.translation.width / max(1, pageRect.width)))
                        center.y = min(1, max(0, center.y + value.translation.height / max(1, pageRect.height)))
                    })
                    .simultaneousGesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }.onEnded { value in widthFraction = min(0.8, max(0.1, widthFraction * value)) })
                    .simultaneousGesture(RotationGesture().updating($rotationDelta) { value, state, _ in state = value }.onEnded { value in rotation = normalizedDegrees(rotation + value.degrees) })
                    .accessibilityLabel("Signature or stamp preview")
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .task { await loadPage() }
    }

    private var clampedWidth: Double { min(0.8, max(0.1, widthFraction * magnification)) }
    private func fittedPageRect(in size: CGSize) -> CGRect {
        guard let page, page.size.width > 0, page.size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / page.size.width, size.height / page.size.height)
        let fitted = CGSize(width: page.size.width * scale, height: page.size.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
    private func normalizedDegrees(_ value: Double) -> Double { var result = value.truncatingRemainder(dividingBy: 360); if result > 180 { result -= 360 }; if result < -180 { result += 360 }; return result }
    private func loadPage() async {
        guard let document = state.document, document.pages.indices.contains(pageIndex) else { return }
        let directory = await state.repository.directory(for: document.id)
        if let rendered = try? await PageRenderer.shared.renderOffMain(page: document.pages[pageIndex], documentDirectory: directory, maximumPixelSize: 1_200) { page = UIImage(cgImage: rendered) }
    }
}
