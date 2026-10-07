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

private final class PhotoChangeState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func update(_ body: (inout Value) -> Void) {
        lock.withLock { body(&value) }
    }

    func snapshot() -> Value {
        lock.withLock { value }
    }
}

private struct EditablePhotoChangeState: Sendable {
    var identifier: String?
    var contentPreparationErrorDescription: String?
}

/// 設定値は不変。PhotoKitの複数コールバック間で共有する結果はPhotoChangeStateで同期する。
final class AssetLibraryWriter: @unchecked Sendable {
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
            let state = PhotoChangeState<PHObjectPlaceholder?>(nil)
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                state.update { $0 = request.placeholderForCreatedAssetCollection }
            }) { success, error in
                let localPlaceholder = state.snapshot()
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
            let state = PhotoChangeState(EditablePhotoChangeState())
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: originalURL
                ) else { return }
                assetRequest.location = location
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                      let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                state.update { $0.identifier = assetPlaceholder.localIdentifier }
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
                    state.update {
                        $0.contentPreparationErrorDescription = error.localizedDescription
                    }
                }
                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
            }) { success, error in
                let result = state.snapshot()
                if success, let createdAssetIdentifier = result.identifier {
                    if let errorDescription = result.contentPreparationErrorDescription {
                        AppLog.save.warning(
                            "save.adjustment.fallback reason=\(errorDescription, privacy: .private)"
                        )
                    }
                    continuation.resume(returning: EditableAssetSaveResult(
                        identifier: createdAssetIdentifier,
                        didAttachRenderedContent: result.contentPreparationErrorDescription == nil
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
            let state = PhotoChangeState<String?>(nil)
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: url
                ) else { return }
                assetRequest.location = location
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                      let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else {
                    return
                }
                state.update { $0 = assetPlaceholder.localIdentifier }
                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
            }) { success, error in
                let createdAssetIdentifier = state.snapshot()
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
