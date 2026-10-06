import SwiftUI

struct SquishableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CameraGridOverlay: View {
    var body: some View {
        ZStack {
            HStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1)
                Spacer()
            }
            VStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

/// ピントと明るさの表示。映像の上なので白一色にし、操作部と重ならない範囲（`bounds`）に収める。
struct FocusRingView: View {
    let point: CGPoint
    /// 描画してよい範囲（このビューと同じ座標系）。上部バーと下の操作部を除いた領域。
    let bounds: CGRect
    let exposureBias: Float
    let exposureBiasRange: ClosedRange<Float>
    let isLocked: Bool

    private static let ringSize: CGFloat = 72
    private static let sliderOffset: CGFloat = 54
    private static let hintWidth: CGFloat = 240
    private static let hintGap: CGFloat = 56

    var body: some View {
        let center = clampedCenter
        // 右端に近いときは明るさのスライダーを左側に出す。
        let sliderOnLeading = center.x + Self.sliderOffset + 16 > bounds.maxX
        // 上端に近いときは案内を下に出す。
        let hintBelow = center.y - Self.hintGap - 10 < bounds.minY

        ZStack {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: isLocked ? 2.5 : 1.5)
                    .frame(width: Self.ringSize, height: Self.ringSize)

                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1.5, height: 48)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                        .offset(y: exposureThumbOffset)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(y: 36)
                }
                .offset(x: sliderOnLeading ? -Self.sliderOffset : Self.sliderOffset)
            }
            .position(center)

            hint
                .frame(width: Self.hintWidth)
                .position(
                    x: clamp(
                        center.x,
                        bounds.minX + Self.hintWidth / 2 + 8,
                        bounds.maxX - Self.hintWidth / 2 - 8
                    ),
                    y: hintBelow ? center.y + Self.hintGap : center.y - Self.hintGap
                )
        }
        .shadow(color: Color.black.opacity(0.45), radius: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLocked ? L10n.text("AE AFロック中") : L10n.text("ピントと明るさ"))
        .accessibilityValue(L10n.text("露出%+.1f", exposureBias))
        .accessibilityIdentifier("capture.focus.indicator")
    }

    @ViewBuilder
    private var hint: some View {
        if isLocked {
            Text(L10n.text("AE/AFロック"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: 0x111111))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.92), in: Capsule())
        } else {
            Text(L10n.text("上下で明るさ・長押しでロック"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var clampedCenter: CGPoint {
        let inset = Self.ringSize / 2
        guard bounds.width > inset * 2, bounds.height > inset * 2 else { return point }
        return CGPoint(
            x: clamp(point.x, bounds.minX + inset, bounds.maxX - inset),
            y: clamp(point.y, bounds.minY + inset, bounds.maxY - inset)
        )
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }

    private var exposureThumbOffset: CGFloat {
        let lower = CGFloat(exposureBiasRange.lowerBound)
        let upper = CGFloat(exposureBiasRange.upperBound)
        guard upper > lower else { return 0 }
        let progress = (CGFloat(exposureBias) - lower) / (upper - lower)
        return 20 - (min(max(progress, 0), 1) * 40)
    }
}
