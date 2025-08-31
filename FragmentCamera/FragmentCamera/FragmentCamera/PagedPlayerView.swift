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

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if isActive {
            // Load and play
            let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    guard let item = item else { return }
                    uiView.play(item: item)
                }
            }
        } else {
            uiView.pause()
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
}
