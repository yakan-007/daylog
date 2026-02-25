import Foundation
import Photos
import AVFoundation

enum AssetPlaybackLoaderError: Error {
    case timeout
    case itemUnavailable
}

final class AssetPlaybackLoader {
    static let shared = AssetPlaybackLoader()
    private init() {}

    @discardableResult
    func requestPlayerItem(
        for asset: PHAsset,
        deliveryMode: PHVideoRequestOptionsDeliveryMode = .fastFormat,
        timeout: TimeInterval = 20,
        completion: @escaping (Result<AVPlayerItem, Error>) -> Void
    ) -> PHImageRequestID {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = deliveryMode

        let manager = PHImageManager.default()
        let lock = NSLock()
        var finished = false

        func finish(_ result: Result<AVPlayerItem, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            completion(result)
        }

        let requestId = manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            if let playerItem {
                finish(.success(playerItem))
            } else {
                finish(.failure(AssetPlaybackLoaderError.itemUnavailable))
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            lock.lock()
            let shouldCancel = !finished
            lock.unlock()
            guard shouldCancel else { return }
            manager.cancelImageRequest(requestId)
            finish(.failure(AssetPlaybackLoaderError.timeout))
        }

        return requestId
    }

    func cancel(_ requestId: PHImageRequestID?) {
        guard let requestId else { return }
        PHImageManager.default().cancelImageRequest(requestId)
    }
}
