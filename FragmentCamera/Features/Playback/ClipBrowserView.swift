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
    /// ページ送りのアニメーション用の横位置（指の動きとは別に持つ）。
    @State private var settleOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 390
    /// 送り出した方向（-1: 次へ、1: 前へ）。新しい動画が準備できるまで保持する。
    @State private var pendingPageDirection: CGFloat?
    @State private var pendingFromItemID: String?
    @State private var pageTurnCount = 0
    @State private var showsLoadingIndicator = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            playbackPage
                .offset(x: settleOffset + dragOffset)

            // 日付と進み具合は動画と一緒に流さず、画面に固定して出しっぱなしにする。
            playbackChrome

            loadingAndFailureContent
        }
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { pageWidth = max(proxy.size.width, 1) }
                    .onChange(of: proxy.size.width) { _, width in pageWidth = max(width, 1) }
            }
        }
        .simultaneousGesture(horizontalSwipeGesture)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: pageTurnCount)
        .sensoryFeedback(.selection, trigger: state.isPaused)
        .onChange(of: pageReadyKey) { _, _ in
            bringInNextPageIfReady()
        }
        .task(id: pendingFromItemID) {
            // 送り先の準備が長引いても、画面が外へ出たままにならないようにする。
            guard pendingFromItemID != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            finishPendingPage(force: true)
        }
        .onTapGesture(perform: handleSurfaceTap)
        .background(Color.black.ignoresSafeArea())
        .task(id: state.isLoading) {
            showsLoadingIndicator = false
            guard state.isLoading else { return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, state.isLoading else { return }
            showsLoadingIndicator = true
        }
    }

    private var playbackPage: some View {
        ZStack {
            ClipBrowserPlayerSurface(player: player)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if let stampContext = state.stampContext {
                DateStampPlaybackOverlay(
                    itemID: state.itemID,
                    context: stampContext,
                    videoAspectRatio: state.videoAspectRatio
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            if !state.textOverlays.isEmpty {
                VlogTextOverlayCanvas(
                    overlays: state.textOverlays,
                    playbackTime: state.clipDuration * state.clipProgress,
                    videoAspectRatio: state.videoAspectRatio
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Chrome

    private var playbackChrome: some View {
        ZStack {
            playbackScrims

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playback.item")
            .accessibilityValue(state.itemID)
            .accessibilityHint(playbackHint)

            if state.isPaused && !state.isLoading && !state.didFailToLoad {
                pausedButton
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.isPaused)
    }

    private var playbackScrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 170)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 左上のスタンプ表記。右上の閉じるボタン（PlaybackFeatureView）の分は空けておく。
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: state.stampDateText.isEmpty ? state.dateText : state.stampDateText)
                .rollMono(15, .semibold, maxScale: 1.3)
                .tracking(0.6)
                .accessibilityLabel(state.dateText)
                .accessibilityIdentifier("playback.date")
            Text(verbatim: timeLine)
                .rollMono(11, maxScale: 1.3)
                .opacity(0.78)
                .accessibilityLabel(state.timeText)
                .accessibilityIdentifier("playback.time")
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.trailing, 64)
        .allowsHitTesting(false)
    }

    private var timeLine: String {
        let time = state.stampTimeText.isEmpty ? state.timeText : state.stampTimeText
        guard let place = state.placeText else { return time }
        return "\(time) · \(place)"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaybackSegmentedProgress(
                durations: state.segmentDurations,
                currentIndex: state.currentClipIndex,
                clipProgress: state.clipProgress,
                dayProgress: state.dayProgress
            )
            .frame(height: 3)

            HStack {
                Text(verbatim: state.positionText)
                    .rollMono(11, maxScale: 1.3)
                    .accessibilityIdentifier("playback.position")
                Spacer(minLength: 8)
                Text(L10n.text("左右で前後 · 下にスワイプで閉じる"))
                    .rollText(10, maxScale: 1.3)
                    .tracking(0.4)
                    .opacity(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
    }

    private var pausedButton: some View {
        Button(action: actions.onTogglePlayback) {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(RollTheme.ink)
                .offset(x: 2)
                .frame(width: 68, height: 68)
                .background(Color.white.opacity(0.92), in: Circle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(L10n.text("再生"))
        .accessibilityIdentifier("playback.toggle")
    }

    @ViewBuilder
    private var loadingAndFailureContent: some View {
        ZStack {
            if state.isLoading && showsLoadingIndicator {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.15)
                    Text(L10n.text("読み込み中"))
                        .rollText(12, .medium)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            if state.didFailToLoad {
                VStack(spacing: 14) {
                    Text(L10n.text("動画を読み込めませんでした"))
                        .rollText(15, .semibold)
                        .foregroundStyle(.white.opacity(0.86))
                    Button(action: actions.onRetry) {
                        Label(L10n.text("もう一度"), systemImage: "arrow.clockwise")
                            .rollText(13, .semibold)
                            .foregroundStyle(RollTheme.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 40)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(SquishableButtonStyle())
                }
            }
        }
    }

    private var playbackHint: String {
        let base = state.canRetreatClip || state.canAdvanceClip
            ? L10n.text("左右で同じ日の前後")
            : L10n.text("この日の動画はここまで")
        return L10n.text("%@。タップで一時停止", base)
    }

    /// 画面のタップは一時停止と再生の切り替え。
    private func handleSurfaceTap() {
        guard !state.isLoading,
              !state.didFailToLoad,
              pendingPageDirection == nil else { return }
        actions.onTogglePlayback()
    }

    /// 指に合わせた横移動。送れる方向は指に1:1でついてくる。送れない方向はゴムのように重く止まる。
    private var dragOffset: CGFloat {
        guard ClipBrowserSwipePolicy.dominantAxis(for: dragTranslation) == .horizontal else {
            return 0
        }
        let canNavigate = dragTranslation.width < 0
            ? state.canAdvanceClip
            : state.canRetreatClip
        return canNavigate
            ? dragTranslation.width
            : ClipBrowserSwipePolicy.rubberBand(dragTranslation.width, dimension: pageWidth * 0.35)
    }

    private var pageReadyKey: String {
        "\(state.itemID)-\(state.isLoading)-\(state.didFailToLoad)"
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard pendingPageDirection == nil,
                      !state.isLoading,
                      !state.isTransitioning else { return }
                guard ClipBrowserSwipePolicy.dominantAxis(for: value.translation) == .horizontal else {
                    dragTranslation = .zero
                    return
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                handleSwipe(value.translation, predicted: value.predictedEndTranslation)
            }
    }

    /// 送る時は、今の動画を指の向きへ押し出し、準備できた次の動画を反対側から入れる。
    private func handleSwipe(_ translation: CGSize, predicted: CGSize) {
        let releasedOffset = dragOffset
        guard pendingPageDirection == nil,
              !state.isLoading,
              !state.isTransitioning,
              let intent = ClipBrowserSwipePolicy.intent(
                translation: translation,
                predictedEndTranslation: predicted
              ) else {
            springBack()
            return
        }

        let direction: CGFloat
        let action: () -> Void
        switch intent {
        case .advanceClip where state.canAdvanceClip:
            direction = -1
            action = actions.onAdvanceClip
        case .retreatClip where state.canRetreatClip:
            direction = 1
            action = actions.onRetreatClip
        case .advanceClip, .retreatClip, .advanceDay, .retreatDay:
            springBack()
            return
        }

        // 指を離した位置からそのまま続けて押し出す（見た目が飛ばないように）。
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settleOffset = releasedOffset
            dragTranslation = .zero
        }
        pendingPageDirection = direction
        pendingFromItemID = state.itemID
        pageTurnCount += 1
        withAnimation(.easeIn(duration: 0.16)) {
            settleOffset = direction * pageWidth
        }
        action()
    }

    private func springBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            dragTranslation = .zero
            settleOffset = 0
        }
    }

    private func bringInNextPageIfReady() {
        guard pendingPageDirection != nil,
              state.itemID != pendingFromItemID,
              !state.isLoading else { return }
        finishPendingPage(force: false)
    }

    /// 次の動画を反対側から入れる。送れなかった（同じ動画のまま）時は元の位置へ戻す。
    private func finishPendingPage(force: Bool) {
        guard let direction = pendingPageDirection else { return }
        let didMove = state.itemID != pendingFromItemID
        pendingPageDirection = nil
        pendingFromItemID = nil
        guard didMove else {
            springBack()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settleOffset = -direction * pageWidth * 0.35
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            settleOffset = 0
        }
    }
}

/// 下の進み具合。クリップごとに区切り、見終わった分は白、いまのクリップは途中まで白、この先は薄い白。
/// 本数が多くて区切りが読めない日は、1本のバーで一日の進み具合を出す（`PlaybackProgressLayout`）。
private struct PlaybackSegmentedProgress: View {
    let durations: [TimeInterval]
    let currentIndex: Int
    let clipProgress: Double
    let dayProgress: Double

    var body: some View {
        Canvas { context, size in
            let track = Color.white.opacity(0.3)
            let fill = Color.white
            let radius = size.height / 2

            switch PlaybackProgressLayout.style(count: durations.count, width: size.width) {
            case .continuous:
                let full = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: full, cornerRadius: radius), with: .color(track))
                let done = CGRect(x: 0, y: 0, width: size.width * clamp(dayProgress), height: size.height)
                context.fill(Path(roundedRect: done, cornerRadius: radius), with: .color(fill))

            case .segmented(let gap):
                let widths = PlaybackProgressLayout.segmentWidths(
                    durations: durations,
                    width: size.width,
                    gap: gap
                )
                var x: CGFloat = 0
                for (index, width) in widths.enumerated() {
                    let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                    let segmentRadius = min(radius, width / 2)
                    context.fill(Path(roundedRect: rect, cornerRadius: segmentRadius), with: .color(track))
                    let fraction: Double
                    if index < currentIndex {
                        fraction = 1
                    } else if index == currentIndex {
                        fraction = clamp(clipProgress)
                    } else {
                        fraction = 0
                    }
                    if fraction > 0 {
                        let done = CGRect(x: x, y: 0, width: width * fraction, height: size.height)
                        context.fill(Path(roundedRect: done, cornerRadius: segmentRadius), with: .color(fill))
                    }
                    x += width + gap
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
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
        switch context.position.column {
        case 0: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    private var frameAlignment: Alignment {
        switch context.position.column {
        case 0: return .topLeading
        case 2: return .topTrailing
        default: return .top
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
                clipProgress: 0.32,
                clipDuration: 3,
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
                textOverlays: [],
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
