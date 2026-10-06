import UIKit

final class VlogishAppDelegate: NSObject, UIApplicationDelegate {
    /// 撮影は縦固定（CaptureOrientationMode を参照）。
    static let supportedInterfaceOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedInterfaceOrientations
    }
}
