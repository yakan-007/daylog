import SwiftUI

struct AppTheme {
    static let accent = Color(hex: 0xFFC857)
    static let onAccent = Color.black
    static let onGlass = Color.white
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
}
