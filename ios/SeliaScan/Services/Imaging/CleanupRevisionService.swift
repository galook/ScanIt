import Foundation

struct CleanupRevisionService {
    func applySmart(to document: inout ScanDocument, pageIndex: Int, repository: RecentRepository) async throws {
        guard document.pages.indices.contains(pageIndex) else { return }
        let page = document.pages[pageIndex]
        guard let parent = page.revisions.first(where: { $0.id == page.activeRevisionID }) else { throw ImagingError.invalidImage }
        let directory = await repository.directory(for: document.id)
        let childID = UUID()
        let reference = StorageLayout.revisionReference(id: childID, extension: FileExtension.jpeg)
        let rendered = try PageRenderer.shared.render(page: page, documentDirectory: directory)
        try CleanupService().smartCleanup(image: rendered, destination: reference.resolving(in: directory))
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: reference.resolving(in: directory).path)
        let child = PageRevision(id: childID, source: reference, editState: PageEditState(), parentRevisionID: parent.id, isRedacted: false)
        document.pages[pageIndex].revisions.append(child)
        document.pages[pageIndex].activeRevisionID = childID
        remapAnalysis(on: &document.pages[pageIndex], through: parent.editState)
        try await repository.update(document)
    }

    func applyManual(strokes: [RedactionStroke], to document: inout ScanDocument, pageIndex: Int, repository: RecentRepository) async throws {
        guard document.pages.indices.contains(pageIndex), !strokes.isEmpty else { return }
        let page = document.pages[pageIndex]
        guard let parent = page.revisions.first(where: { $0.id == page.activeRevisionID }) else { throw ImagingError.invalidImage }
        let directory = await repository.directory(for: document.id)
        let childID = UUID(); let reference = StorageLayout.revisionReference(id: childID, extension: FileExtension.jpeg)
        let rendered = try PageRenderer.shared.render(page: page, documentDirectory: directory)
        try CleanupService().manualCleanup(image: rendered, strokes: strokes, destination: reference.resolving(in: directory))
        try? FileManager.default.setAttributes(FileProtection.attributes, ofItemAtPath: reference.resolving(in: directory).path)
        let child = PageRevision(id: childID, source: reference, editState: PageEditState(), parentRevisionID: parent.id, isRedacted: false)
        document.pages[pageIndex].revisions.append(child); document.pages[pageIndex].activeRevisionID = childID
        remapAnalysis(on: &document.pages[pageIndex], through: parent.editState)
        try await repository.update(document)
    }

    private func remapAnalysis(on page: inout ScanPage, through edits: PageEditState) {
        guard var analysis = page.analysis else { return }
        analysis.tokens = analysis.tokens.compactMap { token in
            guard let bounds = PDFCoordinateMapper.map(token.bounds, through: edits) else { return nil }
            return RecognizedToken(id: token.id, text: token.text, bounds: bounds, confidence: token.confidence)
        }
        analysis.barcodes = analysis.barcodes.compactMap { barcode in
            guard let bounds = PDFCoordinateMapper.map(barcode.bounds, through: edits) else { return nil }
            return RecognizedBarcode(id: barcode.id, payload: barcode.payload, symbology: barcode.symbology, bounds: bounds)
        }
        page.analysis = analysis
    }
}
