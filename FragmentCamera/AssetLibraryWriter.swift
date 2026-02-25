import Foundation
import Photos
import CoreLocation

enum AssetLibraryWriterError: Error {
    case permissionDenied
    case albumUnavailable
    case saveFailed(String)
}

final class AssetLibraryWriter {
    private let albumName: String

    init(albumName: String) {
        self.albumName = albumName
    }

    func saveVideo(url: URL, location: CLLocation?) async throws -> String {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard photoStatus == .authorized || photoStatus == .limited else {
            throw AssetLibraryWriterError.permissionDenied
        }

        let album = try await getOrCreateAlbum()

        var lastError: Error?
        for attempt in 1...2 {
            do {
                let identifier = try await performSave(url: url, location: location, album: album)
                AppLog.save.info("save.success attempt=\(attempt)")
                try? FileManager.default.removeItem(at: url)
                return identifier
            } catch {
                lastError = error
                AppLog.save.warning("save.retry attempt=\(attempt) reason=\(error.localizedDescription, privacy: .public)")
            }
        }

        throw AssetLibraryWriterError.saveFailed(lastError?.localizedDescription ?? "Unknown")
    }

    private func getOrCreateAlbum() async throws -> PHAssetCollection {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let album = collections.firstObject { return album }

        let placeholder: PHObjectPlaceholder = try await withCheckedThrowingContinuation { continuation in
            var localPlaceholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                localPlaceholder = request.placeholderForCreatedAssetCollection
            }) { success, error in
                if success, let localPlaceholder {
                    continuation.resume(returning: localPlaceholder)
                } else {
                    continuation.resume(throwing: error ?? AssetLibraryWriterError.albumUnavailable)
                }
            }
        }

        let newCollections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
        guard let album = newCollections.firstObject else {
            throw AssetLibraryWriterError.albumUnavailable
        }
        return album
    }

    private func performSave(url: URL, location: CLLocation?, album: PHAssetCollection) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var createdAssetIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) else { return }
                assetRequest.location = location
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                      let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                createdAssetIdentifier = assetPlaceholder.localIdentifier
                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
            }) { success, error in
                if success, let createdAssetIdentifier {
                    continuation.resume(returning: createdAssetIdentifier)
                } else {
                    continuation.resume(throwing: error ?? AssetLibraryWriterError.saveFailed("Unknown"))
                }
            }
        }
    }
}
