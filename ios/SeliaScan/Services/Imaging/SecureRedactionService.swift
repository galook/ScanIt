import Foundation

struct SecureRedactionService {
    func apply(to document: inout ScanDocument, pageIndex: Int, strokes: [RedactionStroke], repository: RecentRepository) async throws {
        guard document.pages.indices.contains(pageIndex), !strokes.isEmpty else { return }
        let page = document.pages[pageIndex]
        let directory = await repository.directory(for: document.id)
        guard let parent = page.revisions.first(where: { $0.id == page.activeRevisionID }) else { throw ImagingError.invalidImage }
        let rendered = try PageRenderer.shared.render(page: page, documentDirectory: directory)
        let childID = UUID(); let relative = StorageLayout.revisionReference(id: childID, extension: FileExtension.jpeg)
        try RedactionRenderer().apply(strokes: strokes, to: rendered, outputURL: relative.resolving(in: directory))
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: relative.resolving(in: directory).path)
        let child = PageRevision(id: childID, source: relative, editState: PageEditState(), parentRevisionID: page.activeRevisionID, isRedacted: true)
        document.pages[pageIndex].revisions.append(child); document.pages[pageIndex].activeRevisionID = childID
        if var analysis = document.pages[pageIndex].analysis {
            analysis.tokens = analysis.tokens.compactMap { token in
                guard let mapped = PDFCoordinateMapper.map(token.bounds, through: parent.editState), !intersectsRedaction(mapped, strokes: strokes) else { return nil }
                return RecognizedToken(id: token.id, text: token.text, bounds: mapped, confidence: token.confidence)
            }
            analysis.barcodes = analysis.barcodes.compactMap { barcode in
                guard let mapped = PDFCoordinateMapper.map(barcode.bounds, through: parent.editState), !intersectsRedaction(mapped, strokes: strokes) else { return nil }
                return RecognizedBarcode(id: barcode.id, payload: barcode.payload, symbology: barcode.symbology, bounds: mapped)
            }
            document.pages[pageIndex].analysis = analysis
        }
        try await repository.update(document)
    }

    private func intersectsRedaction(_ bounds: CGRect, strokes: [RedactionStroke]) -> Bool {
        strokes.contains { stroke in
            guard let first = stroke.points.first else { return false }
            let xs = stroke.points.map(\.x), ys = stroke.points.map(\.y)
            let rect = CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y, width: (xs.max() ?? first.x) - (xs.min() ?? first.x), height: (ys.max() ?? first.y) - (ys.min() ?? first.y)).insetBy(dx: -stroke.width / 2, dy: -stroke.width / 2)
            return rect.intersects(bounds)
        }
    }
}
