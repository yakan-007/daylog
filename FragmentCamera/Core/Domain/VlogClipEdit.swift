import Foundation

/// 元動画を変更せずに重ねる文字情報。撮影日時・場所の原本とは分離して保存する。
struct VlogClipEdit: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let assetLocalIdentifier: String
    var textOverlays: [VlogTextOverlay]
    var updatedAt: Date

    init(
        version: Int = currentVersion,
        assetLocalIdentifier: String,
        textOverlays: [VlogTextOverlay] = [],
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.assetLocalIdentifier = assetLocalIdentifier
        self.textOverlays = textOverlays
        self.updatedAt = updatedAt
    }

    func normalized(for clipDuration: TimeInterval) -> VlogClipEdit {
        var seenIdentifiers = Set<UUID>()
        let normalizedOverlays = textOverlays.compactMap { overlay -> VlogTextOverlay? in
            guard seenIdentifiers.insert(overlay.id).inserted else { return nil }
            return overlay.normalized(for: clipDuration)
        }
        return VlogClipEdit(
            version: Self.currentVersion,
            assetLocalIdentifier: assetLocalIdentifier,
            textOverlays: normalizedOverlays,
            updatedAt: updatedAt
        )
    }

    func activeTextOverlays(at time: TimeInterval) -> [VlogTextOverlay] {
        textOverlays.filter { $0.timeRange.contains(time) }
    }
}

struct VlogTextOverlay: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var source: VlogTextSource
    var anchor: VlogNormalizedPoint
    var style: VlogTextStyle
    var timeRange: VlogOverlayTimeRange

    init(
        id: UUID = UUID(),
        source: VlogTextSource,
        anchor: VlogNormalizedPoint = .bottomLeading,
        style: VlogTextStyle = .default,
        timeRange: VlogOverlayTimeRange = .entireClip
    ) {
        self.id = id
        self.source = source
        self.anchor = anchor
        self.style = style
        self.timeRange = timeRange
    }

    func normalized(for clipDuration: TimeInterval) -> VlogTextOverlay? {
        guard source.hasVisibleContent,
              let normalizedRange = timeRange.normalized(for: clipDuration) else {
            return nil
        }
        return VlogTextOverlay(
            id: id,
            source: source.normalized,
            anchor: anchor.normalized,
            style: style.normalized,
            timeRange: normalizedRange
        )
    }
}

enum VlogTextSource: Codable, Equatable, Sendable {
    case custom(String)
    case capturedDate(format: VlogDateFormat)
    case capturedTime(format: VlogTimeFormat)
    /// `customName == nil` は撮影時に取得した地名を表示する。
    case place(customName: String?)

    fileprivate var hasVisibleContent: Bool {
        switch self {
        case .custom(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .capturedDate, .capturedTime, .place:
            return true
        }
    }

    fileprivate var normalized: VlogTextSource {
        switch self {
        case .custom(let text):
            return .custom(text)
        case .capturedDate, .capturedTime:
            return self
        case .place(let customName):
            let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .place(customName: trimmed?.isEmpty == false ? trimmed : nil)
        }
    }

    func resolvedPlaceName(capturedPlaceName: String?) -> String? {
        guard case .place(let customName) = self else { return nil }
        return customName ?? capturedPlaceName
    }
}

enum VlogDateFormat: String, CaseIterable, Codable, Sendable {
    case numeric
    case abbreviated
    case full
}

enum VlogTimeFormat: String, CaseIterable, Codable, Sendable {
    case system
    case twelveHour
    case twentyFourHour
}

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

enum VlogFontDesign: String, CaseIterable, Codable, Sendable {
    case standard
    case rounded
    case serif
}

enum VlogFontWeight: String, CaseIterable, Codable, Sendable {
    case regular
    case medium
    case semibold
    case bold
}

enum VlogTextAlignment: String, CaseIterable, Codable, Sendable {
    case leading
    case center
    case trailing
}

struct VlogTextStyle: Codable, Equatable, Sendable {
    var fontDesign: VlogFontDesign
    var fontWeight: VlogFontWeight
    /// 基準サイズに対する倍率。0.5〜2.0へ正規化する。
    var relativeSize: Double
    var alignment: VlogTextAlignment
    var foregroundColor: VlogColor
    var backgroundColor: VlogColor?
    var outlineColor: VlogColor?
    /// 基準文字サイズに対する比率。0〜0.1へ正規化する。
    var outlineWidth: Double

    static let `default` = VlogTextStyle(
        fontDesign: .standard,
        fontWeight: .semibold,
        relativeSize: 1,
        alignment: .leading,
        foregroundColor: .white,
        backgroundColor: nil,
        outlineColor: .black,
        outlineWidth: 0.025
    )

    var normalized: VlogTextStyle {
        VlogTextStyle(
            fontDesign: fontDesign,
            fontWeight: fontWeight,
            relativeSize: relativeSize.finiteValue(or: 1).clamped(to: 0.5...2),
            alignment: alignment,
            foregroundColor: foregroundColor.normalized,
            backgroundColor: backgroundColor?.normalized,
            outlineColor: outlineColor?.normalized,
            outlineWidth: outlineWidth.finiteValue(or: 0).clamped(to: 0...0.1)
        )
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
        finiteValue(or: 0).clamped(to: 0...1)
    }

    func finiteValue(or fallback: Double) -> Double {
        isFinite ? self : fallback
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
