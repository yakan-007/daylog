import Foundation
import Photos
import UIKit

protocol LibraryUseCase {
    func loadInitialSections() async -> [DaySection]
    func loadMoreSections(after dayKey: String?) async -> [DaySection]
    func refresh() async -> [DaySection]
    func observeLibraryChanges() -> AsyncStream<LibraryChangeEvent>
}

protocol VideoPostProcessingService {
    func process(inputURL: URL, context: VideoPostProcessContext) async throws -> ProcessedVideoResult
}

final class DefaultVideoPostProcessingService: VideoPostProcessingService {
    private let pipeline = VideoPostProcessPipeline()

    func process(inputURL: URL, context: VideoPostProcessContext) async throws -> ProcessedVideoResult {
        let processed = try await pipeline.processRecordedVideo(inputURL: inputURL, context: context)
        return ProcessedVideoResult(
            finalURL: processed.url,
            stampApplied: processed.stampApplied,
            didFallback: processed.usedFallback
        )
    }
}

final class DaylogPhotoLibraryRepository: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let albumName: String
    private let imageManager = PHCachingImageManager()
    private let queue = DispatchQueue(label: "DaylogPhotoLibraryRepository.Queue", qos: .userInitiated)
    private var changeContinuations: [UUID: AsyncStream<LibraryChangeEvent>.Continuation] = [:]
    private var trackedAlbumFetchResult: PHFetchResult<PHAssetCollection>?
    private var trackedAssetFetchResult: PHFetchResult<PHAsset>?

    init(albumName: String = "daylog") {
        self.albumName = albumName
        super.init()
        queue.sync {
            refreshTrackedFetchResults()
        }
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func fetchAllClips() async -> [ClipSummary] {
        await withCheckedContinuation { continuation in
            queue.async {
                self.refreshTrackedFetchResults()
                let result = self.trackedAssetFetchResult
                let clips = self.assets(from: result).map { asset -> ClipSummary in
                    let capturedAt = asset.creationDate ?? Date.distantPast
                    return ClipSummary(
                        assetLocalIdentifier: asset.localIdentifier,
                        capturedAt: capturedAt,
                        dayKey: DaylogFormatters.dayKey(for: capturedAt),
                        duration: asset.duration
                    )
                }
                continuation.resume(returning: clips)
            }
        }
    }

    func asset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    func assets(localIdentifiers: [String]) -> [PHAsset] {
        localIdentifiers.compactMap { asset(localIdentifier: $0) }
    }

    func requestThumbnail(
        assetLocalIdentifier: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        guard let asset = asset(localIdentifier: assetLocalIdentifier) else {
            completion(nil)
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
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
                self?.changeContinuations.removeValue(forKey: identifier)
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let shouldNotify = queue.sync { () -> Bool in
            var changed = false

            if let trackedAlbumFetchResult,
               let albumChanges = changeInstance.changeDetails(for: trackedAlbumFetchResult) {
                self.trackedAlbumFetchResult = albumChanges.fetchResultAfterChanges
                changed = true
            }

            if let trackedAssetFetchResult,
               let assetChanges = changeInstance.changeDetails(for: trackedAssetFetchResult) {
                self.trackedAssetFetchResult = assetChanges.fetchResultAfterChanges
                changed = true
            }

            let currentAlbum = trackedAlbumFetchResult?.firstObject
            if currentAlbum == nil {
                trackedAssetFetchResult = nil
            } else if trackedAssetFetchResult == nil, let currentAlbum {
                trackedAssetFetchResult = fetchAssets(in: currentAlbum)
            }

            if trackedAlbumFetchResult == nil {
                refreshTrackedFetchResults()
                if trackedAlbumFetchResult?.firstObject != nil {
                    changed = true
                }
            }

            return changed
        }

        guard shouldNotify else { return }
        DispatchQueue.main.async {
            for continuation in self.changeContinuations.values {
                continuation.yield(.photoLibraryDidChange)
            }
        }
    }

    private func refreshTrackedFetchResults() {
        trackedAlbumFetchResult = fetchAlbumCollections()
        if let album = trackedAlbumFetchResult?.firstObject {
            trackedAssetFetchResult = fetchAssets(in: album)
        } else {
            trackedAssetFetchResult = nil
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
}

final class ThumbnailService {
    private let repository: DaylogPhotoLibraryRepository

    init(repository: DaylogPhotoLibraryRepository) {
        self.repository = repository
    }

    @discardableResult
    func requestThumbnail(
        assetLocalIdentifier: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        repository.requestThumbnail(
            assetLocalIdentifier: assetLocalIdentifier,
            targetSize: targetSize,
            completion: completion
        )
    }

    func cancel(_ requestID: PHImageRequestID) {
        repository.cancelThumbnailRequest(requestID)
    }
}

final class DaylogLibraryUseCase: LibraryUseCase {
    private let store: ClipMetadataStore
    private let repository: DaylogPhotoLibraryRepository
    private let pageSize: Int

    init(
        store: ClipMetadataStore,
        repository: DaylogPhotoLibraryRepository,
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

    func refresh() async -> [DaySection] {
        let clips = await repository.fetchAllClips()
        await store.replaceAll(with: clips)
        return await store.fetchDaySections(limit: pageSize, cursor: nil)
    }

    func observeLibraryChanges() -> AsyncStream<LibraryChangeEvent> {
        repository.observeChanges()
    }
}
