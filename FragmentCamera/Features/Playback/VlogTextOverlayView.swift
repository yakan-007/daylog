import SwiftUI
import UIKit

/// 編集画面・再生画面が共有する文字レイヤー。
/// 座標は動画そのものに対する 0...1 で持ち、黒帯を含む画面全体には置かない。
struct VlogTextOverlayCanvas: View {
    let overlays: [VlogResolvedTextOverlay]
    let playbackTime: TimeInterval
    let videoAspectRatio: CGFloat
    /// 編集中に選んでいる文字。枠を表示する。
    var selectedID: UUID? = nil

    var body: some View {
        GeometryReader { proxy in
            let contentFrame = DateStampStyle.aspectFitFrame(
                contentAspectRatio: videoAspectRatio,
                in: proxy.size
            )
            ForEach(activeOverlays) { overlay in
                VlogOverlayText(
                    overlay: overlay,
                    contentFrame: contentFrame,
                    isSelected: overlay.id == selectedID
                )
                .opacity(overlay.opacity(at: playbackTime))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var activeOverlays: [VlogResolvedTextOverlay] {
        overlays.filter { $0.timeRange.contains(playbackTime) }
    }
}

/// 1つの文字。書き出し（VlogTextLayerFactory）と同じ実測値（VlogTextMetrics）で描く。
struct VlogOverlayText: View {
    let overlay: VlogResolvedTextOverlay
    let contentFrame: CGRect
    var isSelected: Bool = false

    var body: some View {
        let spec = overlay.style.spec
        let metrics = VlogTextMetrics.measure(overlay: overlay, contentFrame: contentFrame)
        let center = VlogTextLayout.center(
            anchor: overlay.anchor,
            contentFrame: contentFrame,
            boxSize: metrics.boxSize
        )

        Text(overlay.text)
            .font(Font(metrics.font as CTFont))
            .foregroundStyle(Color(spec.foreground))
            .multilineTextAlignment(textAlignment)
            .lineLimit(nil)
            .minimumScaleFactor(0.8)
            .shadow(
                color: spec.outline.map { Color($0).opacity(spec.outlineOpacity) } ?? .clear,
                radius: spec.outline == nil
                    ? 0
                    : max(1, metrics.fontSize * CGFloat(spec.outlineRadiusRatio)) / 2
            )
            .frame(width: metrics.textSize.width, height: metrics.textSize.height, alignment: frameAlignment)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .background {
                if let background = spec.background {
                    RoundedRectangle(
                        cornerRadius: metrics.fontSize * CGFloat(spec.cornerRadiusRatio),
                        style: .continuous
                    )
                    .fill(Color(background))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .padding(-6)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                }
            }
            .position(center)
            .accessibilityIdentifier("playback.textOverlay")
            .accessibilityLabel(overlay.text)
    }

    private var textAlignment: TextAlignment {
        switch overlay.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch overlay.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

extension Color {
    init(_ color: VlogColor) {
        let normalized = color.normalized
        self.init(
            red: normalized.red,
            green: normalized.green,
            blue: normalized.blue,
            opacity: normalized.alpha
        )
    }
}
