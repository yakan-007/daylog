import SwiftUI
import AVKit
import Photos

struct DayPlayerView: UIViewControllerRepresentable {
    let assets: [PHAsset]

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = false
        controller.player = AVQueuePlayer()
        loadItems(into: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    private func loadItems(into controller: AVPlayerViewController) {
        let queue = controller.player as? AVQueuePlayer
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        var items: [AVPlayerItem] = []
        let group = DispatchGroup()
        for asset in assets {
            group.enter()
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                if let item = playerItem { items.append(item) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let sorted = items // order preserved by request order
            for item in sorted { queue?.insert(item, after: nil) }
            controller.player?.play()
        }
    }
}

