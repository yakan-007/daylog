import CoreGraphics
import Foundation

struct VlogClipSourceMetadata: Equatable, Sendable {
    let capturedAt: Date
    let capturedPlaceName: String?
    let timeZoneIdentifier: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
    }
}

struct VlogResolvedTextOverlay: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let anchor: VlogNormalizedPoint
    let style: VlogTextStylePreset
    let scale: Double
    let timeRange: VlogOverlayTimeRange
    var alignment: VlogTextAlignment = .center
    /// 区間の終わりに向けて消えていく時間（0 なら最後まで表示してパッと消える）。
    var fadeOutDuration: TimeInterval = 0

    /// 再生位置での不透明度。フェードの途中なら 0〜1 の間になる。
    func opacity(at time: TimeInterval) -> Double {
        guard timeRange.contains(time) else { return 0 }
        guard fadeOutDuration > 0, let end = timeRange.end else { return 1 }
        let fadeStart = end - fadeOutDuration
        guard time > fadeStart else { return 1 }
        return max(0, min(1, (end - time) / fadeOutDuration))
    }
}

/// プレビュー・再生・書き出しが共通で使う、編集レシピから表示用データへの変換。
enum VlogTextOverlayResolver {
    /// スタンプのかたまりを表す表示用ID（1クリップに1つ）。
    static let blockID = UUID(uuidString: "6F6C6F67-6973-4800-8000-000000000001")!

    static func resolve(
        edit: VlogClipEdit,
        metadata: VlogClipSourceMetadata,
        clipDuration: TimeInterval
    ) -> [VlogResolvedTextOverlay] {
        guard clipDuration.isFinite, clipDuration > 0 else { return [] }
        let block = edit.normalized(for: clipDuration).block
        let timeZone = edit.sourceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? metadata.timeZone
        let text = lines(for: block, capturedAt: metadata.capturedAt, timeZone: timeZone)
            .joined(separator: "\n")
        guard !text.isEmpty else { return [] }
        let fades = block.fadesOut && clipDuration > VlogFadeTiming.totalDuration
        return [
            VlogResolvedTextOverlay(
                id: blockID,
                text: text,
                anchor: block.anchor,
                style: block.style,
                scale: block.scale,
                timeRange: fades
                    ? VlogOverlayTimeRange(start: 0, end: VlogFadeTiming.totalDuration)
                    : .entireClip,
                alignment: block.alignment,
                fadeOutDuration: fades ? VlogFadeTiming.fadeDuration : 0
            )
        ]
    }

    /// 上から 日付 → 時刻 → 場所 の順。ひとことは設定に応じて一番上か一番下。日付・時刻は日付スタンプと同じ書式で描く。
    static func lines(
        for block: VlogStampBlock,
        capturedAt: Date,
        timeZone: TimeZone
    ) -> [String] {
        var lines: [String] = []
        let caption = block.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if block.hasCaption, block.captionPlacement == .above {
            lines.append(caption)
        }
        if block.showsDate {
            lines.append(contentsOf: DateStampFormatter.lines(
                from: capturedAt,
                storedFormat: block.dateFormat,
                zeroPadded: block.zeroPadded,
                timeStyle: block.timeStyle,
                elements: [.date],
                timeZone: timeZone
            ).prefix(1))
        }
        if block.showsTime {
            lines.append(contentsOf: DateStampFormatter.lines(
                from: capturedAt,
                storedFormat: block.dateFormat,
                zeroPadded: block.zeroPadded,
                timeStyle: block.timeStyle,
                elements: [.time],
                timeZone: timeZone
            ).prefix(1))
        }
        if block.hasPlace {
            lines.append(block.placeName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if block.hasCaption, block.captionPlacement == .below {
            lines.append(caption)
        }
        return lines
    }
}

/// 文字の大きさと位置の計算。SwiftUI（編集・再生）と Core Animation（書き出し）が
/// 同じ値を使うことで、プレビューと書き出し結果を一致させる。
enum VlogTextLayout {
    /// 動画の短辺に対する基準の文字サイズ。
    static let baseFontRatio: CGFloat = 0.06
    /// 文字のかたまりが使える最大幅（動画の幅に対する割合）。
    static let maxWidthRatio: CGFloat = 0.88
    /// 端から離す余白（動画の短辺に対する割合）。
    static let marginRatio: CGFloat = 0.04

    static func fontSize(scale: Double, contentFrame: CGRect) -> CGFloat {
        let shortSide = max(min(contentFrame.width, contentFrame.height), 1)
        return shortSide * baseFontRatio * CGFloat(scale)
    }

    static func maxWidth(contentFrame: CGRect) -> CGFloat {
        max(contentFrame.width * maxWidthRatio, 1)
    }

    static func margin(contentFrame: CGRect) -> CGFloat {
        min(contentFrame.width, contentFrame.height) * marginRatio
    }

    /// 文字のかたまりの中心。`boxSize` が分かる時は、はみ出さないよう内側へ寄せる。
    static func center(
        anchor: VlogNormalizedPoint,
        contentFrame: CGRect,
        boxSize: CGSize? = nil
    ) -> CGPoint {
        let desired = CGPoint(
            x: contentFrame.minX + contentFrame.width * CGFloat(anchor.x),
            y: contentFrame.minY + contentFrame.height * CGFloat(anchor.y)
        )
        guard let boxSize else { return desired }
        let margin = margin(contentFrame: contentFrame)
        let halfWidth = min(boxSize.width / 2, contentFrame.width / 2)
        let halfHeight = min(boxSize.height / 2, contentFrame.height / 2)
        let minX = contentFrame.minX + min(margin + halfWidth, contentFrame.width / 2)
        let maxX = contentFrame.maxX - min(margin + halfWidth, contentFrame.width / 2)
        let minY = contentFrame.minY + min(margin + halfHeight, contentFrame.height / 2)
        let maxY = contentFrame.maxY - min(margin + halfHeight, contentFrame.height / 2)
        return CGPoint(
            x: min(max(desired.x, minX), maxX),
            y: min(max(desired.y, minY), maxY)
        )
    }
}
