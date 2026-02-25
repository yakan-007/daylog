import SwiftUI

struct AppTheme {
    // Brand + semantic colors
    static let accent = Color(hex: 0xFFC857)
    static let onAccent = Color.black
    static let onGlass = Color.white
    static let danger = Color.red
    static let surface = Color.black.opacity(0.24)
    static let surfaceElevated = Color.black.opacity(0.35)
    static let stroke = Color.white.opacity(0.14)

    // Layout tokens
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let radiusS: CGFloat = 10
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20

    // Typography tokens
    static let labelFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 15, weight: .regular)
    static let titleFont = Font.system(size: 20, weight: .bold)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 16
    var shadowOpacity: Double = 0.25
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func glassPanel(radius: CGFloat = 16, shadowOpacity: Double = 0.25) -> some View {
        self.modifier(GlassPanel(radius: radius, shadowOpacity: shadowOpacity))
    }

    func tokenCard(radius: CGFloat = AppTheme.radiusM) -> some View {
        self
            .padding(AppTheme.spacingM)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
