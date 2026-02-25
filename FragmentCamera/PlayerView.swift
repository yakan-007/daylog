import SwiftUI
import AVKit
import Photos

struct PlayerView: UIViewControllerRepresentable {
    let asset: PHAsset

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        AudioSessionMode.activatePlayback()
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = false
        controller.player = AVPlayer()
        context.coordinator.showLoading(on: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        AudioSessionMode.activatePlayback()
        if context.coordinator.currentAssetId == asset.localIdentifier { return }
        context.coordinator.currentAssetId = asset.localIdentifier
        context.coordinator.cancelPendingRequest()
        context.coordinator.showLoading(on: uiViewController)

        let options = PHVideoRequestOptions()
        options.deliveryMode = .fastFormat

        AppLog.player.info("player.load.begin asset=\(self.asset.localIdentifier, privacy: .public)")
        let requestId = AssetPlaybackLoader.shared.requestPlayerItem(for: asset, deliveryMode: options.deliveryMode, timeout: 15) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let playerItem):
                    uiViewController.player?.replaceCurrentItem(with: playerItem)
                    uiViewController.player?.play()
                    context.coordinator.hideLoading(on: uiViewController)
                    AppLog.player.info("player.load.success asset=\(self.asset.localIdentifier, privacy: .public)")
                case .failure(let error):
                    context.coordinator.currentAssetId = nil
                    context.coordinator.showLoadingFailure(on: uiViewController)
                    AppLog.player.error("player.load.fail asset=\(self.asset.localIdentifier, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                }
            }
        }
        context.coordinator.pendingRequestId = requestId
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.cancelPendingRequest()
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
    }

    final class Coordinator {
        var pendingRequestId: PHImageRequestID?
        var currentAssetId: String?

        func cancelPendingRequest() {
            AssetPlaybackLoader.shared.cancel(pendingRequestId)
            pendingRequestId = nil
        }

        func showLoading(on controller: AVPlayerViewController) {
            let spinnerTag = 991
            let labelTag = 992
            if controller.view.viewWithTag(spinnerTag) == nil {
                let spinner = UIActivityIndicatorView(style: .large)
                spinner.tag = spinnerTag
                spinner.color = .white
                spinner.translatesAutoresizingMaskIntoConstraints = false
                spinner.startAnimating()
                controller.view.addSubview(spinner)
                NSLayoutConstraint.activate([
                    spinner.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
                    spinner.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor, constant: -12)
                ])
            }
            let label: UILabel
            if let existing = controller.view.viewWithTag(labelTag) as? UILabel {
                label = existing
            } else {
                label = UILabel()
                label.tag = labelTag
                label.textColor = .white
                label.font = .systemFont(ofSize: 15, weight: .semibold)
                label.translatesAutoresizingMaskIntoConstraints = false
                controller.view.addSubview(label)
                if let spinner = controller.view.viewWithTag(spinnerTag) {
                    NSLayoutConstraint.activate([
                        label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
                        label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor)
                    ])
                }
            }
            label.text = "読み込み中..."
        }

        func hideLoading(on controller: AVPlayerViewController) {
            controller.view.viewWithTag(991)?.removeFromSuperview()
            controller.view.viewWithTag(992)?.removeFromSuperview()
        }

        func showLoadingFailure(on controller: AVPlayerViewController) {
            if let label = controller.view.viewWithTag(992) as? UILabel {
                label.text = "動画を読み込めませんでした"
            } else {
                showLoading(on: controller)
                (controller.view.viewWithTag(992) as? UILabel)?.text = "動画を読み込めませんでした"
            }
        }
    }
}
