import SwiftUI

@main
struct FragmentCameraApp: App {
    // Register the AppDelegate to manage app-level events like orientation lock.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
