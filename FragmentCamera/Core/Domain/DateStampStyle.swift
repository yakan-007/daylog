import CoreGraphics
import Foundation

/// タイムスタンプを動画へ反映する時期。
///
/// `playbackOverlay` は元動画を保ち、Vlogish 内の再生と書き出し時にレシピを適用する。
/// `burnOnCapture` は写真アプリなど Vlogish 外でも見える代わりに、撮影後の保存が重くなる。
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

/// 共通の日付スタンプの位置。編集画面のかたまり（`VlogBlockPosition`）と同じ9か所。
/// 並びは画面の見た目どおり（上の行の左から）。
enum DateStampPosition: String, CaseIterable, Codable, Sendable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    static func normalized(_ key: String) -> DateStampPosition {
        DateStampPosition(rawValue: key) ?? .topTrailing
    }

    /// 0: 左、1: 中央、2: 右
    var column: Int {
        switch self {
        case .topLeading, .leading, .bottomLeading: return 0
        case .top, .center, .bottom: return 1
        case .topTrailing, .trailing, .bottomTrailing: return 2
        }
    }

    /// 0: 上、1: 中央、2: 下
    var row: Int {
        switch self {
        case .topLeading, .top, .topTrailing: return 0
        case .leading, .center, .trailing: return 1
        case .bottomLeading, .bottom, .bottomTrailing: return 2
        }
    }

    /// 編集画面のかたまりの位置に直す。
    var blockPosition: VlogBlockPosition {
        VlogBlockPosition(rawValue: row * 3 + column) ?? .topTrailing
    }

    var title: String {
        blockPosition.accessibilityTitle
    }
}

/// 日付の並び順。国や地域で読み方が違うため（10.06 を6月10日と読む地域がある）、
/// 既定は端末の地域に合わせ、設定で変えられる。
enum DateStampDateOrder: String, CaseIterable, Codable, Sendable {
    case yearMonthDay = "ymd"
    case monthDayYear = "mdy"
    case dayMonthYear = "dmy"

    /// 端末の地域の並び。年・月・日の現れる順で判定する。
    static func regional(locale: Locale = .autoupdatingCurrent) -> DateStampDateOrder {
        let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "y/M/d"
        guard let year = pattern.firstIndex(where: { $0 == "y" || $0 == "Y" }),
              let month = pattern.firstIndex(where: { $0 == "M" || $0 == "L" }),
              let day = pattern.firstIndex(of: "d") else {
            return .yearMonthDay
        }
        if year < month && year < day { return .yearMonthDay }
        return month < day ? .monthDayYear : .dayMonthYear
    }

    /// スタンプの日付の書式。
    func datePattern(zeroPadded: Bool) -> String {
        switch self {
        case .yearMonthDay: return zeroPadded ? "yyyy.MM.dd" : "y.M.d"
        case .monthDayYear: return zeroPadded ? "MM.dd.yyyy" : "M.d.y"
        case .dayMonthYear: return zeroPadded ? "dd.MM.yyyy" : "d.M.y"
        }
    }

    /// 年を省いた短い書式（記録画面の "10.06" など）。
    var monthDayPattern: String {
        self == .dayMonthYear ? "dd.MM" : "MM.dd"
    }

    var title: String {
        switch self {
        case .yearMonthDay: return L10n.text("年 月 日")
        case .monthDayYear: return L10n.text("月 日 年")
        case .dayMonthYear: return L10n.text("日 月 年")
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

    /// iPhone の「24時間表示」の設定（と地域）に合わせた表記。
    static func system(locale: Locale = .autoupdatingCurrent) -> DateStampTimeStyle {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        return pattern.contains("a") ? .twelveHour : .twentyFourHour
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
        switch position.column {
        case 0: x = margin
        case 2: x = renderSize.width - margin - width
        default: x = (renderSize.width - width) / 2
        }

        let y: CGFloat
        switch position.row {
        case 0: y = margin
        case 2: y = renderSize.height - margin - height
        default: y = (renderSize.height - height) / 2
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
