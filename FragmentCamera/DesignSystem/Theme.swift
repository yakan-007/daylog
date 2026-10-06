import SwiftUI
import UIKit

/// 映像を主役にしたミニマルなテーマ。
enum VlogishModernTheme {
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

    static let pagePadding: CGFloat = 16
    static let mediaRadius: CGFloat = 16
}

struct VlogishModernBackground: View {
    var body: some View {
        VlogishModernTheme.background
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

/// カメラロール（時間軸）用のトークン。白に近い地と黒、差し色は1色だけ。
/// ライブラリは常にライトで表示するため、固定色で定義する。
enum RollTheme {
    static let ground = Color(hex: 0xF5F5F2)
    static let ink = Color(hex: 0x111111)
    /// 地の上で 4.5:1 を満たす補助テキスト色。
    static let secondary = Color(hex: 0x6E6E6A)
    static let hairline = Color(hex: 0xDEDED9)
    static let rowLine = Color(hex: 0xE6E6E1)
    static let dashed = Color(hex: 0xBDBDB7)
    static let fill = Color(hex: 0xE9E9E4)
    static let placeholder = Color(hex: 0xDCDCD6)
    static let accent = Color(hex: 0xFF5B14)

    static let pagePadding: CGFloat = 20

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Dynamic Type

/// 固定ptの見た目を基準に、端末の文字サイズ設定に合わせて拡大するフォント。
/// レイアウトが崩れないよう、拡大率に上限を設ける。
struct RollScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let baseSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maxScale: CGFloat

    init(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design,
        maxScale: CGFloat
    ) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: RollScaledFont.textStyle(for: size))
        self.baseSize = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale
    }

    func body(content: Content) -> some View {
        content.font(.system(
            size: min(max(scaledSize, baseSize * 0.8), baseSize * maxScale),
            weight: weight,
            design: design
        ))
    }

    /// 大きな数字は拡大幅の小さい文字スタイルに合わせる。
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<17: return .subheadline
        case ..<22: return .body
        case ..<34: return .title2
        default: return .largeTitle
        }
    }
}

extension View {
    /// 等幅（日付スタンプ・時刻・数字）。
    func rollMono(_ size: CGFloat, _ weight: Font.Weight = .regular, maxScale: CGFloat = 1.8) -> some View {
        modifier(RollScaledFont(size: size, weight: weight, design: .monospaced, maxScale: maxScale))
    }

    /// 本文（日本語のラベル）。
    func rollText(_ size: CGFloat, _ weight: Font.Weight = .regular, maxScale: CGFloat = 1.8) -> some View {
        modifier(RollScaledFont(size: size, weight: weight, design: .default, maxScale: maxScale))
    }
}
