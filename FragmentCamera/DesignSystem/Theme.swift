import SwiftUI
import UIKit

/// 映像を主役にしたミニマルなテーマ。
enum DaylogModernTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let elevated = Color(uiColor: .secondarySystemGroupedBackground)
    static let foreground = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)
    static let divider = Color(uiColor: .separator)
    static let accent = Color(uiColor: .systemBlue)
    static let accentSoft = Color(uiColor: .systemBlue).opacity(0.11)
    static let danger = Color(uiColor: .systemRed)
    static let mediaPlaceholder = Color(uiColor: .secondarySystemFill)

    /// 映像上ではブランド色より、カメラとして認識しやすい選択色を優先する。
    static let captureAccent = Color(uiColor: .systemYellow)
    static let recording = Color(uiColor: .systemRed)

    static let pagePadding: CGFloat = 16
    static let mediaRadius: CGFloat = 16
}

struct DaylogModernBackground: View {
    var body: some View {
        DaylogModernTheme.background
            .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
