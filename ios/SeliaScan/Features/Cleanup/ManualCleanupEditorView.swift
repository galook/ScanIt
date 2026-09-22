import SwiftUI
import UIKit

struct ManualCleanupEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let pageIndex: Int
    @State private var image: UIImage?
    @State private var strokes: [RedactionStroke] = []
    @State private var redo: [RedactionStroke] = []
    @State private var active: RedactionStroke?
    @State private var width = 42.0

    var body: some View {
        NavigationStack {
            VStack {
                GeometryReader { proxy in
                    let pageRect = fittedPageRect(in: proxy.size)
                    ZStack {
                        if let image { Image(uiImage: image).resizable().frame(width: pageRect.width, height: pageRect.height).position(x: pageRect.midX, y: pageRect.midY) }
                        Canvas { context, size in
                            for stroke in strokes + [active].compactMap({ $0 }) {
                                guard let first = stroke.points.first else { continue }
                                var path = Path(); path.move(to: CGPoint(x: pageRect.minX + first.x * pageRect.width, y: pageRect.minY + (1 - first.y) * pageRect.height))
                                for point in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: pageRect.minX + point.x * pageRect.width, y: pageRect.minY + (1 - point.y) * pageRect.height)) }
                                context.stroke(path, with: .color(.orange.opacity(0.75)), style: StrokeStyle(lineWidth: stroke.width * pageRect.width, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if active == nil, !pageRect.contains(value.location) { return }
                            let point = CGPoint(x: min(1, max(0, (value.location.x - pageRect.minX) / pageRect.width)), y: min(1, max(0, 1 - (value.location.y - pageRect.minY) / pageRect.height)))
                            if active == nil { active = RedactionStroke(id: UUID(), points: [point], width: width / pageRect.width, line: false); redo.removeAll() } else if (active?.points.count ?? 0) < AppConfiguration.maximumStrokePoints { active?.points.append(point) }
                        }.onEnded { _ in if var stroke = active, strokes.count < AppConfiguration.maximumEditStrokes { if stroke.points.count == 1 { stroke.points.append(stroke.points[0]) }; strokes.append(stroke) }; active = nil })
                    }.background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack { Text("Brush size"); Slider(value: $width, in: 12...100) }
                HStack { Button("Undo") { if let item = strokes.popLast() { redo.append(item) } }.disabled(strokes.isEmpty).keyboardShortcut(AppKeyboardShortcut.undo, modifiers: .command); Button("Redo") { if let item = redo.popLast() { strokes.append(item) } }.disabled(redo.isEmpty).keyboardShortcut(AppKeyboardShortcut.undo, modifiers: [.command, .shift]); Button("Clear") { redo.append(contentsOf: strokes); strokes.removeAll() }.disabled(strokes.isEmpty) }.buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Manual cleanup")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() }.disabled(strokes.isEmpty) } }
            .task { await loadImage() }
        }
    }

    private func loadImage() async { guard let document = state.document, document.pages.indices.contains(pageIndex) else { return }; let directory = await state.repository.directory(for: document.id); if let rendered = try? await PageRenderer.shared.renderOffMain(page: document.pages[pageIndex], documentDirectory: directory, maximumPixelSize: 1_800) { image = UIImage(cgImage: rendered) } }
    private func fittedPageRect(in size: CGSize) -> CGRect { guard let image, image.size.width > 0, image.size.height > 0 else { return CGRect(origin: .zero, size: size) }; let scale = min(size.width / image.size.width, size.height / image.size.height); let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale); return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height) }
    private func apply() { Task { guard var document = state.document else { return }; do { try await CleanupRevisionService().applyManual(strokes: strokes, to: &document, pageIndex: pageIndex, repository: state.repository); state.document = document; dismiss() } catch { state.errorMessage = error.localizedDescription } } }
}
