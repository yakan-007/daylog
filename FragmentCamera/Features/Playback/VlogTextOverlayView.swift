import SwiftUI

/// 編集画面・再生画面が共有する文字レイヤー。
/// 座標は動画そのものに対する0...1で保持し、黒帯を含む画面全体には置かない。
struct VlogTextOverlayCanvas: View {
    let overlays: [VlogResolvedTextOverlay]
    let playbackTime: TimeInterval
    let videoAspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let contentFrame = DateStampStyle.aspectFitFrame(
                contentAspectRatio: videoAspectRatio,
                in: proxy.size
            )
            ForEach(activeOverlays) { overlay in
                VlogOverlayText(overlay: overlay, contentFrame: contentFrame)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var activeOverlays: [VlogResolvedTextOverlay] {
        overlays.filter { $0.timeRange.contains(playbackTime) }
    }
}

private struct VlogOverlayText: View {
    let overlay: VlogResolvedTextOverlay
    let contentFrame: CGRect

    var body: some View {
        let boxWidth = max(contentFrame.width * 0.84, 1)
        let margin = max(contentFrame.width * 0.04, 8)
        let desiredX = contentFrame.minX
            + contentFrame.width * CGFloat(overlay.anchor.x)
        let originX = min(
            max(desiredX - boxWidth * horizontalAnchor, contentFrame.minX + margin),
            contentFrame.maxX - margin - boxWidth
        )
        let y = min(
            max(
                contentFrame.minY + contentFrame.height * CGFloat(overlay.anchor.y),
                contentFrame.minY + 24
            ),
            contentFrame.maxY - 24
        )

        Text(overlay.text)
            .font(.system(
                size: max(15, min(contentFrame.width, contentFrame.height) * 0.055)
                    * overlay.style.relativeSize,
                weight: overlay.style.fontWeight.swiftUIWeight,
                design: overlay.style.fontDesign.swiftUIDesign
            ))
            .foregroundStyle(Color(overlay.style.foregroundColor))
            .multilineTextAlignment(overlay.style.alignment.swiftUITextAlignment)
            .shadow(
                color: overlay.style.outlineColor.map(Color.init) ?? .clear,
                radius: overlay.style.outlineWidth > 0 ? 2 : 0,
                x: 0,
                y: 1
            )
            .padding(.horizontal, overlay.style.backgroundColor == nil ? 0 : 8)
            .padding(.vertical, overlay.style.backgroundColor == nil ? 0 : 5)
            .background {
                if let background = overlay.style.backgroundColor {
                    Color(background)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .frame(width: boxWidth, alignment: overlay.style.alignment.swiftUIAlignment)
            .position(x: originX + boxWidth / 2, y: y)
            .accessibilityIdentifier("playback.textOverlay")
            .accessibilityLabel(overlay.text)
    }

    private var horizontalAnchor: CGFloat {
        switch overlay.style.alignment {
        case .leading: return 0
        case .center: return 0.5
        case .trailing: return 1
        }
    }
}

private extension Color {
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

private extension VlogFontDesign {
    var swiftUIDesign: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }
}

private extension VlogFontWeight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

private extension VlogTextAlignment {
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var swiftUIAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
