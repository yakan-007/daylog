import Foundation
import Photos
import UIKit

enum PhotoLibraryRepositoryError: LocalizedError {
    case authorizationNotDetermined
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .authorizationNotDetermined:
            return L10n.text("写真へのアクセスがまだ選択されていません。")
        case .permissionDenied:
            return L10n.text("写真へのアクセスが許可されていません。")
        }
    }
}

@MainActor
protocol PlaybackAssetRepository: AnyObject {
    func asset(localIdentifier: String) -> PHAsset?
}

/// PhotoKitへのアクセス点。UIで扱うPHAssetと変更通知をMainActorに閉じ込める。
@MainActor
final class VlogishPhotoLibraryRepository: NSObject, PHPhotoLibraryChangeObserver, PlaybackAssetRepository {
    private let albumName: String
    private let imageManager = PHCachingImageManager()
    private var changeContinuations: [UUID: AsyncStream<LibraryChangeEvent>.Continuation] = [:]

    init(albumName: String = AppIdentity.photoAlbumName) {
        self.albumName = albumName
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func fetchAllClips(requestAuthorizationIfNeeded: Bool) async throws -> [ClipSummary] {
        let status = await readAuthorizationStatus(
            requestIfNeeded: requestAuthorizationIfNeeded
        )
        switch status {
        case .authorized, .limited:
            break
        case .notDetermined:
            throw PhotoLibraryRepositoryError.authorizationNotDetermined
        default:
            throw PhotoLibraryRepositoryError.permissionDenied
        }

        guard let album = fetchAlbumCollections().firstObject else { return [] }
        return assets(from: fetchAssets(in: album)).map(makeClipSummary)
    }

    private func readAuthorizationStatus(
        requestIfNeeded: Bool
    ) async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined, requestIfNeeded else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func asset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    func clipSummary(localIdentifier: String) -> ClipSummary? {
        asset(localIdentifier: localIdentifier).map(makeClipSummary)
    }

    func assets(localIdentifiers: [String]) -> [PHAsset] {
        guard !localIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: localIdentifiers,
            options: nil
        )
        var resolved: [PHAsset] = []
        resolved.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            resolved.append(asset)
        }
        return resolved
    }

    func requestThumbnail(
        assetLocalIdentifier: String,
        targetSize: CGSize,
        completion: @MainActor @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        guard let asset = asset(localIdentifier: assetLocalIdentifier) else {
            completion(nil)
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func cancelThumbnailRequest(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    func observeChanges() -> AsyncStream<LibraryChangeEvent> {
        AsyncStream { continuation in
            let identifier = UUID()
            changeContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.changeContinuations.removeValue(forKey: identifier)
                }
            }
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.notifyLibraryChanged()
        }
    }

    private func notifyLibraryChanged() {
        for continuation in changeContinuations.values {
            continuation.yield(.photoLibraryDidChange)
        }
    }

    private func fetchAlbumCollections() -> PHFetchResult<PHAssetCollection> {
        let collectionOptions = PHFetchOptions()
        collectionOptions.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: collectionOptions)
    }

    private func fetchAssets(in album: PHAssetCollection) -> PHFetchResult<PHAsset> {
        let assetOptions = PHFetchOptions()
        assetOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assetOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        return PHAsset.fetchAssets(in: album, options: assetOptions)
    }

    private func assets(from result: PHFetchResult<PHAsset>?) -> [PHAsset] {
        guard let result else { return [] }
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private func makeClipSummary(asset: PHAsset) -> ClipSummary {
        let capturedAt = asset.creationDate ?? Date.distantPast
        return ClipSummary(
            assetLocalIdentifier: asset.localIdentifier,
            capturedAt: capturedAt,
            dayKey: VlogishFormatters.dayKey(for: capturedAt),
            duration: asset.duration
        )
    }
}

@MainActor
final class ThumbnailService: LibraryThumbnailProviding {
    private let repository: VlogishPhotoLibraryRepository

    init(repository: VlogishPhotoLibraryRepository) {
        self.repository = repository
    }

    @discardableResult
    func requestThumbnail(
        assetLocalIdentifier: String,
        targetSize: CGSize,
        completion: @MainActor @escaping (UIImage?) -> Void
    ) -> LibraryThumbnailRequest {
        LibraryThumbnailRequest(
            rawValue: repository.requestThumbnail(
                assetLocalIdentifier: assetLocalIdentifier,
                targetSize: targetSize,
                completion: completion
            )
        )
    }

    func cancelThumbnailRequest(_ request: LibraryThumbnailRequest) {
        repository.cancelThumbnailRequest(request.rawValue)
    }
}

@MainActor
final class VlogishLibraryUseCase {
    private let store: ClipMetadataStore
    private let repository: VlogishPhotoLibraryRepository
    private let pageSize: Int

    init(
        store: ClipMetadataStore,
        repository: VlogishPhotoLibraryRepository,
        pageSize: Int = 20
    ) {
        self.store = store
        self.repository = repository
        self.pageSize = pageSize
    }

    func loadInitialSections() async -> [DaySection] {
        await store.fetchDaySections(limit: pageSize, cursor: nil)
    }

    func loadMoreSections(after dayKey: String?) async -> [DaySection] {
        await store.fetchDaySections(limit: pageSize, cursor: dayKey)
    }

    func loadCalendarSummaries() async -> [DayCalendarSummary] {
        await store.fetchCalendarSummaries()
    }

    func loadDaySection(dayKey: String) async -> DaySection? {
        await store.fetchDaySection(dayKey: dayKey)
    }

    func registerSavedClip(localIdentifier: String) async -> [DaySection]? {
        guard let clip = repository.clipSummary(localIdentifier: localIdentifier) else {
            return nil
        }
        await store.upsert(clip)
        return await store.fetchDaySections(limit: pageSize, cursor: nil)
    }

    func refresh(requestAuthorizationIfNeeded: Bool) async throws -> [DaySection] {
        let clips = try await repository.fetchAllClips(
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
        await store.replaceAll(with: clips)
        return await store.fetchDaySections(limit: pageSize, cursor: nil)
    }

    func observeLibraryChanges() -> AsyncStream<LibraryChangeEvent> {
        repository.observeChanges()
    }
}
