import Foundation
import Photos

struct PhotosSaveResult: Sendable { let identifiers: [String] }

struct PhotosSaver {
    func save(imagesAt urls: [URL]) async throws -> PhotosSaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotosSaveError.denied }
        var identifiers: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for url in urls {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
                if let identifier = request.placeholderForCreatedAsset?.localIdentifier { identifiers.append(identifier) }
            }
        }
        return PhotosSaveResult(identifiers: identifiers)
    }
}

enum PhotosSaveError: LocalizedError { case denied; var errorDescription: String? { String(localized: "Allow FruitySelia to add images to Photos, then try again.") } }
