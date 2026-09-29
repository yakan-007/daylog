import AVFoundation
import QuartzCore
import UIKit

struct TimedVlogTextOverlay: Sendable {
    let overlay: VlogResolvedTextOverlay
    let start: CMTime
    let duration: CMTime
    let contentFrame: CGRect
}

/// アプリ内プレビューと同じ正規化座標を、共有動画のCore Animation座標へ変換する。
enum VlogTextLayerFactory {
    static func makeTimedTextLayers(
        overlays: [TimedVlogTextOverlay]
    ) -> [CATextLayer] {
        overlays.compactMap { timedOverlay in
            guard timedOverlay.duration.seconds.isFinite,
                  timedOverlay.duration.seconds > 0 else { return nil }
            let layer = makeTextLayer(
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

    static func makeTextLayer(
        overlay: VlogResolvedTextOverlay,
        contentFrame: CGRect
    ) -> CATextLayer {
        let baseDimension = min(contentFrame.width, contentFrame.height)
        let fontSize = max(15, baseDimension * 0.055) * overlay.style.relativeSize
        let font = resolvedFont(style: overlay.style, size: fontSize)
        let margin = max(contentFrame.width * 0.04, 8)
        let boxWidth = max(contentFrame.width * 0.84, 1)
        let desiredX = contentFrame.minX
            + contentFrame.width * CGFloat(overlay.anchor.x)
        let anchorFactor: CGFloat = switch overlay.style.alignment {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let originX = min(
            max(desiredX - boxWidth * anchorFactor, contentFrame.minX + margin),
            contentFrame.maxX - margin - boxWidth
        )
        let lineCount = max(overlay.text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        let verticalPadding: CGFloat = overlay.style.backgroundColor == nil ? 0 : 10
        let boxHeight = ceil(font.lineHeight * CGFloat(lineCount) * 1.15) + verticalPadding
        let desiredYFromTop = contentFrame.minY
            + contentFrame.height * CGFloat(overlay.anchor.y)
        let centerYFromTop = min(
            max(desiredYFromTop, contentFrame.minY + (boxHeight / 2) + margin),
            contentFrame.maxY - (boxHeight / 2) - margin
        )

        let layer = CATextLayer()
        layer.string = overlay.text
        layer.font = CGFont(font.fontName as CFString) ?? font.fontName as CFTypeRef
        layer.fontSize = fontSize
        layer.alignmentMode = alignmentMode(overlay.style.alignment)
        layer.isWrapped = true
        layer.truncationMode = .end
        layer.contentsScale = UIScreen.main.scale
        layer.foregroundColor = UIColor(overlay.style.foregroundColor).cgColor
        if let background = overlay.style.backgroundColor {
            layer.backgroundColor = UIColor(background).cgColor
            layer.cornerRadius = 7
        }
        if let outline = overlay.style.outlineColor,
           overlay.style.outlineWidth > 0 {
            layer.shadowColor = UIColor(outline).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = max(1, fontSize * overlay.style.outlineWidth)
            layer.shadowOffset = .zero
        }
        // Core Animationの動画座標は左下原点。
        layer.frame = CGRect(
            x: originX,
            y: contentFrame.minY + contentFrame.maxY
                - centerYFromTop - (boxHeight / 2),
            width: boxWidth,
            height: boxHeight
        )
        return layer
    }

    private static func resolvedFont(style: VlogTextStyle, size: CGFloat) -> UIFont {
        let weight: UIFont.Weight = switch style.fontWeight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign = switch style.fontDesign {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func alignmentMode(
        _ alignment: VlogTextAlignment
    ) -> CATextLayerAlignmentMode {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    private static func visibilityAnimation(
        for overlay: TimedVlogTextOverlay
    ) -> CAKeyframeAnimation {
        let duration = max(overlay.duration.seconds, 0.001)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0]
        animation.keyTimes = [0, 0.999, 1]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
            + max(overlay.start.seconds, 0)
        animation.duration = duration
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }
}

private extension UIColor {
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
