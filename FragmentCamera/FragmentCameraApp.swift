import SwiftUI

@main
struct FragmentCameraApp: App {
    // Register the AppDelegate to manage app-level events like orientation lock.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var container = DaylogContainer()

    var body: some Scene {
        WindowGroup {
            ContentView(
                captureViewModel: container.captureViewModel,
                libraryViewModel: container.libraryViewModel,
                settingsViewModel: container.settingsViewModel,
                makePlaybackSingle: container.makePlaybackSingle,
                makePlaybackDay: container.makePlaybackDay
            )
        }
    }
}
