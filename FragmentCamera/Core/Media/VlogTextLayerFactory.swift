import AVFoundation
import QuartzCore
import UIKit

struct TimedVlogTextOverlay: Sendable {
    let overlay: VlogResolvedTextOverlay
    let start: CMTime
    let duration: CMTime
    let contentFrame: CGRect
}

/// アプリ内プレビューと同じ計算（VlogTextLayout / VlogTextStyleSpec）で、
/// 書き出し動画の Core Animation レイヤーを作る。
enum VlogTextLayerFactory {
    static func makeTimedTextLayers(
        overlays: [TimedVlogTextOverlay]
    ) -> [CALayer] {
        overlays.compactMap { timedOverlay in
            guard timedOverlay.duration.seconds.isFinite,
                  timedOverlay.duration.seconds > 0 else { return nil }
            let layer = makeLayer(
                overlay: timedOverlay.overlay,
                contentFrame: timedOverlay.contentFrame
            )
            layer.opacity = 0
            layer.add(
                visibilityAnimation(for: timedOverlay),
                forKey: "vlogish-text-visibility"
            )
            return layer
        }
    }

    /// 背景（帯）付きにも対応するため、背景用の親レイヤーに文字レイヤーを入れて返す。
    static func makeLayer(
        overlay: VlogResolvedTextOverlay,
        contentFrame: CGRect
    ) -> CALayer {
        let spec = overlay.style.spec
        let metrics = VlogTextMetrics.measure(overlay: overlay, contentFrame: contentFrame)
        let fontSize = metrics.fontSize
        let attributes = metrics.attributes
        let horizontalPadding = metrics.horizontalPadding
        let verticalPadding = metrics.verticalPadding
        let textSize = metrics.textSize
        let boxSize = metrics.boxSize
        let center = VlogTextLayout.center(
            anchor: overlay.anchor,
            contentFrame: contentFrame,
            boxSize: boxSize
        )

        let container = CALayer()
        // Core Animation の動画座標は左下原点。上からの位置を反転する。
        container.frame = CGRect(
            x: center.x - boxSize.width / 2,
            y: contentFrame.minY + contentFrame.maxY - center.y - boxSize.height / 2,
            width: boxSize.width,
            height: boxSize.height
        )
        if let background = spec.background {
            container.backgroundColor = UIColor(background).cgColor
            container.cornerRadius = fontSize * CGFloat(spec.cornerRadiusRatio)
        }

        let textLayer = CATextLayer()
        textLayer.string = NSAttributedString(
            string: overlay.text,
            attributes: attributes.merging(
                [.foregroundColor: UIColor(spec.foreground)],
                uniquingKeysWith: { _, new in new }
            )
        )
        textLayer.isWrapped = true
        textLayer.alignmentMode = switch overlay.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.frame = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: textSize.width,
            height: textSize.height
        )
        if let outline = spec.outline, spec.outlineRadiusRatio > 0 {
            textLayer.shadowColor = UIColor(outline).cgColor
            textLayer.shadowOpacity = Float(spec.outlineOpacity)
            textLayer.shadowRadius = max(1, fontSize * CGFloat(spec.outlineRadiusRatio))
            textLayer.shadowOffset = .zero
        }
        container.addSublayer(textLayer)
        return container
    }

    private static func visibilityAnimation(
        for overlay: TimedVlogTextOverlay
    ) -> CAKeyframeAnimation {
        let duration = max(overlay.duration.seconds, 0.001)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        // フェードありなら最後の数百ミリ秒で消す。なしなら区間の終わりでパッと消す。
        let fade = min(max(overlay.overlay.fadeOutDuration, 0), duration)
        let fadeStart = fade > 0 ? max((duration - fade) / duration, 0) : 0.999
        animation.values = [1, 1, 0]
        animation.keyTimes = [0, NSNumber(value: fadeStart), 1]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
            + max(overlay.start.seconds, 0)
        animation.duration = duration
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }
}

/// 文字の大きさの実測。編集プレビューと書き出しが同じ値を使う。
struct VlogTextMetrics {
    let fontSize: CGFloat
    let font: UIFont
    let attributes: [NSAttributedString.Key: Any]
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    /// 文字だけの大きさ。
    let textSize: CGSize
    /// 背景の余白を含む大きさ。
    let boxSize: CGSize

    static func measure(
        overlay: VlogResolvedTextOverlay,
        contentFrame: CGRect
    ) -> VlogTextMetrics {
        let spec = overlay.style.spec
        let fontSize = VlogTextLayout.fontSize(scale: overlay.scale, contentFrame: contentFrame)
        let font = VlogTextFont.uiFont(spec: spec, size: fontSize)
        let horizontalPadding = fontSize * CGFloat(spec.horizontalPaddingRatio)
        let verticalPadding = fontSize * CGFloat(spec.verticalPaddingRatio)
        let maxTextWidth = max(
            VlogTextLayout.maxWidth(contentFrame: contentFrame) - horizontalPadding * 2,
            1
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch overlay.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let measured = (overlay.text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        // 描画時に端が欠けないよう、わずかに余裕を持たせる。
        let textSize = CGSize(
            width: min(ceil(measured.width) + 2, maxTextWidth),
            height: ceil(measured.height) + 2
        )
        return VlogTextMetrics(
            fontSize: fontSize,
            font: font,
            attributes: attributes,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            textSize: textSize,
            boxSize: CGSize(
                width: textSize.width + horizontalPadding * 2,
                height: textSize.height + verticalPadding * 2
            )
        )
    }
}

/// 見た目の定義からフォントを作る。SwiftUI 側も同じ太さ・書体を使う。
enum VlogTextFont {
    static func uiFont(spec: VlogTextStyleSpec, size: CGFloat) -> UIFont {
        let weight: UIFont.Weight = switch spec.weight {
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
        let base = UIFont.systemFont(ofSize: max(size, 1), weight: weight)
        guard spec.isRounded,
              let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: max(size, 1))
    }
}

extension UIColor {
    convenience init(_ color: VlogColor) {
        let normalized = color.normalized
        self.init(
            red: normalized.red,
            green: normalized.green,
            blue: normalized.blue,
            alpha: normalized.alpha
        )
    }
}
