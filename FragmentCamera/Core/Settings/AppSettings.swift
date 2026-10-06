import Foundation

struct DateStampSettings: Equatable, Sendable {
    var isEnabled: Bool
    var format: String
    var isZeroPadded: Bool
    var timeStyle: DateStampTimeStyle
    var sizeKey: String
    var position: DateStampPosition
    var elements: Set<DateStampElement>
    var fadesOut: Bool
}

extension DateStampSettings {
    func applying(
        _ visibilityOverride: VideoStampVisibilityOverride?
    ) -> DateStampSettings {
        guard let visibilityOverride else { return self }
        var resolved = self
        resolved.elements.subtract(visibilityOverride.hiddenElements)
        if visibilityOverride.hidesStamp || resolved.elements.isEmpty {
            resolved.isEnabled = false
        }
        return resolved
    }

    func shouldResolvePlaceName(
        storedPlaceName: String?,
        hasAssetLocation: Bool
    ) -> Bool {
        guard isEnabled,
              elements.contains(.place),
              hasAssetLocation else { return false }
        return storedPlaceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true
    }

    /// 動画固有の撮影情報は残し、見た目だけを現在の設定に差し替える。
    func displayContext(
        basedOn base: VideoPostProcessContext,
        storageMode: VideoStorageMode? = nil
    ) -> VideoPostProcessContext? {
        guard isEnabled else { return nil }
        return recordingContext(
            capturedAt: base.stampDate,
            placeName: base.placeName,
            timeZoneIdentifier: base.timeZoneIdentifier,
            storageMode: storageMode ?? base.storageMode
        )
    }

    /// 撮影時に保存する素材情報と、その時点の表示設定を一度だけ組み立てる。
    /// スタンプ非表示でも容量最適化や後編集に必要なコンテキストは保持する。
    func recordingContext(
        capturedAt: Date,
        placeName: String?,
        timeZoneIdentifier: String,
        storageMode: VideoStorageMode
    ) -> VideoPostProcessContext {
        VideoPostProcessContext(
            stampEnabled: isEnabled,
            stampDate: capturedAt,
            format: format,
            zeroPadded: isZeroPadded,
            timeStyle: timeStyle,
            sizeKey: sizeKey,
            position: position,
            elements: elements,
            fadesOut: fadesOut,
            placeName: placeName,
            timeZoneIdentifier: timeZoneIdentifier,
            storageMode: storageMode
        )
    }

    func displayContext(
        capturedAt: Date,
        placeName: String?,
        timeZoneIdentifier: String,
        storageMode: VideoStorageMode
    ) -> VideoPostProcessContext? {
        guard isEnabled else { return nil }
        return recordingContext(
            capturedAt: capturedAt,
            placeName: placeName,
            timeZoneIdentifier: timeZoneIdentifier,
            storageMode: storageMode
        )
    }
}

/// UserDefaults のキーと既定値を一元管理する。
///
/// 画面ごとに `@AppStorage` を持つと、キー名や既定値がずれやすいため、
/// 永続設定へのアクセスはこの型を経由する。
final class VlogishSettingsStore {
    private enum Key {
        static let stampEnabled = "isDateStampEnabled"
        static let stampFormat = "dateStampFormat"
        static let stampDateOrder = "dateStampDateOrder"
        static let stampZeroPadded = "dateStampZeroPadded"
        static let stampTimeStyle = "dateStampTimeStyle"
        static let stampSize = "dateStampSize"
        static let stampPosition = "dateStampPosition"
        static let stampShowsDate = "dateStampShowsDate"
        static let stampShowsTime = "dateStampShowsTime"
        static let stampShowsPlace = "dateStampShowsPlace"
        static let stampFadesOut = "dateStampFadesOut"
        static let stampRenderingMode = "dateStampRenderingMode"
        static let videoStorageMode = "videoStorageMode"
        static let locationCaptureEnabled = "isLocationCaptureEnabled"
        static let selectedCaptureDuration = "selectedCaptureDuration"
        static let hasSeenCaptureIntroCard = "hasSeenCaptureIntroCard"
        static let hasSeenCaptureCoach = "hasSeenCaptureCoach"
    }

    private enum DefaultValue {
        static let stampEnabled = true
        static let stampFormat = DateStampFormatter.compactDateTime
        static let stampZeroPadded = false
        static let stampTimeStyle = DateStampTimeStyle.twentyFourHour
        static let stampSize = DateStampStyle.medium
        static let stampPosition = DateStampPosition.topTrailing
        static let stampElements: Set<DateStampElement> = [.date, .time]
        static let stampFadesOut = true
        static let stampRenderingMode = StampRenderingMode.playbackOverlay
        static let videoStorageMode = VideoStorageMode.standard
        static let locationCaptureEnabled = false
        static let selectedCaptureDuration = CaptureDurationPolicy.defaultValue
        static let hasSeenCaptureIntroCard = false
        static let hasSeenCaptureCoach = false
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 撮影・再生・書き出しで使う、いまの日付スタンプ設定。
    ///
    /// 世界中で読み違えないよう、日付の並びは地域（または設定）に合わせ、数字は常に0でそろえる。
    /// 時刻は iPhone の12時間／24時間の設定に従う。
    var dateStampSettings: DateStampSettings {
        get {
            DateStampSettings(
                isEnabled: stampEnabled,
                format: stampDateOrder.rawValue,
                isZeroPadded: true,
                timeStyle: DateStampTimeStyle.system(),
                sizeKey: stampSize,
                position: stampPosition,
                elements: stampElements,
                fadesOut: stampFadesOut
            )
        }
        set {
            // 日付の並び・0そろえ・時刻表記は上の読み取りで決まるので、ここでは保存しない。
            stampEnabled = newValue.isEnabled
            stampSize = newValue.sizeKey
            stampPosition = newValue.position
            stampElements = newValue.elements
            stampFadesOut = newValue.fadesOut
        }
    }

    var stampEnabled: Bool {
        get { bool(forKey: Key.stampEnabled, default: DefaultValue.stampEnabled) }
        set { defaults.set(newValue, forKey: Key.stampEnabled) }
    }

    var stampFormat: String {
        get {
            let stored = defaults.string(forKey: Key.stampFormat) ?? DefaultValue.stampFormat
            return stored == DateStampFormatter.compactDateTime
                ? stored
                : DefaultValue.stampFormat
        }
        set {
            let normalized = newValue == DateStampFormatter.compactDateTime
                ? newValue
                : DefaultValue.stampFormat
            defaults.set(normalized, forKey: Key.stampFormat)
        }
    }

    /// 利用者が選んだ日付の並び。nil なら端末の地域に合わせる。
    var stampDateOrderOverride: DateStampDateOrder? {
        get { defaults.string(forKey: Key.stampDateOrder).flatMap(DateStampDateOrder.init(rawValue:)) }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Key.stampDateOrder)
            } else {
                defaults.removeObject(forKey: Key.stampDateOrder)
            }
        }
    }

    /// 実際に使う日付の並び。
    var stampDateOrder: DateStampDateOrder {
        stampDateOrderOverride ?? DateStampDateOrder.regional()
    }

    var stampZeroPadded: Bool {
        get { bool(forKey: Key.stampZeroPadded, default: DefaultValue.stampZeroPadded) }
        set { defaults.set(newValue, forKey: Key.stampZeroPadded) }
    }

    var stampTimeStyle: DateStampTimeStyle {
        get {
            DateStampTimeStyle.normalized(
                defaults.string(forKey: Key.stampTimeStyle)
                    ?? DefaultValue.stampTimeStyle.rawValue
            )
        }
        set { defaults.set(newValue.rawValue, forKey: Key.stampTimeStyle) }
    }

    var stampSize: String {
        get {
            DateStampStyle.normalizedSizeKey(
                defaults.string(forKey: Key.stampSize) ?? DefaultValue.stampSize
            )
        }
        set { defaults.set(DateStampStyle.normalizedSizeKey(newValue), forKey: Key.stampSize) }
    }

    var stampPosition: DateStampPosition {
        get {
            DateStampPosition.normalized(
                defaults.string(forKey: Key.stampPosition)
                    ?? DefaultValue.stampPosition.rawValue
            )
        }
        set { defaults.set(newValue.rawValue, forKey: Key.stampPosition) }
    }

    var stampElements: Set<DateStampElement> {
        get {
            var elements: Set<DateStampElement> = []
            if bool(forKey: Key.stampShowsDate, default: true) { elements.insert(.date) }
            if bool(forKey: Key.stampShowsTime, default: true) { elements.insert(.time) }
            if bool(forKey: Key.stampShowsPlace, default: false) { elements.insert(.place) }
            return elements.isEmpty ? DefaultValue.stampElements : elements
        }
        set {
            let normalized = newValue.isEmpty ? DefaultValue.stampElements : newValue
            defaults.set(normalized.contains(.date), forKey: Key.stampShowsDate)
            defaults.set(normalized.contains(.time), forKey: Key.stampShowsTime)
            defaults.set(normalized.contains(.place), forKey: Key.stampShowsPlace)
        }
    }

    var stampFadesOut: Bool {
        get { bool(forKey: Key.stampFadesOut, default: DefaultValue.stampFadesOut) }
        set { defaults.set(newValue, forKey: Key.stampFadesOut) }
    }

    var stampRenderingMode: StampRenderingMode {
        get {
            StampRenderingMode.normalized(
                defaults.string(forKey: Key.stampRenderingMode)
                    ?? DefaultValue.stampRenderingMode.rawValue
            )
        }
        set { defaults.set(newValue.rawValue, forKey: Key.stampRenderingMode) }
    }

    var videoStorageMode: VideoStorageMode {
        get {
            VideoStorageMode.normalized(
                defaults.string(forKey: Key.videoStorageMode)
                    ?? DefaultValue.videoStorageMode.rawValue
            )
        }
        set { defaults.set(newValue.rawValue, forKey: Key.videoStorageMode) }
    }

    var locationCaptureEnabled: Bool {
        get {
            bool(
                forKey: Key.locationCaptureEnabled,
                default: DefaultValue.locationCaptureEnabled
            )
        }
        set { defaults.set(newValue, forKey: Key.locationCaptureEnabled) }
    }

    var selectedCaptureDuration: TimeInterval {
        get {
            let stored = defaults.object(forKey: Key.selectedCaptureDuration) as? NSNumber
            return Self.normalizedCaptureDuration(stored?.doubleValue)
        }
        set {
            defaults.set(
                Self.normalizedCaptureDuration(newValue),
                forKey: Key.selectedCaptureDuration
            )
        }
    }

    var hasSeenCaptureIntroCard: Bool {
        get {
            bool(
                forKey: Key.hasSeenCaptureIntroCard,
                default: DefaultValue.hasSeenCaptureIntroCard
            )
        }
        set { defaults.set(newValue, forKey: Key.hasSeenCaptureIntroCard) }
    }


    /// 撮影画面での一言（シャッターの案内と、1本目を撮った後の案内）を見たか。
    var hasSeenCaptureCoach: Bool {
        get { bool(forKey: Key.hasSeenCaptureCoach, default: DefaultValue.hasSeenCaptureCoach) }
        set { defaults.set(newValue, forKey: Key.hasSeenCaptureCoach) }
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func normalizedCaptureDuration(_ duration: TimeInterval?) -> TimeInterval {
        CaptureDurationPolicy.normalized(duration)
    }
}
