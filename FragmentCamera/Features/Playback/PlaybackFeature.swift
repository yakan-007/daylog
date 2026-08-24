import SwiftUI

struct PlaybackFeatureView: View {
    let route: PlaybackRoute
    let makeLibraryClipBrowser: (LibraryClipPlaybackContext) -> LibraryClipBrowserViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var dismissalOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            LibraryClipBrowserHostView(
                context: route.context,
                makeLibraryClipBrowser: makeLibraryClipBrowser
            )

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SquishableButtonStyle())
            .padding(.top, 10)
            .padding(.trailing, 16)
            .accessibilityLabel("再生を閉じる")
            .accessibilityIdentifier("playback.close")
        }
        .offset(y: dismissalOffset)
        .simultaneousGesture(dismissGesture)
        .presentationBackground(.black)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let translation = value.translation
                guard translation.height > 0,
                      abs(translation.height) > abs(translation.width) * 1.2 else { return }
                dismissalOffset = min(translation.height * 0.42, 120)
            }
            .onEnded { value in
                let translation = value.translation
                let predicted = value.predictedEndTranslation
                let isDownward = translation.height > 0
                    && abs(translation.height) > abs(translation.width) * 1.2
                if isDownward && (translation.height > 90 || predicted.height > 180) {
                    dismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                        dismissalOffset = 0
                    }
                }
            }
    }
}

private struct LibraryClipBrowserHostView: View {
    @StateObject private var viewModel: LibraryClipBrowserViewModel

    init(
        context: LibraryClipPlaybackContext,
        makeLibraryClipBrowser: @escaping (LibraryClipPlaybackContext) -> LibraryClipBrowserViewModel
    ) {
        _viewModel = StateObject(wrappedValue: makeLibraryClipBrowser(context))
    }

    var body: some View {
        LibraryClipBrowserFeatureView(viewModel: viewModel)
    }
}
