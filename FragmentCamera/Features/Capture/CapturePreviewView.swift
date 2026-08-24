import SwiftUI
import UIKit

final class CameraPreviewController: UIViewController {
    var cameraService: CameraService?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        #if !targetEnvironment(simulator)
        guard let previewLayer = cameraService?.previewLayer else { return }
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if !targetEnvironment(simulator)
        cameraService?.previewLayer.frame = view.bounds
        cameraService?.refreshPreviewOrientation()
        #endif
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.cameraService?.previewLayer.frame = self?.view.bounds ?? .zero
            self?.cameraService?.refreshPreviewOrientation()
        })
    }
}

struct CameraPreviewView: UIViewControllerRepresentable {
    let cameraService: CameraService

    func makeUIViewController(context: Context) -> CameraPreviewController {
        let controller = CameraPreviewController()
        controller.cameraService = cameraService
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {
        uiViewController.cameraService = cameraService
    }
}
