import AVFoundation
import SwiftUI

struct ClipBrowserActions {
    let onAdvanceClip: () -> Void
    let onRetreatClip: () -> Void
    let onTogglePlayback: () -> Void
    let onRetry: () -> Void
}

struct LibraryClipBrowserFeatureView: View {
    @ObservedObject var viewModel: LibraryClipBrowserViewModel

    var body: some View {
        ClipBrowserView(
            state: viewModel.screenState,
            player: viewModel.player,
            actions: ClipBrowserActions(
                onAdvanceClip: viewModel.advanceClip,
                onRetreatClip: viewModel.retreatClip,
                onTogglePlayback: viewModel.togglePlayback,
                onRetry: viewModel.retryPlayback
            )
        )
        .onAppear {
            viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.stopPlayback()
        }
    }
}

struct ClipBrowserView: View {
    let state: ClipBrowserScreenState
    let player: AVPlayer
    let actions: ClipBrowserActions

    @State private var dragTranslation: CGSize = .zero
    @State private var showsLoadingIndicator = false
    @State private var controlsVisible = true
    @State private var controlsInteractionID = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            playbackPage
                .offset(x: dragOffset)
                .scaleEffect(dragScale)

            loadingAndFailureContent
        }
        .contentShape(Rectangle())
        .simultaneousGesture(horizontalSwipeGesture)
        .onTapGesture(perform: handleSurfaceTap)
        .background(Color.black.ignoresSafeArea())
        .task(id: state.isLoading) {
            showsLoadingIndicator = false
            guard state.isLoading else { return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, state.isLoading else { return }
            showsLoadingIndicator = true
        }
        .task(id: controlsAutohideID) {
            guard controlsVisible,
                  !state.isPaused,
                  !state.isLoading,
                  !state.didFailToLoad else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
        .onChange(of: state.itemID) { _, _ in
            revealControls()
        }
        .onChange(of: state.isPaused) { _, isPaused in
            if isPaused {
                controlsVisible = true
            }
            controlsInteractionID += 1
        }
        .onChange(of: state.isLoading) { _, _ in
            controlsInteractionID += 1
        }
    }

    private var playbackPage: some View {
        ZStack {
            ClipBrowserPlayerSurface(player: player)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            playbackScrims
            if let stampContext = state.stampContext {
                DateStampPlaybackOverlay(
                    itemID: state.itemID,
                    context: stampContext,
                    videoAspectRatio: state.videoAspectRatio
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            if controlsVisible {
                overlayContent
                    .transition(.opacity)
            }
        }
    }

    private var playbackScrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.58), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
        }
        .ignoresSafeArea()
        .opacity(controlsVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var loadingAndFailureContent: some View {
        ZStack {
            if state.isLoading && showsLoadingIndicator {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.15)
                    Text("読み込み中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            if state.didFailToLoad {
                VStack(spacing: 14) {
                    Text("動画を読み込めませんでした")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Button(action: actions.onRetry) {
                        Label("もう一度", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(DaylogModernTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SquishableButtonStyle())
                }
            }
        }
    }

    private var overlayContent: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.dateText)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("playback.date")
                    Text(state.timeText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                        .accessibilityIdentifier("playback.time")
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text(state.positionText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .accessibilityIdentifier("playback.position")

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.25))
                            Capsule()
                                .fill(.white)
                                .frame(width: max(4, proxy.size.width * CGFloat(state.dayProgress)))
                        }
                    }
                    .frame(height: 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playback.item")
            .accessibilityValue(state.itemID)
            .accessibilityHint(playbackHint)

            Button {
                actions.onTogglePlayback()
                controlsVisible = true
                controlsInteractionID += 1
            } label: {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.36), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.36), lineWidth: 1)
                    }
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityLabel(state.isPaused ? L10n.text("再生") : L10n.text("一時停止"))
            .accessibilityIdentifier("playback.toggle")
            .disabled(state.isLoading || state.didFailToLoad)
        }
    }

    private var playbackHint: String {
        if state.canRetreatClip || state.canAdvanceClip {
            return L10n.text("左右で同じ日の前後")
        }
        return L10n.text("この日の動画はここまで")
    }

    private var controlsAutohideID: String {
        "\(state.itemID)-\(state.isPaused)-\(state.isLoading)-\(controlsInteractionID)"
    }

    private func handleSurfaceTap() {
        guard !state.didFailToLoad else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            controlsVisible = state.isPaused ? true : !controlsVisible
        }
        controlsInteractionID += 1
    }

    private func revealControls() {
        withAnimation(.easeOut(duration: 0.18)) {
            controlsVisible = true
        }
        controlsInteractionID += 1
    }

    private var dragOffset: CGFloat {
        guard ClipBrowserSwipePolicy.dominantAxis(for: dragTranslation) == .horizontal else {
            return 0
        }
        let canNavigate = dragTranslation.width < 0
            ? state.canAdvanceClip
            : state.canRetreatClip
        let response: CGFloat = canNavigate ? 0.72 : 0.2
        return max(min(dragTranslation.width, 220), -220) * response
    }

    private var dragScale: CGFloat {
        1 - min(abs(dragOffset) / 8_000, 0.012)
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !state.isLoading, !state.isTransitioning else { return }
                guard ClipBrowserSwipePolicy.dominantAxis(for: value.translation) == .horizontal else {
                    dragTranslation = .zero
                    return
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                withAnimation(.interactiveSpring(
                    response: 0.26,
                    dampingFraction: 0.88
                )) {
                    dragTranslation = .zero
                }
                handleSwipe(value.translation, predicted: value.predictedEndTranslation)
            }
    }

    private func handleSwipe(_ translation: CGSize, predicted: CGSize) {
        guard !state.isLoading,
              !state.isTransitioning,
              let intent = ClipBrowserSwipePolicy.intent(
                translation: translation,
                predictedEndTranslation: predicted
              ) else { return }
        switch intent {
        case .advanceClip where state.canAdvanceClip:
            actions.onAdvanceClip()
        case .retreatClip where state.canRetreatClip:
            actions.onRetreatClip()
        case .advanceClip, .retreatClip, .advanceDay, .retreatDay:
            break
        }
    }
}

private struct DateStampPlaybackOverlay: View {
    let itemID: String
    let context: VideoPostProcessContext
    let videoAspectRatio: CGFloat

    @State private var opacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            let contentFrame = DateStampStyle.aspectFitFrame(
                contentAspectRatio: videoAspectRatio,
                in: proxy.size
            )
            let lines = DateStampFormatter.lines(
                from: context.stampDate,
                storedFormat: context.format,
                zeroPadded: context.zeroPadded,
                timeStyle: context.timeStyle,
                elements: context.elements,
                placeName: context.placeName,
                timeZone: context.stampTimeZone
            )
            let textFrame = DateStampStyle.textFrame(
                for: contentFrame.size,
                sizeKey: context.sizeKey,
                position: context.position,
                lineCount: lines.count
            )
            Text(lines.joined(separator: "\n"))
                .font(.system(
                    size: DateStampStyle.fontSize(
                        for: contentFrame.size,
                        sizeKey: context.sizeKey
                    ),
                    weight: .semibold
                ))
                .foregroundStyle(.white)
                .multilineTextAlignment(textAlignment)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                .frame(
                    width: textFrame.width,
                    height: textFrame.height,
                    alignment: frameAlignment
                )
                .position(
                    x: contentFrame.minX + textFrame.midX,
                    y: contentFrame.minY + textFrame.midY
                )
                .opacity(opacity)
                .accessibilityIdentifier("playback.stamp")
                .accessibilityLabel(lines.joined(separator: ", "))
        }
        .task(id: itemID) {
            opacity = 1
            guard context.fadesOut else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
        }
    }

    private var textAlignment: TextAlignment {
        switch context.position {
        case .topLeading, .bottomLeading: return .leading
        case .topTrailing, .bottomTrailing: return .trailing
        case .center: return .center
        }
    }

    private var frameAlignment: Alignment {
        switch context.position {
        case .topLeading, .bottomLeading: return .topLeading
        case .topTrailing, .bottomTrailing: return .topTrailing
        case .center: return .top
        }
    }

}

private struct ClipBrowserPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: PlayerSurfaceView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

private final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
private struct ClipBrowserViewPreviews: PreviewProvider {
    static var previews: some View {
        ClipBrowserView(
            state: ClipBrowserScreenState(
                itemID: "preview",
                dateText: "7月15日 火",
                timeText: "18:42",
                positionText: "2 / 5",
                dayProgress: 0.32,
                isPaused: false,
                swipeHintText: "左右で同じ日の前後",
                isLoading: false,
                didFailToLoad: false,
                isTransitioning: false,
                canRetreatClip: true,
                canAdvanceClip: true,
                canRetreatDay: false,
                canAdvanceDay: false,
                stampContext: nil,
                videoAspectRatio: 9.0 / 16.0
            ),
            player: AVPlayer(),
            actions: ClipBrowserActions(
                onAdvanceClip: {},
                onRetreatClip: {},
                onTogglePlayback: {},
                onRetry: {}
            )
        )
    }
}
#endif
