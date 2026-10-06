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

/// PhotoKit から再生用の AVPlayerItem を作る。
///
/// AVPlayerItem は Main Actor で作って Main Actor で渡す（Swift 6 の並行性チェックに合わせる）。
/// 完了は必ず非同期で1回だけ呼ぶ（キャッシュ済みでも、呼び出し側の状態更新より先に走らないように）。
@MainActor
final class AssetPlaybackLoader {
    static let shared = AssetPlaybackLoader()
    private let cachedPlayerItems = NSCache<NSString, AVPlayerItem>()
    private init() {}

    /// 1回の読み込みの状態。完了とタイムアウトのどちらか先に来た方だけを通す。
    private final class RequestState {
        var isFinished = false
    }

    /// PhotoKit の結果（Sendable でない AVAsset / AVAudioMix）を Main Actor へ渡すための入れ物。
    /// 受け取った後は Main Actor の中だけで使う。
    private struct DeliveredAsset: @unchecked Sendable {
        let asset: AVAsset?
        let audioMix: AVAudioMix?
        let error: Error?
    }

    @discardableResult
    func requestPlayerItem(
        for asset: PHAsset,
        deliveryMode: PHVideoRequestOptionsDeliveryMode = .fastFormat,
        timeout: TimeInterval = 20,
        completion: @escaping @MainActor (Result<AVPlayerItem, Error>) -> Void
    ) -> PHImageRequestID {
        let cacheKey = asset.localIdentifier as NSString
        if let cachedItem = cachedPlayerItems.object(forKey: cacheKey) {
            cachedPlayerItems.removeObject(forKey: cacheKey)
            Task { @MainActor in completion(.success(cachedItem)) }
            return PHInvalidImageRequestID
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = deliveryMode
        options.version = .original

        let manager = PHImageManager.default()
        let state = RequestState()
        let finish: @MainActor (Result<AVPlayerItem, Error>) -> Void = { result in
            guard !state.isFinished else { return }
            state.isFinished = true
            completion(result)
        }

        let requestId = manager.requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            let delivered = DeliveredAsset(
                asset: avAsset,
                audioMix: audioMix,
                error: info?[PHImageErrorKey] as? Error
            )
            Task { @MainActor in
                if let error = delivered.error {
                    finish(.failure(error))
                    return
                }
                guard let avAsset = delivered.asset else {
                    finish(.failure(AssetPlaybackLoaderError.itemUnavailable))
                    return
                }
                let playerItem = AVPlayerItem(asset: avAsset)
                playerItem.audioMix = delivered.audioMix
                finish(.success(playerItem))
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard !state.isFinished else { return }
            PHImageManager.default().cancelImageRequest(requestId)
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
