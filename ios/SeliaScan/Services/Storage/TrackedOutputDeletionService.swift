import Foundation
import Photos

struct TrackedOutputDeletionService {
    func delete(_ output: TrackedOutput) async throws {
        if let bookmark = output.bookmark { try ExternalOutputStore().deleteExact(output); _ = bookmark; return }
        if let identifier = output.photosAssetIdentifier {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else { throw PhotosSaveError.denied }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard assets.count == 1 else { throw OutputError.missing }
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
            return
        }
        throw OutputError.missingIdentity
    }
}
