import Foundation
import Photos
import CoreLocation

enum AssetLibraryWriterError: LocalizedError {
    case permissionDenied
    case albumUnavailable
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L10n.text("写真へのアクセスが許可されていないため、動画を保存できませんでした。")
        case .albumUnavailable:
            return L10n.text("保存先の「%@」アルバムを準備できませんでした。", AppIdentity.photoAlbumName)
        case .saveFailed(let message):
            return message.isEmpty ? L10n.text("動画を写真ライブラリへ保存できませんでした。") : message
        }
    }
}

struct EditableAssetSaveResult: Sendable {
    let identifier: String
    let didAttachRenderedContent: Bool
}

final class AssetLibraryWriter {
    private let albumName: String
    private let temporaryFileStore: TemporaryFileStore

    init(
        albumName: String,
        temporaryFileStore: TemporaryFileStore = TemporaryFileStore()
    ) {
        self.albumName = albumName
        self.temporaryFileStore = temporaryFileStore
    }

    func saveVideo(
        url: URL,
        location: CLLocation?
    ) async throws -> String {
        try await ensurePhotoLibraryAuthorization()
        let album = try await getOrCreateAlbum()

        var lastError: Error?
        for attempt in 1...2 {
            do {
                let identifier = try await performPlainSave(
                    url: url,
                    location: location,
                    album: album
                )
                AppLog.save.info("save.success attempt=\(attempt)")
                removeManagedFiles([url])
                return identifier
            } catch {
                lastError = error
                AppLog.save.warning(
                    "save.retry attempt=\(attempt) reason=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
        throw lastError ?? AssetLibraryWriterError.saveFailed("Unknown")
    }

    func saveVideo(
        originalURL: URL,
        renderedURL: URL,
        adjustmentData: PHAdjustmentData,
        location: CLLocation?
    ) async throws -> EditableAssetSaveResult {
        try await ensurePhotoLibraryAuthorization()

        let album = try await getOrCreateAlbum()

        var lastError: Error?
        for attempt in 1...2 {
            do {
                let result = try await performSave(
                    originalURL: originalURL,
                    renderedURL: renderedURL,
                    adjustmentData: adjustmentData,
                    location: location,
                    album: album
                )
                AppLog.save.info("save.success attempt=\(attempt)")
                removeManagedFiles([originalURL, renderedURL])
                return result
            } catch {
                lastError = error
                AppLog.save.warning("save.retry attempt=\(attempt) reason=\(error.localizedDescription, privacy: .private)")
            }
        }

        if let lastError {
            // 容量不足などの原因を上位で分類できるよう、元のエラーを失わない。
            throw lastError
        }
        throw AssetLibraryWriterError.saveFailed("Unknown")
    }

    private func ensurePhotoLibraryAuthorization() async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch currentStatus {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requestedStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw AssetLibraryWriterError.permissionDenied
            }
        default:
            throw AssetLibraryWriterError.permissionDenied
        }
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

    private func performSave(
        originalURL: URL,
        renderedURL: URL,
        adjustmentData: PHAdjustmentData,
        location: CLLocation?,
        album: PHAssetCollection
    ) async throws -> EditableAssetSaveResult {
        try await withCheckedThrowingContinuation { continuation in
            var createdAssetIdentifier: String?
            var contentPreparationError: Error?
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: originalURL
                ) else { return }
                assetRequest.location = location
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                      let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                createdAssetIdentifier = assetPlaceholder.localIdentifier
                let editingOutput = PHContentEditingOutput(
                    placeholderForCreatedAsset: assetPlaceholder
                )
                editingOutput.adjustmentData = adjustmentData
                do {
                    if FileManager.default.fileExists(
                        atPath: editingOutput.renderedContentURL.path
                    ) {
                        try FileManager.default.removeItem(
                            at: editingOutput.renderedContentURL
                        )
                    }
                    try FileManager.default.copyItem(
                        at: renderedURL,
                        to: editingOutput.renderedContentURL
                    )
                    assetRequest.contentEditingOutput = editingOutput
                } catch {
                    contentPreparationError = error
                }
                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
            }) { success, error in
                if success, let createdAssetIdentifier {
                    if let contentPreparationError {
                        AppLog.save.warning(
                            "save.adjustment.fallback reason=\(contentPreparationError.localizedDescription, privacy: .private)"
                        )
                    }
                    continuation.resume(returning: EditableAssetSaveResult(
                        identifier: createdAssetIdentifier,
                        didAttachRenderedContent: contentPreparationError == nil
                    ))
                } else {
                    continuation.resume(throwing: error ?? AssetLibraryWriterError.saveFailed("Unknown"))
                }
            }
        }
    }

    private func performPlainSave(
        url: URL,
        location: CLLocation?,
        album: PHAssetCollection
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var createdAssetIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: url
                ) else { return }
                assetRequest.location = location
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                      let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else {
                    return
                }
                createdAssetIdentifier = assetPlaceholder.localIdentifier
                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
            }) { success, error in
                if success, let createdAssetIdentifier {
                    continuation.resume(returning: createdAssetIdentifier)
                } else {
                    continuation.resume(
                        throwing: error ?? AssetLibraryWriterError.saveFailed("Unknown")
                    )
                }
            }
        }
    }

    private func removeManagedFiles(_ urls: [URL]) {
        var removedPaths: Set<String> = []
        for url in urls where removedPaths.insert(url.path).inserted {
            if temporaryFileStore.manages(url) {
                temporaryFileStore.removeIfExists(at: url)
            }
        }
    }
}
