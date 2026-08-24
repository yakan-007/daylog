import SwiftUI
import UIKit

struct CaptureTopBar: View {
    let state: CaptureScreenState
    let onToggleTorch: () -> Void
    let onToggleGrid: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CaptureCapsuleActionButton(
                systemName: state.isTorchEnabled ? "bolt.fill" : "bolt.slash.fill",
                tint: state.isTorchEnabled ? .yellow : .white,
                isEnabled: state.isTorchAvailable,
                accessibilityLabel: state.isTorchEnabled ? L10n.text("ライトを消す") : L10n.text("ライトをつける"),
                action: onToggleTorch
            )
            .accessibilityIdentifier("capture.torch")

            Spacer()

            CaptureCapsuleActionButton(
                systemName: "square.grid.3x3",
                tint: state.isGridVisible ? DaylogModernTheme.captureAccent : .white,
                accessibilityLabel: state.isGridVisible ? L10n.text("グリッドを隠す") : L10n.text("グリッドを表示"),
                action: onToggleGrid
            )
            .accessibilityIdentifier("capture.grid")

            CaptureCapsuleActionButton(
                systemName: "gearshape.fill",
                tint: .white,
                isEnabled: !state.isRecording,
                accessibilityLabel: L10n.text("設定"),
                action: onOpenSettings
            )
            .accessibilityIdentifier("capture.settings")
        }
        .padding(.horizontal, 4)
    }
}

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

struct CaptureBottomDock: View {
    let state: CaptureScreenState
    let latestThumbnail: UIImage?
    let todayClipCount: Int
    let onSelectDuration: (TimeInterval) -> Void
    let onSelectZoom: (CGFloat) -> Void
    let onOpenLibrary: () -> Void
    let onShutter: () -> Void
    let onSwitchCamera: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomSelectionNamespace
    @Namespace private var durationSelectionNamespace

    var body: some View {
        VStack(spacing: state.isRecording ? 8 : 12) {
            exportCapacityNotice
            zoomPicker
            durationPicker
            captureControls
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
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

    @ViewBuilder
    private var exportCapacityNotice: some View {
        if todayClipCount >= DayVideoExportPolicy.cautionClipCount,
           !state.isRecording {
            let isHeavy = todayClipCount >= DayVideoExportPolicy.heavyClipCount
            Label(
                isHeavy
                    ? L10n.text("%d本・分割結合", todayClipCount)
                    : L10n.text("分割まであと%d本", DayVideoExportPolicy.heavyClipCount - todayClipCount),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHeavy ? Color.white : Color.black.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHeavy ? DaylogModernTheme.danger : DaylogModernTheme.captureAccent)
            .clipShape(Capsule())
        }
    }

    private var zoomPicker: some View {
        HStack(spacing: 6) {
            ForEach(state.zoomOptions) { option in
                let isSelected = abs(state.zoomFactor - option.deviceFactor) < 0.15
                Button {
                    withAnimation(selectionAnimation) {
                        onSelectZoom(option.deviceFactor)
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(Color.white.opacity(0.16))
                                .overlay {
                                    Circle()
                                        .stroke(DaylogModernTheme.captureAccent.opacity(0.72), lineWidth: 1)
                                }
                                .matchedGeometryEffect(
                                    id: "zoom.selection",
                                    in: zoomSelectionNamespace
                                )
                        }

                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? DaylogModernTheme.captureAccent : Color.white.opacity(0.82))
                    }
                    .frame(width: 36, height: 36)
                    .scaleEffect(isSelected ? 1.08 : 1)
                    .contentShape(Circle())
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(state.isRecording)
                .accessibilityLabel(L10n.text("ズーム %@", option.title))
                .accessibilityIdentifier("capture.zoom.\(option.displayFactor)")
                .accessibilityValue(isSelected ? L10n.text("選択中") : "")
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.46), in: Capsule())
        .opacity(state.isRecording ? 0 : 1)
        .animation(selectionAnimation, value: selectedZoomID)
        .sensoryFeedback(.selection, trigger: selectedZoomID) { oldValue, newValue in
            oldValue != nil && newValue != nil && oldValue != newValue
        }
    }

    private var durationPicker: some View {
        HStack(spacing: 8) {
            ForEach(state.durationOptions, id: \.self) { duration in
                let isSelected = state.selectedDuration == duration
                Button {
                    withAnimation(selectionAnimation) {
                        onSelectDuration(duration)
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                                .matchedGeometryEffect(
                                    id: "duration.selection",
                                    in: durationSelectionNamespace
                                )
                        }

                        VStack(spacing: 4) {
                            Text(L10n.text("%d秒", Int(duration)))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Capsule()
                                .fill(isSelected ? DaylogModernTheme.captureAccent : .clear)
                                .frame(width: isSelected ? 14 : 4, height: 3)
                        }
                        .foregroundStyle(isSelected ? DaylogModernTheme.captureAccent : Color.white.opacity(0.7))
                    }
                    .frame(width: 52, height: 44)
                    .scaleEffect(isSelected ? 1.04 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(state.isRecording)
                .accessibilityLabel(L10n.text("録画時間 %d秒", Int(duration)))
                .accessibilityIdentifier("capture.duration.\(Int(duration))")
                .accessibilityValue(state.selectedDuration == duration ? L10n.text("選択中") : "")
                .accessibilityHint(L10n.text("選ぶと、次の撮影は%d秒で自動停止します", Int(duration)))
            }
        }
        .frame(height: 44)
        .opacity(state.isRecording ? 0.28 : 1)
        .scaleEffect(state.isRecording ? 0.96 : 1, anchor: .bottom)
        .animation(selectionAnimation, value: state.selectedDuration)
        .sensoryFeedback(.selection, trigger: state.selectedDuration)
    }

    private var selectedZoomID: CGFloat? {
        state.zoomOptions.first(where: {
            abs(state.zoomFactor - $0.deviceFactor) < 0.15
        })?.id
    }

    private var selectionAnimation: Animation? {
        reduceMotion
            ? nil
            : .spring(response: 0.24, dampingFraction: 0.78)
    }

    private var captureControls: some View {
        HStack(alignment: .center) {
            Button(action: onOpenLibrary) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                        .frame(width: 54, height: 54)
                        .overlay { libraryThumbnail }

                    if todayClipCount > 0 {
                        Text("\(todayClipCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.black)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(.white)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(Color.black.opacity(0.55), lineWidth: 2)
                            }
                            .offset(x: 7, y: 7)
                    }
                }
            }
            .buttonStyle(SquishableButtonStyle())
            .opacity(state.isRecording ? 0.18 : 1)
            .scaleEffect(state.isRecording ? 0.92 : 1)
            .allowsHitTesting(!state.isRecording)
            .accessibilityLabel(L10n.text("日別ライブラリ。今日%d本", todayClipCount))
            .accessibilityIdentifier("capture.library")

            Spacer()

            Button(action: onShutter) {
                CaptureShutterButtonContent(state: state)
            }
            .buttonStyle(SquishableButtonStyle())
            .disabled(!state.isShutterEnabled)
            .accessibilityLabel(state.isRecording ? L10n.text("録画を停止") : L10n.text("録画を開始"))
            .accessibilityIdentifier("capture.shutter")
            .accessibilityHint(state.isRecording ? L10n.text("タップすると録画を停止して保存します") : L10n.text("%d秒の動画を撮影します", Int(state.selectedDuration)))

            Spacer()

            Button(action: onSwitchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(SquishableButtonStyle())
            .opacity(state.isRecording ? 0.18 : 1)
            .scaleEffect(state.isRecording ? 0.92 : 1)
            .disabled(state.isRecording)
            .accessibilityLabel("前後のカメラを切り替える")
            .accessibilityIdentifier("capture.camera.switch")
        }
    }

    @ViewBuilder
    private var libraryThumbnail: some View {
        if let latestThumbnail {
            Image(uiImage: latestThumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous))
        } else {
            Image(systemName: "photo.stack")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct CaptureShutterButtonContent: View {
    let state: CaptureScreenState

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 3)
                .frame(width: 88, height: 88)

            if state.isRecording {
                Circle()
                    .trim(from: 0, to: state.recordingProgress)
                    .stroke(DaylogModernTheme.recording, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 98, height: 98)
                    .rotationEffect(.degrees(-90))
            }

            RoundedRectangle(cornerRadius: state.isRecording ? 12 : 36, style: .continuous)
                .fill(state.isRecording ? DaylogModernTheme.recording : Color.white)
                .frame(width: state.isRecording ? 34 : 62, height: state.isRecording ? 34 : 62)
        }
    }
}

struct CaptureIntroCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "record.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(DaylogModernTheme.accent)
                Text("一瞬ずつ、一日を残す。")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(DaylogModernTheme.foreground)
                Text("秒数を選んで、中央のボタンを押すだけ。\n撮影と音声のため、次にカメラとマイクの使用を確認します。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DaylogModernTheme.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onDismiss) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(DaylogModernTheme.accent)
                        .clipShape(Circle())
                }
                .accessibilityLabel("はじめる")
                .accessibilityIdentifier("capture.intro.start")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .background(DaylogModernTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 24, y: 8)
            .padding(16)
        }
        .background(Color.black.opacity(0.24).ignoresSafeArea())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct CaptureCapsuleActionButton: View {
    let systemName: String
    let tint: Color
    var isEnabled: Bool = true
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isEnabled ? tint : Color.white.opacity(0.35))
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.42))
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CapturePermissionCard: View {
    let message: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("権限を確認してください")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
            Button("設定を開く", action: onOpenSettings)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DaylogModernTheme.accent)
                .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}
