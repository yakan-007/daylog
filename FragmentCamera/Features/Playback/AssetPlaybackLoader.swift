import Foundation
import Photos
import AVFoundation

enum AssetPlaybackLoaderError: LocalizedError {
    case timeout
    case itemUnavailable

    var errorDescription: String? {
        switch self {
        case .timeout:
            return L10n.text("動画の読み込みがタイムアウトしました。")
        case .itemUnavailable:
            return L10n.text("動画を取得できませんでした。")
        }
    }
}

final class AssetPlaybackLoader {
    @MainActor static let shared = AssetPlaybackLoader()
    private let cachedPlayerItems = NSCache<NSString, AVPlayerItem>()
    private init() {}

    @discardableResult
    func requestPlayerItem(
        for asset: PHAsset,
        deliveryMode: PHVideoRequestOptionsDeliveryMode = .fastFormat,
        timeout: TimeInterval = 20,
        completion: @escaping (Result<AVPlayerItem, Error>) -> Void
    ) -> PHImageRequestID {
        let cacheKey = asset.localIdentifier as NSString
        if let cachedItem = cachedPlayerItems.object(forKey: cacheKey) {
            cachedPlayerItems.removeObject(forKey: cacheKey)
            completion(.success(cachedItem))
            return PHInvalidImageRequestID
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = deliveryMode
        options.version = .original

        let manager = PHImageManager.default()
        let lock = NSLock()
        var finished = false

        func finish(_ result: Result<AVPlayerItem, Error>) {
            let shouldComplete = lock.withLock {
                guard !finished else { return false }
                finished = true
                return true
            }
            guard shouldComplete else { return }
            completion(result)
        }

        let requestId = manager.requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            if let error = info?[PHImageErrorKey] as? Error {
                finish(.failure(error))
                return
            }
            guard let avAsset else {
                finish(.failure(AssetPlaybackLoaderError.itemUnavailable))
                return
            }
            let playerItem = AVPlayerItem(asset: avAsset)
            playerItem.audioMix = audioMix
            finish(.success(playerItem))
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            let shouldCancel = lock.withLock { !finished }
            guard shouldCancel else { return }
            manager.cancelImageRequest(requestId)
            finish(.failure(AssetPlaybackLoaderError.timeout))
        }

        return requestId
    }

    func cancel(_ requestId: PHImageRequestID?) {
        guard let requestId, requestId != PHInvalidImageRequestID else { return }
        PHImageManager.default().cancelImageRequest(requestId)
    }

    @discardableResult
    func prefetchPlayerItem(
        for asset: PHAsset,
        deliveryMode: PHVideoRequestOptionsDeliveryMode = .fastFormat,
        timeout: TimeInterval = 20
    ) -> PHImageRequestID {
        let cacheKey = asset.localIdentifier as NSString
        guard cachedPlayerItems.object(forKey: cacheKey) == nil else {
            return PHInvalidImageRequestID
        }

        return requestPlayerItem(for: asset, deliveryMode: deliveryMode, timeout: timeout) { [weak self] result in
            guard case .success(let playerItem) = result else { return }
            self?.cachedPlayerItems.setObject(playerItem, forKey: cacheKey)
        }
    }
}
