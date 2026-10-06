import Foundation

/// 1本のクリップに対する非破壊編集。元動画は変更せず、再生と書き出しの時に重ねる。
///
/// 編集の中心は「スタンプのかたまり（VlogStampBlock）」ひとつ。日付・時刻・場所と、その下の
/// ひとことを1つにまとめて、位置・大きさ・見た目をまとめて決める。
/// 一度保存したクリップでは、日付表示も共通設定ではなくこのかたまりで描く。
///
/// 機能を足す時の方針:
/// - 新しい編集項目（使う範囲、音を消す、つなぐ時に外す など）はこの型にプロパティとして足す。
/// - 形が変わったら `currentVersion` を上げる（ストアの形式も自動で上がる）。
///   ストアは古い版を読まずに破棄する（リリース前の方針）。
struct VlogClipEdit: Codable, Equatable, Sendable {
    static let currentVersion = 4

    let version: Int
    let assetLocalIdentifier: String
    var block: VlogStampBlock
    /// 撮影時のタイムゾーン。日付・時刻を旅行先の時刻のまま表示するために保持する。
    var sourceTimeZoneIdentifier: String?
    var updatedAt: Date

    init(
        version: Int = currentVersion,
        assetLocalIdentifier: String,
        block: VlogStampBlock = VlogStampBlock(),
        sourceTimeZoneIdentifier: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.assetLocalIdentifier = assetLocalIdentifier
        self.block = block
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        self.updatedAt = updatedAt
    }

    func normalized(for clipDuration: TimeInterval) -> VlogClipEdit {
        VlogClipEdit(
            version: Self.currentVersion,
            assetLocalIdentifier: assetLocalIdentifier,
            block: block.normalized,
            sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Stamp block

/// 日付・時刻・場所・ひとことを上から順に重ねた、1つの文字のかたまり。
///
/// 日付・時刻・場所は1つずつ「出す／出さない」を切り替えるだけ（増やせない）。
/// ひとことは空なら出さない。並び順は `lines` の順で固定。
struct VlogStampBlock: Codable, Equatable, Sendable {
    static let scaleRange: ClosedRange<Double> = 0.5...3.0
    static let maxCaptionLength = 80

    var showsDate: Bool
    var showsTime: Bool
    var showsPlace: Bool
    /// 場所の表示名。撮影時の地名を初期値に、手で書き換えられる。
    var placeName: String
    /// 日付・時刻の下に添えるひとこと。
    var caption: String
    /// 日付・時刻の書式（作った時点の共通設定を保持する）。
    var dateFormat: String
    var zeroPadded: Bool
    var timeStyle: DateStampTimeStyle
    /// かたまりの中心。動画そのものに対する 0...1。端の値は描画時に余白の内側へ寄る。
    var anchor: VlogNormalizedPoint
    var style: VlogTextStylePreset
    /// 基準の大きさに対する倍率。
    var scale: Double
    /// ひとことを日付・時刻の上に置くか下に置くか。
    var captionPlacement: VlogCaptionPlacement
    /// 2秒ほどで消す（共通設定の「2秒後にフェードアウト」と同じ）。
    var fadesOut: Bool

    init(
        showsDate: Bool = false,
        showsTime: Bool = false,
        showsPlace: Bool = false,
        placeName: String = "",
        caption: String = "",
        dateFormat: String = DateStampFormatter.compactDateTime,
        zeroPadded: Bool = false,
        timeStyle: DateStampTimeStyle = .twentyFourHour,
        anchor: VlogNormalizedPoint = .center,
        style: VlogTextStylePreset = .simple,
        scale: Double = 1,
        captionPlacement: VlogCaptionPlacement = .below,
        fadesOut: Bool = false
    ) {
        self.showsDate = showsDate
        self.showsTime = showsTime
        self.showsPlace = showsPlace
        self.placeName = placeName
        self.caption = caption
        self.dateFormat = dateFormat
        self.zeroPadded = zeroPadded
        self.timeStyle = timeStyle
        self.anchor = anchor
        self.style = style
        self.scale = scale
        self.captionPlacement = captionPlacement
        self.fadesOut = fadesOut
    }

    // 項目を足しても保存済みデータを読めるよう、足した項目は「無ければ既定値」で読む。
    private enum CodingKeys: String, CodingKey {
        case showsDate, showsTime, showsPlace, placeName, caption
        case dateFormat, zeroPadded, timeStyle, anchor, style, scale
        case captionPlacement, fadesOut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsDate = try container.decode(Bool.self, forKey: .showsDate)
        showsTime = try container.decode(Bool.self, forKey: .showsTime)
        showsPlace = try container.decode(Bool.self, forKey: .showsPlace)
        placeName = try container.decode(String.self, forKey: .placeName)
        caption = try container.decode(String.self, forKey: .caption)
        dateFormat = try container.decode(String.self, forKey: .dateFormat)
        zeroPadded = try container.decode(Bool.self, forKey: .zeroPadded)
        timeStyle = try container.decode(DateStampTimeStyle.self, forKey: .timeStyle)
        anchor = try container.decode(VlogNormalizedPoint.self, forKey: .anchor)
        style = try container.decode(VlogTextStylePreset.self, forKey: .style)
        scale = try container.decode(Double.self, forKey: .scale)
        captionPlacement = try container.decodeIfPresent(VlogCaptionPlacement.self, forKey: .captionPlacement) ?? .below
        fadesOut = try container.decodeIfPresent(Bool.self, forKey: .fadesOut) ?? false
    }

    var hasCaption: Bool {
        !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasPlace: Bool {
        showsPlace && !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 何も表示しないか。
    var isEmpty: Bool {
        !showsDate && !showsTime && !hasPlace && !hasCaption
    }

    /// 左寄せ・中央・右寄せ。かたまりを置いた位置から決める（左端なら左寄せ）。
    var alignment: VlogTextAlignment {
        if anchor.x < 0.34 { return .leading }
        if anchor.x > 0.66 { return .trailing }
        return .center
    }

    var normalized: VlogStampBlock {
        var copy = self
        copy.caption = String(caption.prefix(Self.maxCaptionLength))
        copy.placeName = String(placeName.prefix(Self.maxCaptionLength))
        copy.anchor = anchor.normalized
        copy.scale = scale.isFinite
            ? min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            : 1
        return copy
    }
}

enum VlogCaptionPlacement: String, CaseIterable, Codable, Sendable {
    case above
    case below

    var title: String {
        switch self {
        case .above: return L10n.text("日付の上")
        case .below: return L10n.text("日付の下")
        }
    }
}

/// 共通設定の「2秒後にフェードアウト」と同じ見え方（2秒表示して0.5秒で消える）。
enum VlogFadeTiming {
    static let visibleDuration: TimeInterval = 2.0
    static let fadeDuration: TimeInterval = 0.5
    static var totalDuration: TimeInterval { visibleDuration + fadeDuration }
}

enum VlogTextAlignment: String, Codable, Sendable {
    case leading
    case center
    case trailing
}

// MARK: - Style presets

/// 文字の見た目。新しい見た目は case を足して `spec` に描き方を書くだけで、
/// 編集画面・再生・書き出しのすべてに反映される。
enum VlogTextStylePreset: String, CaseIterable, Codable, Sendable {
    case simple
    case band
    case bubble

    var title: String {
        switch self {
        case .simple: return L10n.text("シンプル")
        case .band: return L10n.text("帯")
        case .bubble: return L10n.text("ぷっくり")
        }
    }

    var spec: VlogTextStyleSpec {
        switch self {
        case .simple:
            return VlogTextStyleSpec(
                weight: .semibold,
                isRounded: false,
                foreground: .white,
                background: nil,
                outline: .black,
                outlineRadiusRatio: 0.12,
                outlineOpacity: 0.6,
                horizontalPaddingRatio: 0,
                verticalPaddingRatio: 0,
                cornerRadiusRatio: 0
            )
        case .band:
            return VlogTextStyleSpec(
                weight: .bold,
                isRounded: false,
                foreground: VlogColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1),
                background: VlogColor(red: 1, green: 1, blue: 1, alpha: 0.94),
                outline: nil,
                outlineRadiusRatio: 0,
                outlineOpacity: 0,
                horizontalPaddingRatio: 0.45,
                verticalPaddingRatio: 0.18,
                cornerRadiusRatio: 0.2
            )
        case .bubble:
            return VlogTextStyleSpec(
                weight: .heavy,
                isRounded: true,
                foreground: .white,
                background: nil,
                outline: .black,
                outlineRadiusRatio: 0.1,
                outlineOpacity: 1,
                horizontalPaddingRatio: 0,
                verticalPaddingRatio: 0,
                cornerRadiusRatio: 0
            )
        }
    }
}

/// プラットフォームに依存しない描き方の定義。SwiftUI と Core Animation の両方がこれを読む。
struct VlogTextStyleSpec: Equatable, Sendable {
    enum Weight: Sendable {
        case semibold
        case bold
        case heavy
    }

    let weight: Weight
    let isRounded: Bool
    let foreground: VlogColor
    let background: VlogColor?
    /// 文字の周りのぼかした縁取り（影で表現する）。
    let outline: VlogColor?
    /// 文字サイズに対する縁取りの半径。
    let outlineRadiusRatio: Double
    let outlineOpacity: Double
    /// 文字サイズに対する背景の余白。
    let horizontalPaddingRatio: Double
    let verticalPaddingRatio: Double
    let cornerRadiusRatio: Double
}

// MARK: - Geometry

struct VlogNormalizedPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    static let topLeading = VlogNormalizedPoint(x: 0.08, y: 0.08)
    static let topTrailing = VlogNormalizedPoint(x: 0.92, y: 0.08)
    static let center = VlogNormalizedPoint(x: 0.5, y: 0.5)
    static let bottomLeading = VlogNormalizedPoint(x: 0.08, y: 0.92)
    static let bottomTrailing = VlogNormalizedPoint(x: 0.92, y: 0.92)

    var normalized: VlogNormalizedPoint {
        VlogNormalizedPoint(x: x.unitValue, y: y.unitValue)
    }
}

/// かたまりを置く9か所（上・中・下 × 左・中央・右）。
/// 端は 0 / 1 を入れ、実際の位置は `VlogTextLayout` が余白の内側に収める。
enum VlogBlockPosition: Int, CaseIterable, Sendable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    var anchor: VlogNormalizedPoint {
        let column = rawValue % 3
        let row = rawValue / 3
        return VlogNormalizedPoint(x: Double(column) * 0.5, y: Double(row) * 0.5)
    }

    /// 手で動かした後など、9か所のどれにも当たらない時は nil。
    static func matching(_ anchor: VlogNormalizedPoint) -> VlogBlockPosition? {
        allCases.first { position in
            abs(position.anchor.x - anchor.x) < 0.001 && abs(position.anchor.y - anchor.y) < 0.001
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .topLeading: return L10n.text("左上")
        case .top: return L10n.text("上")
        case .topTrailing: return L10n.text("右上")
        case .leading: return L10n.text("左")
        case .center: return L10n.text("中央")
        case .trailing: return L10n.text("右")
        case .bottomLeading: return L10n.text("左下")
        case .bottom: return L10n.text("下")
        case .bottomTrailing: return L10n.text("右下")
        }
    }
}

struct VlogOverlayTimeRange: Codable, Equatable, Sendable {
    var start: TimeInterval
    /// `nil` はクリップ末尾まで。
    var end: TimeInterval?

    static let entireClip = VlogOverlayTimeRange(start: 0, end: nil)

    func normalized(for clipDuration: TimeInterval) -> VlogOverlayTimeRange? {
        guard clipDuration.isFinite, clipDuration > 0, start.isFinite else { return nil }
        let normalizedStart = min(max(start, 0), clipDuration)
        let requestedEnd = end ?? clipDuration
        guard requestedEnd.isFinite else { return nil }
        let normalizedEnd = min(max(requestedEnd, 0), clipDuration)
        guard normalizedEnd > normalizedStart else { return nil }
        return VlogOverlayTimeRange(start: normalizedStart, end: normalizedEnd)
    }

    func contains(_ time: TimeInterval) -> Bool {
        guard time.isFinite, time >= start else { return false }
        return end.map { time < $0 } ?? true
    }
}

struct VlogColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = VlogColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = VlogColor(red: 0, green: 0, blue: 0, alpha: 1)

    var normalized: VlogColor {
        VlogColor(
            red: red.unitValue,
            green: green.unitValue,
            blue: blue.unitValue,
            alpha: alpha.unitValue
        )
    }
}

private extension Double {
    var unitValue: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}
