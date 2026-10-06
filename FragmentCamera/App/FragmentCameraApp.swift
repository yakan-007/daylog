import SwiftUI

@main
struct VlogishApp: App {
    @UIApplicationDelegateAdaptor(VlogishAppDelegate.self) private var appDelegate
    @StateObject private var container = VlogishContainer()

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
