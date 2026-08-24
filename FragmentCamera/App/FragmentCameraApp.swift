import SwiftUI

@main
struct FragmentCameraApp: App {
    @UIApplicationDelegateAdaptor(DaylogAppDelegate.self) private var appDelegate
    @StateObject private var container = DaylogContainer()

    var body: some Scene {
        WindowGroup {
            ContentView(
                captureViewModel: container.captureViewModel,
                libraryViewModel: container.libraryViewModel,
                settingsViewModel: container.settingsViewModel,
                makeLibraryClipBrowser: container.makeLibraryClipBrowser
            )
        }
    }
}
