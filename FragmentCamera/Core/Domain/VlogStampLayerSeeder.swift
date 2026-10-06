import Foundation

/// 共通の日付スタンプ設定から、編集画面の初期状態（スタンプのかたまり）を作る。
///
/// まだ編集していないクリップを開いた時だけ使う。共通設定で出している日付・時刻・場所を
/// そのまま並べ、共通設定の位置・大きさに置く。共通設定がオフなら空から組み立てる。
enum VlogStampLayerSeeder {
    /// 日付スタンプ（DateStampStyle）の文字サイズ比。VlogTextLayout の基準に合わせて倍率に直す。
    private static let stampFontRatio: Double = 0.052

    static func block(
        settings: DateStampSettings,
        placeName: String?
    ) -> VlogStampBlock {
        let trimmedPlace = placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isEnabled = settings.isEnabled
        return VlogStampBlock(
            showsDate: isEnabled && settings.elements.contains(.date),
            showsTime: isEnabled && settings.elements.contains(.time),
            showsPlace: isEnabled && settings.elements.contains(.place) && !trimmedPlace.isEmpty,
            placeName: trimmedPlace,
            caption: "",
            dateFormat: settings.format,
            zeroPadded: settings.isZeroPadded,
            timeStyle: settings.timeStyle,
            anchor: anchor(for: settings.position),
            style: .simple,
            scale: stampScale(sizeKey: settings.sizeKey),
            captionPlacement: .below,
            fadesOut: settings.fadesOut
        )
    }

    /// 日付スタンプと同じ見た目の大きさになる倍率。
    static func stampScale(sizeKey: String) -> Double {
        Double(DateStampStyle.scale(for: sizeKey)) * stampFontRatio / Double(VlogTextLayout.baseFontRatio)
    }

    /// 共通設定の9つの位置を、かたまりの中心に直す（端は描画時に余白の内側へ寄る）。
    static func anchor(for position: DateStampPosition) -> VlogNormalizedPoint {
        position.blockPosition.anchor
    }
}
