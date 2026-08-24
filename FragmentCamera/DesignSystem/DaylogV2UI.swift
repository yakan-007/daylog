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

struct FocusRingView: View {
    let point: CGPoint
    let exposureBias: Float
    let exposureBiasRange: ClosedRange<Float>
    let isLocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.yellow, lineWidth: isLocked ? 3 : 2)
                .frame(width: 72, height: 72)

            Text(isLocked ? L10n.text("AE/AFロック") : L10n.text("上下で明るさ・長押しでロック"))
                .font(.system(size: isLocked ? 11 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow)
                .fixedSize()
                .offset(y: -54)

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 2, height: 48)
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 9, height: 9)
                    .offset(y: exposureThumbOffset)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .offset(y: 36)
            }
            .offset(x: 54)
        }
            .position(point)
            .shadow(color: Color.black.opacity(0.5), radius: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isLocked ? L10n.text("AE AFロック中") : L10n.text("ピントと明るさ"))
            .accessibilityValue(L10n.text("露出%+.1f", exposureBias))
            .accessibilityIdentifier("capture.focus.indicator")
    }

    private var exposureThumbOffset: CGFloat {
        let lower = CGFloat(exposureBiasRange.lowerBound)
        let upper = CGFloat(exposureBiasRange.upperBound)
        guard upper > lower else { return 0 }
        let progress = (CGFloat(exposureBias) - lower) / (upper - lower)
        return 20 - (min(max(progress, 0), 1) * 40)
    }
}
