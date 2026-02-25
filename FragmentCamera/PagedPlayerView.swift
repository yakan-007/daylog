import SwiftUI
import AVFoundation
import Photos

struct PagedPlayerView: View {
    let assets: [PHAsset]
    @State var index: Int

    var body: some View {
        TabView(selection: $index) {
            ForEach(assets.indices, id: \.self) { i in
                AssetPlayerLayerView(asset: assets[i], isActive: i == index)
                    .tag(i)
                    .background(Color.black)
                    .ignoresSafeArea()
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
    }
}

struct AssetPlayerLayerView: UIViewRepresentable {
    let asset: PHAsset
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if isActive {
            AudioSessionMode.activatePlayback()
            if context.coordinator.currentAssetId == asset.localIdentifier { return }
            context.coordinator.currentAssetId = asset.localIdentifier
            context.coordinator.cancelPendingRequest()
            AppLog.player.info("player.load.begin asset=\(asset.localIdentifier, privacy: .public)")
            let requestId = AssetPlaybackLoader.shared.requestPlayerItem(for: asset, deliveryMode: .automatic, timeout: 15) { result in
                DispatchQueue.main.async {
                    guard case .success(let item) = result else {
                        if case .failure(let error) = result {
                            AppLog.player.error("player.load.fail asset=\(asset.localIdentifier, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                        }
                        context.coordinator.currentAssetId = nil
                        return
                    }
                    uiView.play(item: item)
                    AppLog.player.info("player.load.success asset=\(asset.localIdentifier, privacy: .public)")
                }
            }
            context.coordinator.pendingRequestId = requestId
        } else {
            context.coordinator.cancelPendingRequest()
            context.coordinator.currentAssetId = nil
            uiView.pause()
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.cancelPendingRequest()
        uiView.pause()
    }

    final class Coordinator {
        var pendingRequestId: PHImageRequestID?
        var currentAssetId: String?

        func cancelPendingRequest() {
            AssetPlaybackLoader.shared.cancel(pendingRequestId)
            pendingRequestId = nil
        }
    }
}

final class PlayerContainerView: UIView {
    private var player: AVPlayer = AVPlayer()
    private let layerPlayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layerPlayer.player = player
        layerPlayer.videoGravity = .resizeAspect
        self.layer.addSublayer(layerPlayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layerPlayer.frame = self.bounds
    }

    func play(item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func pause() {
        player.pause()
        // Keep item; when re-activated it will be replaced with fresh item
    }

    deinit {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
