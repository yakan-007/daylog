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
    let size: CGSize

    var body: some View {
        Circle()
            .stroke(AppTheme.accent, lineWidth: 2)
            .frame(width: 72, height: 72)
            .position(point)
            .shadow(color: AppTheme.accent.opacity(0.35), radius: 10)
    }
}
