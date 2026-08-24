import CoreGraphics

/// タイムスタンプを動画へ反映する時期。
///
/// `playbackOverlay` は元動画を保ち、daylog 内の再生と書き出し時にレシピを適用する。
/// `burnOnCapture` は写真アプリなど daylog 外でも見える代わりに、撮影後の保存が重くなる。
enum StampRenderingMode: String, CaseIterable, Codable, Sendable {
    case playbackOverlay
    case burnOnCapture

    static func normalized(_ key: String) -> StampRenderingMode {
        StampRenderingMode(rawValue: key) ?? .playbackOverlay
    }

    var title: String {
        switch self {
        case .playbackOverlay: return L10n.text("再生時")
        case .burnOnCapture: return L10n.text("撮影時")
        }
    }

    var explanation: String {
        switch self {
        case .playbackOverlay:
            return L10n.text("元動画を残し、アプリ内の再生と書き出し時に現在の設定でスタンプを重ねます。後から変更できます。")
        case .burnOnCapture:
            return L10n.text("写真アプリでも見えるよう撮影直後に焼き込みます。アプリ内では現在の設定で表示・書き出しできます。")
        }
    }
}

enum DateStampPosition: String, CaseIterable, Codable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case center

    static func normalized(_ key: String) -> DateStampPosition {
        DateStampPosition(rawValue: key) ?? .topTrailing
    }

    var title: String {
        switch self {
        case .topLeading: return L10n.text("左上")
        case .topTrailing: return L10n.text("右上")
        case .bottomLeading: return L10n.text("左下")
        case .bottomTrailing: return L10n.text("右下")
        case .center: return L10n.text("中央")
        }
    }
}

enum DateStampElement: String, CaseIterable, Codable, Sendable {
    case date
    case time
    case place

    var title: String {
        switch self {
        case .date: return L10n.text("日付")
        case .time: return L10n.text("時刻")
        case .place: return L10n.text("場所")
        }
    }

    var systemImage: String {
        switch self {
        case .date: return "calendar"
        case .time: return "clock"
        case .place: return "location"
        }
    }
}

/// 表示位置とは独立した時刻表記。位置を変えても文字列の形式は変えない。
enum DateStampTimeStyle: String, CaseIterable, Codable, Sendable {
    case twelveHour
    case twentyFourHour

    static func normalized(_ key: String) -> DateStampTimeStyle {
        DateStampTimeStyle(rawValue: key) ?? .twentyFourHour
    }

    var title: String {
        switch self {
        case .twelveHour: return L10n.text("12時間")
        case .twentyFourHour: return L10n.text("24時間")
        }
    }

    var example: String {
        switch self {
        case .twelveHour: return "6:39 PM"
        case .twentyFourHour: return "18:39"
        }
    }
}

enum DateStampStyle {
    static let small = "small"
    static let medium = "medium"
    static let large = "large"

    static let allSizes = [small, medium, large]

    static func normalizedSizeKey(_ key: String) -> String {
        allSizes.contains(key) ? key : medium
    }

    static func scale(for key: String) -> CGFloat {
        switch normalizedSizeKey(key) {
        case small: return 0.82
        case large: return 1.24
        default: return 1.0
        }
    }

    static func fontSize(
        for renderSize: CGSize,
        sizeKey: String
    ) -> CGFloat {
        let shortSide = min(renderSize.width, renderSize.height)
        return max(14, shortSide * 0.052 * scale(for: sizeKey))
    }

    static func margin(for renderSize: CGSize) -> CGFloat {
        min(renderSize.width, renderSize.height) * 0.05
    }

    static func aspectFitFrame(
        contentAspectRatio: CGFloat,
        in containerSize: CGSize
    ) -> CGRect {
        let safeAspectRatio = max(contentAspectRatio, 0.01)
        let containerAspectRatio = containerSize.width / max(containerSize.height, 1)
        if containerAspectRatio > safeAspectRatio {
            let width = containerSize.height * safeAspectRatio
            return CGRect(
                x: (containerSize.width - width) / 2,
                y: 0,
                width: width,
                height: containerSize.height
            )
        }
        let height = containerSize.width / safeAspectRatio
        return CGRect(
            x: 0,
            y: (containerSize.height - height) / 2,
            width: containerSize.width,
            height: height
        )
    }

    static func textFrame(
        for renderSize: CGSize,
        sizeKey: String,
        position: DateStampPosition,
        lineCount: Int,
        preferredWidth: CGFloat? = nil
    ) -> CGRect {
        let margin = margin(for: renderSize)
        let fontSize = fontSize(for: renderSize, sizeKey: sizeKey)
        let height = fontSize * 1.35 * CGFloat(max(lineCount, 1))
        let availableWidth = max(renderSize.width - (margin * 2), 1)
        let width = min(max(preferredWidth ?? availableWidth, fontSize), availableWidth)

        let x: CGFloat
        switch position {
        case .topLeading, .bottomLeading:
            x = margin
        case .topTrailing, .bottomTrailing:
            x = renderSize.width - margin - width
        case .center:
            x = (renderSize.width - width) / 2
        }

        switch position {
        case .topLeading, .topTrailing:
            return CGRect(x: x, y: margin, width: width, height: height)
        case .bottomLeading, .bottomTrailing:
            return CGRect(
                x: x,
                y: renderSize.height - margin - height,
                width: width,
                height: height
            )
        case .center:
            return CGRect(
                x: x,
                y: (renderSize.height - height) / 2,
                width: width,
                height: height
            )
        }
    }
}
