import UIKit

final class DaylogAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedInterfaceOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedInterfaceOrientations
    }
}

@MainActor
enum DaylogOrientationController {
    static func apply(_ mode: CaptureOrientationMode) {
        let mask: UIInterfaceOrientationMask = switch mode {
        case .portrait:
            .portrait
        case .landscape:
            .landscape
        }
        DaylogAppDelegate.supportedInterfaceOrientations = mask

        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState != .unattached }
        for scene in scenes {
            scene.windows.forEach { window in
                requestSupportedOrientationsUpdate(from: window.rootViewController)
            }
            scene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: mask
                )
            ) { error in
                AppLog.capture.warning(
                    "orientation.update.fail mode=\(mode.rawValue, privacy: .public) reason=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    private static func requestSupportedOrientationsUpdate(
        from viewController: UIViewController?
    ) {
        guard let viewController else { return }
        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        if let presented = viewController.presentedViewController {
            requestSupportedOrientationsUpdate(from: presented)
        }
    }
}
