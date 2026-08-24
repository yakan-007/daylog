import AVFoundation
import QuartzCore
import UIKit

struct TimedVideoStamp: Sendable {
    let context: VideoPostProcessContext
    let start: CMTime
    let duration: CMTime
    let contentFrame: CGRect
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
            textLayer.add(fade, forKey: "daylog-stamp-fade")
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
        stamps: [TimedVideoStamp]
    ) {
        let textLayers = makeTimedTextLayers(stamps: stamps)
        guard !textLayers.isEmpty else { return }
        installAnimationLayers(
            on: videoComposition,
            renderSize: renderSize,
            textLayers: textLayers
        )
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
                forKey: "daylog-stamp-visibility"
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
        textLayer.contentsScale = UIScreen.main.scale
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
        switch position {
        case .topLeading, .bottomLeading: return .left
        case .topTrailing, .bottomTrailing: return .right
        case .center: return .center
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
        textLayers: [CATextLayer]
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
