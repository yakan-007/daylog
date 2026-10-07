import AVFoundation
import QuartzCore
import UIKit

struct TimedVideoStamp: Sendable {
    let context: VideoPostProcessContext
    let start: CMTime
    let duration: CMTime
    let contentFrame: CGRect
}

/// 書き出しの最後に入れる小さなロゴの置き方。
struct ExportEndMark: Sendable {
    static let text = "VLOGISH"
    /// 動画の終わりから何秒前に出すか。
    static let visibleDuration: Double = 1.5
    static let fadeDuration: Double = 0.3
    static let opacity: Float = 0.72

    /// 置く場所の候補。上から順に、空いている角を使う。
    enum Corner: CaseIterable, Sendable {
        case bottomTrailing
        case bottomLeading
        case topTrailing
        case topLeading
    }

    let start: CMTime
    let end: CMTime
    let contentFrame: CGRect

    init(videoDuration: CMTime, contentFrame: CGRect) {
        let duration = max(videoDuration.seconds.isFinite ? videoDuration.seconds : 0, 0)
        start = CMTime(
            seconds: max(duration - Self.visibleDuration, 0),
            preferredTimescale: 600
        )
        end = CMTime(seconds: duration, preferredTimescale: 600)
        self.contentFrame = contentFrame
    }

    /// ロゴが出ている間に、ほかの文字が見えているか。
    func overlapsInTime(start otherStart: Double, end otherEnd: Double) -> Bool {
        otherStart < end.seconds && otherEnd > start.seconds
    }
}

/// 撮影時の焼き込みと一日動画の書き出しで、同じ文字・余白・フェードを使う。
enum DateStampLayerFactory {
    static func installSingleStamp(
        on videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        context: VideoPostProcessContext
    ) {
        guard context.stampEnabled else { return }
        let textLayer = makeTextLayer(
            contentFrame: CGRect(origin: .zero, size: renderSize),
            context: context
        )
        if context.fadesOut {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.beginTime = AVCoreAnimationBeginTimeAtZero + 2.0
            fade.duration = 0.5
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            textLayer.add(fade, forKey: "vlogish-stamp-fade")
        }
        installAnimationLayers(
            on: videoComposition,
            renderSize: renderSize,
            textLayers: [textLayer]
        )
    }

    static func installTimedStamps(
        on videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        stamps: [TimedVideoStamp],
        vlogTextOverlays: [TimedVlogTextOverlay] = [],
        endMark: ExportEndMark? = nil
    ) {
        let stampLayers: [CALayer] = makeTimedTextLayers(stamps: stamps)
        let textLayers = stampLayers
            + VlogTextLayerFactory.makeTimedTextLayers(overlays: vlogTextOverlays)
            + endMarkLayers(endMark, stamps: stamps, vlogTextOverlays: vlogTextOverlays)
        guard !textLayers.isEmpty else { return }
        installAnimationLayers(
            on: videoComposition,
            renderSize: renderSize,
            textLayers: textLayers
        )
    }

    private static func endMarkLayers(
        _ mark: ExportEndMark?,
        stamps: [TimedVideoStamp],
        vlogTextOverlays: [TimedVlogTextOverlay]
    ) -> [CALayer] {
        guard let mark else { return [] }
        let occupied = occupiedFrames(during: mark, stamps: stamps, vlogTextOverlays: vlogTextOverlays)
        return makeEndMarkLayer(mark, avoiding: occupied).map { [$0] } ?? []
    }

    /// クリップ数とレイヤー数、各表示区間を動画生成なしで検証できる形に保つ。
    static func makeTimedTextLayers(stamps: [TimedVideoStamp]) -> [CATextLayer] {
        stamps.compactMap { stamp -> CATextLayer? in
            guard stamp.context.stampEnabled,
                  stamp.duration.seconds.isFinite,
                  stamp.duration.seconds > 0 else { return nil }
            let layer = makeTextLayer(
                contentFrame: stamp.contentFrame,
                context: stamp.context
            )
            layer.opacity = 0
            layer.add(
                visibilityAnimation(for: stamp),
                forKey: "vlogish-stamp-visibility"
            )
            return layer
        }
    }

    static func makeTextLayer(
        contentFrame: CGRect,
        context: VideoPostProcessContext
    ) -> CATextLayer {
        let lines = DateStampFormatter.lines(
            from: context.stampDate,
            storedFormat: context.format,
            zeroPadded: context.zeroPadded,
            timeStyle: context.timeStyle,
            elements: context.elements,
            placeName: context.placeName,
            timeZone: context.stampTimeZone
        )
        let fontSize = DateStampStyle.fontSize(
            for: contentFrame.size,
            sizeKey: context.sizeKey
        )
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let preferredWidth = measuredTextWidth(
            lines: lines,
            font: font,
            maximumWidth: max(
                contentFrame.width - (DateStampStyle.margin(for: contentFrame.size) * 2),
                1
            )
        )
        let localFrame = DateStampStyle.textFrame(
            for: contentFrame.size,
            sizeKey: context.sizeKey,
            position: context.position,
            lineCount: lines.count,
            preferredWidth: preferredWidth
        )
        let textLayer = CATextLayer()
        textLayer.string = lines.joined(separator: "\n")
        textLayer.font = fontReference(font: font)
        textLayer.alignmentMode = alignmentMode(for: context.position)
        textLayer.isWrapped = true
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.shadowOpacity = 0.6
        textLayer.shadowRadius = 2
        textLayer.shadowOffset = CGSize(width: 0, height: 1)
        textLayer.contentsScale = 2
        // SwiftUI/DateStampStyleは左上原点、動画合成のCore Animationは左下原点。
        // 中央以外はY座標を反転しないと「右下」が「右上」へ書き出される。
        let compositorFrame = CGRect(
            x: localFrame.minX,
            y: contentFrame.height - localFrame.maxY,
            width: localFrame.width,
            height: localFrame.height
        )
        textLayer.frame = compositorFrame.offsetBy(
            dx: contentFrame.origin.x,
            dy: contentFrame.origin.y
        )
        return textLayer
    }

    /// 書き出しの最後に出す小さな VLOGISH。スタンプと同じ白・影で、少し透かす。
    /// スタンプや「ひとこと」と重ならない角を選ぶ。4つの角が全部ふさがっていたら入れない。
    static func makeEndMarkLayer(
        _ mark: ExportEndMark,
        avoiding occupied: [CGRect] = []
    ) -> CATextLayer? {
        let size = mark.contentFrame.size
        let shortSide = min(size.width, size.height)
        let fontSize = max(10, shortSide * 0.03)
        let margin = DateStampStyle.margin(for: size)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let text = NSAttributedString(
            string: ExportEndMark.text,
            attributes: [
                .font: font,
                .kern: fontSize * 0.18,
                .foregroundColor: UIColor.white
            ]
        )
        let textSize = text.size()
        let width = ceil(textSize.width) + 4
        let height = ceil(textSize.height) + 2

        // Core Animation は左下原点。下の角は minY 側になる。
        func frame(for corner: ExportEndMark.Corner) -> CGRect {
            let content = mark.contentFrame
            let isLeading = corner == .bottomLeading || corner == .topLeading
            let isBottom = corner == .bottomLeading || corner == .bottomTrailing
            return CGRect(
                x: isLeading ? content.minX + margin : content.maxX - margin - width,
                y: isBottom ? content.minY + margin : content.maxY - margin - height,
                width: width,
                height: height
            )
        }
        // 文字どうしがくっついて見えないよう、少し余裕を持って判定する。
        let breathingRoom = margin * 0.5
        guard let corner = ExportEndMark.Corner.allCases.first(where: { corner in
            let candidate = frame(for: corner).insetBy(dx: -breathingRoom, dy: -breathingRoom)
            return !occupied.contains { $0.intersects(candidate) }
        }) else {
            return nil
        }

        let layer = CATextLayer()
        layer.string = text
        layer.alignmentMode = (corner == .bottomLeading || corner == .topLeading) ? .left : .right
        layer.frame = frame(for: corner)
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.contentsScale = 2
        layer.opacity = 0

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = ExportEndMark.opacity
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero + max(mark.start.seconds, 0)
        fadeIn.duration = ExportEndMark.fadeDuration
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        layer.add(fadeIn, forKey: "vlogish-end-mark")
        return layer
    }

    /// ロゴが出ている間に画面にある、スタンプと「ひとこと」の場所。
    static func occupiedFrames(
        during mark: ExportEndMark,
        stamps: [TimedVideoStamp],
        vlogTextOverlays: [TimedVlogTextOverlay]
    ) -> [CGRect] {
        let stampFrames = stamps.compactMap { stamp -> CGRect? in
            guard stamp.context.stampEnabled else { return nil }
            let start = stamp.start.seconds
            var visibleEnd = start + stamp.duration.seconds
            if stamp.context.fadesOut, stamp.duration.seconds > 2 {
                visibleEnd = min(visibleEnd, start + 2.5)
            }
            guard mark.overlapsInTime(start: start, end: visibleEnd) else { return nil }
            return makeTextLayer(contentFrame: stamp.contentFrame, context: stamp.context).frame
        }
        let overlayFrames = vlogTextOverlays.compactMap { timed -> CGRect? in
            let start = timed.start.seconds
            guard mark.overlapsInTime(start: start, end: start + timed.duration.seconds) else {
                return nil
            }
            return VlogTextLayerFactory.makeLayer(
                overlay: timed.overlay,
                contentFrame: timed.contentFrame
            ).frame
        }
        return stampFrames + overlayFrames
    }

    private static func fontReference(font: UIFont) -> CFTypeRef {
        return CGFont(font.fontName as CFString) ?? font.fontName as CFTypeRef
    }

    private static func measuredTextWidth(
        lines: [String],
        font: UIFont,
        maximumWidth: CGFloat
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let widestLine = lines
            .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            .max() ?? font.pointSize
        // 文字端がクリップされないよう、描画用の余白を少しだけ加える。
        return min(widestLine + 4, maximumWidth)
    }

    private static func alignmentMode(
        for position: DateStampPosition
    ) -> CATextLayerAlignmentMode {
        switch position.column {
        case 0: return .left
        case 2: return .right
        default: return .center
        }
    }

    private static func visibilityAnimation(
        for stamp: TimedVideoStamp
    ) -> CAKeyframeAnimation {
        let duration = max(stamp.duration.seconds, 0.001)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        if stamp.context.fadesOut, duration > 2 {
            let fadeStart = min(2, duration)
            let fadeEnd = min(fadeStart + 0.5, duration)
            animation.values = [1, 1, 0, 0]
            animation.keyTimes = [
                0,
                NSNumber(value: fadeStart / duration),
                NSNumber(value: fadeEnd / duration),
                1
            ]
        } else {
            animation.values = [1, 1, 0]
            animation.keyTimes = [0, 0.999, 1]
        }
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + max(stamp.start.seconds, 0)
        animation.duration = duration
        // 開始前はモデル値（opacity = 0）のままにする。
        // .both にすると後続クリップの先頭値まで過去へ延長され、
        // まだ始まっていないスタンプが前のクリップへ重なる。
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }

    private static func installAnimationLayers(
        on videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        textLayers: [CALayer]
    ) {
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        textLayers.forEach(overlayLayer.addSublayer)
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }
}
