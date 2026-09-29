import Foundation

/// Public-facing product identity. Keeping these values in one place prevents
/// the App Store name, Photos album, and in-app copy from drifting apart.
enum AppIdentity {
    static let brandName = "Vlogish"
    static let homeScreenName = "Vlogish"
    static let photoAlbumName = "Vlogish"
}

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale.autoupdatingCurrent,
            arguments: arguments
        )
    }
}
