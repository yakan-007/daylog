import SwiftUI
import UIKit

/// 撮影画面のトークン。映像の上では黒・白を基本にし、色は意味ごとに1つだけ使う。
/// オレンジ（`accent`）は時間軸の「いま」、赤（`recording`）は録画中。
enum CaptureTheme {
    static let accent = RollTheme.accent
    static let recording = Color(hex: 0xFF3B30)
    static let ink = RollTheme.ink
    static let selectedFill = Color.white.opacity(0.92)
    static let scrim = Color.black.opacity(0.36)
    static let iconShadow = Color.black.opacity(0.35)
}

// MARK: - Top bar

struct CaptureTopBar: View {
    let state: CaptureScreenState
    let todayTimeline: CaptureTodayTimeline
    let onToggleTorch: () -> Void
    let onToggleGrid: () -> Void
    let onOpenSettings: () -> Void
    let onOpenToday: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                CaptureChromeButton(
                    systemName: state.isTorchEnabled ? "bolt.fill" : "bolt.slash",
                    isActive: state.isTorchEnabled,
                    isEnabled: state.isTorchAvailable,
                    accessibilityLabel: state.isTorchEnabled ? L10n.text("ライトを消す") : L10n.text("ライトをつける"),
                    action: onToggleTorch
                )
                .accessibilityIdentifier("capture.torch")

                Spacer(minLength: 0)

                CaptureChromeButton(
                    systemName: "square.grid.3x3",
                    isActive: state.isGridVisible,
                    accessibilityLabel: state.isGridVisible ? L10n.text("グリッドを隠す") : L10n.text("グリッドを表示"),
                    action: onToggleGrid
                )
                .accessibilityIdentifier("capture.grid")

                CaptureChromeButton(
                    systemName: "slider.horizontal.3",
                    isActive: false,
                    accessibilityLabel: L10n.text("設定"),
                    action: onOpenSettings
                )
                .accessibilityIdentifier("capture.settings")
            }
            .captureChromeHidden(state.isRecording)

            if let clockText = state.recordingClockText, state.isRecording {
                CaptureRecordingClockPill(text: clockText)
                    .transition(.opacity)
            } else {
                CaptureTodayStrip(timeline: todayTimeline, action: onOpenToday)
                    // 左右のボタン（右は2つ分）に重ならないよう、狭い画面では縮める。
                    .padding(.horizontal, 92)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.isRecording)
    }
}

/// 上部中央の「今日のミニ時間軸」。カメラロールと同じ見た目で、タップすると今日の記録を開く。
private struct CaptureTodayStrip: View {
    let timeline: CaptureTodayTimeline
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 分単位で「いま」の位置と日付を更新する（日付をまたいでも自然に切り替わる）。
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityIdentifier("capture.today")
    }

    private func content(now: Date) -> some View {
        let count = timeline.clipCount(on: now)
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text(verbatim: "\(CaptureTodayTimeline.dateText(now)) \(CaptureTodayTimeline.weekdayText(now))")
                Spacer(minLength: 0)
                Text(verbatim: CameraRollStampFormat.clips(count))
                    .opacity(0.8)
            }
            .rollMono(10, .medium, maxScale: 1.3)
            .tracking(0.6)
            .lineLimit(1)

            CaptureMiniTimeAxis(
                clipFractions: timeline.clipFractions(on: now),
                nowFraction: CaptureTodayTimeline.nowFraction(now)
            )
            .frame(height: 10)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 200)
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("今日の記録を開く。今日%d本", count))
    }
}

/// 0〜24時の細い時間軸。撮った時刻に縦の目盛り、いまの位置に差し色の点。
private struct CaptureMiniTimeAxis: View {
    let clipFractions: [Double]
    let nowFraction: Double

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let nowX = size.width * nowFraction

            var past = Path()
            past.move(to: CGPoint(x: 0, y: midY))
            past.addLine(to: CGPoint(x: nowX, y: midY))
            context.stroke(past, with: .color(.white), lineWidth: 1)

            var future = Path()
            future.move(to: CGPoint(x: nowX, y: midY))
            future.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                future,
                with: .color(.white.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            for fraction in clipFractions {
                let x = min(max(size.width * fraction, 1), size.width - 1)
                let tick = CGRect(x: x - 1, y: 0, width: 2, height: size.height)
                context.fill(Path(tick), with: .color(.white))
            }

            let dot = CGRect(x: nowX - 4.5, y: midY - 4.5, width: 9, height: 9)
            context.fill(Path(ellipseIn: dot), with: .color(CaptureTheme.accent))
        }
        .accessibilityHidden(true)
    }
}

private struct CaptureRecordingClockPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CaptureTheme.recording)
                .frame(width: 8, height: 8)
            Text(text)
                .rollMono(14, .medium, maxScale: 1.3)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color.black.opacity(0.42), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("録画中 %@", text))
        .accessibilityIdentifier("capture.recording.clock")
    }
}

// MARK: - Center status

struct CaptureCenterStatus: View {
    let statusText: String?
    let permissionMessage: String?
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.42))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("capture.status")
            }

            if let permissionMessage {
                CapturePermissionCard(
                    message: permissionMessage,
                    onOpenSettings: onOpenSystemSettings
                )
            }
        }
    }
}

// MARK: - Bottom dock

struct CaptureBottomDock: View {
    let state: CaptureScreenState
    let latestThumbnail: UIImage?
    let todayTimeline: CaptureTodayTimeline
    var coachMark: CaptureCoachMark? = nil
    let onSelectDuration: (TimeInterval) -> Void
    let onSelectZoom: (CGFloat) -> Void
    let onOpenLibrary: () -> Void
    let onShutter: () -> Void
    let onSwitchCamera: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomSelectionNamespace
    @Namespace private var durationSelectionNamespace

    var body: some View {
        VStack(spacing: 18) {
            if let coachMark, !state.isRecording {
                CaptureCoachBubble(mark: coachMark, seconds: Int(state.selectedDuration))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
            zoomPicker
            durationPicker
            captureControls
            grabber
        }
        .animation(chromeAnimation, value: coachMark)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .animation(chromeAnimation, value: state.isRecording)
        .simultaneousGesture(
            DragGesture(minimumDistance: 22)
                .onEnded { value in
                    let translation = value.translation
                    guard !state.isRecording,
                          translation.height < -54,
                          abs(translation.height) > abs(translation.width) * 1.25 else {
                        return
                    }
                    onOpenLibrary()
                }
        )
        .accessibilityAction(named: L10n.text("記録を開く"), onOpenLibrary)
    }

    private var todayClipCount: Int {
        todayTimeline.clipCount(on: Date())
    }

    // MARK: Zoom

    private var zoomPicker: some View {
        HStack(spacing: 4) {
            ForEach(state.zoomOptions) { option in
                let isSelected = abs(state.zoomFactor - option.deviceFactor) < 0.15
                Button {
                    withAnimation(selectionAnimation) {
                        onSelectZoom(option.deviceFactor)
                    }
                } label: {
                    Text(isSelected ? option.title : option.title.replacingOccurrences(of: "×", with: ""))
                        .rollMono(12, .semibold, maxScale: 1.3)
                        .foregroundStyle(isSelected ? CaptureTheme.ink : Color.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 36, minHeight: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(CaptureTheme.selectedFill)
                                    .matchedGeometryEffect(id: "zoom.selection", in: zoomSelectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(state.isRecording)
                .accessibilityLabel(L10n.text("ズーム %@", option.title))
                .accessibilityIdentifier("capture.zoom.\(option.displayFactor)")
                .accessibilityValue(isSelected ? L10n.text("選択中") : "")
            }
        }
        .padding(4)
        .background(CaptureTheme.scrim, in: Capsule())
        .captureChromeHidden(state.isRecording)
        .animation(selectionAnimation, value: selectedZoomID)
        .sensoryFeedback(.selection, trigger: selectedZoomID) { oldValue, newValue in
            oldValue != nil && newValue != nil && oldValue != newValue
        }
    }

    private var selectedZoomID: CGFloat? {
        state.zoomOptions.first(where: {
            abs(state.zoomFactor - $0.deviceFactor) < 0.15
        })?.id
    }

    // MARK: Duration

    /// 秒数を目盛り付きのセグメントで見せる。長いほど棒が高く、選んだ秒数は白く塗りつぶす（ズームと同じ選択表現）。
    private var durationPicker: some View {
        HStack(spacing: 2) {
            ForEach(state.durationOptions, id: \.self) { duration in
                let seconds = Int(duration)
                let isSelected = state.selectedDuration == duration
                Button {
                    withAnimation(selectionAnimation) {
                        onSelectDuration(duration)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(isSelected ? CaptureTheme.ink : Color.white.opacity(0.55))
                            .frame(width: 2, height: CGFloat(4 + seconds * 3))
                            .frame(height: 19, alignment: .bottom)
                        Text(verbatim: "\(seconds)s")
                            .rollMono(12, .semibold, maxScale: 1.3)
                            .foregroundStyle(isSelected ? CaptureTheme.ink : Color.white.opacity(0.8))
                    }
                    .padding(.vertical, 7)
                    .frame(width: 48)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(CaptureTheme.selectedFill)
                                .matchedGeometryEffect(id: "duration.selection", in: durationSelectionNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(state.isRecording)
                .accessibilityLabel(L10n.text("録画時間 %d秒", seconds))
                .accessibilityIdentifier("capture.duration.\(seconds)")
                .accessibilityValue(isSelected ? L10n.text("選択中") : "")
                .accessibilityHint(L10n.text("選ぶと、次の撮影は%d秒で自動停止します", seconds))
            }
        }
        .padding(4)
        .background(CaptureTheme.scrim, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 録画中も「何秒で撮っているか」は読めるよう、薄く残す。
        .opacity(state.isRecording ? 0.35 : 1)
        .allowsHitTesting(!state.isRecording)
        .animation(selectionAnimation, value: state.selectedDuration)
        .sensoryFeedback(.selection, trigger: state.selectedDuration)
    }

    // MARK: Controls

    private var captureControls: some View {
        HStack(alignment: .center) {
            Button(action: onOpenLibrary) {
                ZStack(alignment: .bottomTrailing) {
                    libraryThumbnail
                        .frame(width: 52, height: 52)
                        .background(CaptureTheme.scrim)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                        }

                    if todayClipCount > 0 {
                        Text(verbatim: "\(todayClipCount)")
                            .rollMono(11, .semibold, maxScale: 1.2)
                            .foregroundStyle(CaptureTheme.ink)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.white, in: Capsule())
                            .offset(x: 7, y: 7)
                    }
                }
            }
            .buttonStyle(SquishableButtonStyle())
            .captureChromeHidden(state.isRecording)
            .accessibilityLabel(L10n.text("日別ライブラリ。今日%d本", todayClipCount))
            .accessibilityIdentifier("capture.library")

            Spacer()

            Button(action: onShutter) {
                CaptureShutterButtonContent(
                    isRecording: state.isRecording,
                    progress: state.recordingProgress,
                    isHighlighted: coachMark == .shutter
                )
            }
            .buttonStyle(SquishableButtonStyle())
            .disabled(!state.isShutterEnabled)
            .accessibilityLabel(state.isRecording ? L10n.text("録画を停止") : L10n.text("録画を開始"))
            .accessibilityIdentifier("capture.shutter")
            .accessibilityHint(state.isRecording ? L10n.text("タップすると録画を停止して保存します") : L10n.text("%d秒の動画を撮影します", Int(state.selectedDuration)))

            Spacer()

            Button(action: onSwitchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(CaptureTheme.scrim, in: Circle())
            }
            .buttonStyle(SquishableButtonStyle())
            .disabled(state.isRecording)
            .captureChromeHidden(state.isRecording)
            .accessibilityLabel(L10n.text("前後のカメラを切り替える"))
            .accessibilityIdentifier("capture.camera.switch")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var libraryThumbnail: some View {
        if let latestThumbnail {
            Image(uiImage: latestThumbnail)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo.stack")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    /// 上にスワイプすると記録が開くことを示す取っ手。タップでも開ける。
    private var grabber: some View {
        Button(action: onOpenLibrary) {
            VStack(spacing: 4) {
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 36, height: 4)
                Text(L10n.text("上にスワイプで今日の記録"))
                    .rollText(10, maxScale: 1.3)
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .captureChromeHidden(state.isRecording)
        .accessibilityHidden(true)
        .accessibilityIdentifier("capture.grabber")
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78)
    }

    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }
}

// MARK: - Shutter

private struct CaptureShutterButtonContent: View {
    let isRecording: Bool
    let progress: Double
    var isHighlighted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            // はじめての撮影の前だけ、シャッターをゆっくり光らせる。
            if isHighlighted && !isRecording {
                Circle()
                    .stroke(Color.white.opacity(pulse ? 0 : 0.55), lineWidth: 2)
                    .frame(width: pulse ? 116 : 92, height: pulse ? 116 : 92)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                            pulse = true
                        }
                    }
                    .onDisappear { pulse = false }
            }

            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: 92, height: 92)

            if isRecording {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(CaptureTheme.recording, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 102, height: 102)
                    .rotationEffect(.degrees(-90))
            }

            RoundedRectangle(cornerRadius: isRecording ? 8 : 35, style: .continuous)
                .fill(isRecording ? CaptureTheme.recording : Color.white)
                .frame(width: isRecording ? 32 : 70, height: isRecording ? 32 : 70)
        }
        .frame(width: 104, height: 104)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: isRecording)
    }
}

// MARK: - Coach

/// 撮影画面での一言の吹き出し（白い地に黒い文字、下向きの矢印）。
private struct CaptureCoachBubble: View {
    let mark: CaptureCoachMark
    let seconds: Int

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(title)
                    .rollText(15, .bold)
                Text(detail)
                    .rollText(12)
                    .foregroundStyle(RollTheme.secondary)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(RollTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Triangle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 16, height: 8)
        }
        .frame(maxWidth: 280)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.coach")
    }

    private var title: String {
        switch mark {
        case .shutter: return L10n.text("押すと%d秒撮れます", seconds)
        case .firstClip: return L10n.text("今日の1本目")
        }
    }

    private var detail: String {
        switch mark {
        case .shutter: return L10n.text("秒数はこの下の目盛りで変えられます")
        case .firstClip: return L10n.text("上にスワイプで今日の記録を見られます")
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Shared pieces

private struct CaptureChromeButton: View {
    let systemName: String
    let isActive: Bool
    var isEnabled: Bool = true
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background {
                    if isActive {
                        Circle().fill(CaptureTheme.selectedFill)
                    }
                }
                .shadow(color: isActive ? .clear : CaptureTheme.iconShadow, radius: 3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isActive ? L10n.text("オン") : "")
    }

    private var foreground: Color {
        guard isEnabled else { return Color.white.opacity(0.35) }
        return isActive ? CaptureTheme.ink : .white
    }
}

private struct CapturePermissionCard: View {
    let message: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("権限を確認してください"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
            Button(L10n.text("設定を開く"), action: onOpenSettings)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CaptureTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private extension View {
    /// 録画中は周りの操作を消して、映像とシャッターだけにする。
    func captureChromeHidden(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}
