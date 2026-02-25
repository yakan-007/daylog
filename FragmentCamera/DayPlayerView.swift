import SwiftUI
import AVKit
import Photos
import UIKit

struct DayPlayerView: UIViewControllerRepresentable {
    let assets: [PHAsset]

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        AudioSessionMode.activatePlayback()
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = false
        controller.player = AVQueuePlayer()
        loadItems(into: controller, coordinator: context.coordinator)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.cleanup()
        uiViewController.player?.pause()
        if let q = uiViewController.player as? AVQueuePlayer {
            q.removeAllItems()
        } else {
            uiViewController.player?.replaceCurrentItem(with: nil)
        }
    }

    private func loadItems(into controller: AVPlayerViewController, coordinator: Coordinator) {
        let queue = controller.player as? AVQueuePlayer
        let deliveryMode: PHVideoRequestOptionsDeliveryMode = .fastFormat

        guard !assets.isEmpty else { return }
        coordinator.cancelPendingRequests()
        showLoading(on: controller)

        // 1) Prioritize first clip so playback can start quickly.
        let firstAsset = assets[0]
        AppLog.player.info("player.load.begin asset=\(firstAsset.localIdentifier, privacy: .public)")
        let firstId = AssetPlaybackLoader.shared.requestPlayerItem(for: firstAsset, deliveryMode: deliveryMode, timeout: 15) { result in
            DispatchQueue.main.async {
                guard case .success(let item) = result else {
                    self.showLoadingFailure(on: controller)
                    if case .failure(let error) = result {
                        AppLog.player.error("player.load.fail asset=\(firstAsset.localIdentifier, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                queue?.insert(item, after: nil)
                controller.player?.play()
                self.hideLoading(on: controller)
                coordinator.hidePlaybackEnded(on: controller)
                coordinator.observePlaybackEnd(player: queue, controller: controller)
                AppLog.player.info("player.load.success asset=\(firstAsset.localIdentifier, privacy: .public)")
            }
        }
        coordinator.track(requestId: firstId)

        // 2) Load the rest in parallel and enqueue in order.
        guard assets.count > 1 else { return }
        let collectQueue = DispatchQueue(label: "DayPlayerView.ItemCollect")
        var orderedItems: [AVPlayerItem?] = Array(repeating: nil, count: assets.count - 1)
        let group = DispatchGroup()
        for (index, asset) in assets.dropFirst().enumerated() {
            group.enter()
            let requestId = AssetPlaybackLoader.shared.requestPlayerItem(for: asset, deliveryMode: deliveryMode, timeout: 15) { result in
                if case .success(let item) = result {
                    collectQueue.sync { orderedItems[index] = item }
                } else if case .failure(let error) = result {
                    AppLog.player.error("player.load.fail asset=\(asset.localIdentifier, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                }
                group.leave()
            }
            coordinator.track(requestId: requestId)
        }
        group.notify(queue: .main) {
            let items = collectQueue.sync { orderedItems.compactMap { $0 } }
            for item in items { queue?.insert(item, after: nil) }
        }

    }

    final class Coordinator {
        private var requestIds: [PHImageRequestID] = []
        private var endObserver: NSObjectProtocol?

        func track(requestId: PHImageRequestID) {
            requestIds.append(requestId)
        }

        func cancelPendingRequests() {
            for id in requestIds {
                AssetPlaybackLoader.shared.cancel(id)
            }
            requestIds.removeAll()
        }

        func observePlaybackEnd(player: AVQueuePlayer?, controller: AVPlayerViewController) {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: nil,
                queue: .main
            ) { [weak player, weak controller, weak self] _ in
                guard let player, let controller, let self else { return }
                if player.items().isEmpty {
                    self.showPlaybackEnded(on: controller)
                }
            }
        }

        func cleanup() {
            cancelPendingRequests()
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }

        func hidePlaybackEnded(on controller: AVPlayerViewController) {
            controller.view.viewWithTag(993)?.removeFromSuperview()
        }

        private func showPlaybackEnded(on controller: AVPlayerViewController) {
            let endedTag = 993
            guard controller.view.viewWithTag(endedTag) == nil else { return }

            let label = UILabel()
            label.tag = endedTag
            label.text = "再生が終了しました"
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            label.font = .systemFont(ofSize: 16, weight: .semibold)
            label.textAlignment = .center
            label.layer.cornerRadius = 10
            label.layer.masksToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false

            controller.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
                label.heightAnchor.constraint(equalToConstant: 40)
            ])
        }
    }

    private func showLoading(on controller: AVPlayerViewController) {
        let spinnerTag = 991
        let labelTag = 992
        if controller.view.viewWithTag(spinnerTag) != nil { return }
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.tag = spinnerTag
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        let label = UILabel()
        label.tag = labelTag
        label.text = "読み込み中..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        controller.view.addSubview(spinner)
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
            label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor)
        ])
    }

    private func hideLoading(on controller: AVPlayerViewController) {
        controller.view.viewWithTag(991)?.removeFromSuperview()
        controller.view.viewWithTag(992)?.removeFromSuperview()
    }

    private func showLoadingFailure(on controller: AVPlayerViewController) {
        let labelTag = 992
        if let label = controller.view.viewWithTag(labelTag) as? UILabel {
            label.text = "動画を読み込めませんでした"
        }
    }
}
