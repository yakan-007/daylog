import Foundation
import OSLog

enum AppLog {
    // Choose a stable subsystem; fall back if bundle id is nil.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "FragmentCamera"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let permission = Logger(subsystem: subsystem, category: "permission")
    static let location = Logger(subsystem: subsystem, category: "location")
}

