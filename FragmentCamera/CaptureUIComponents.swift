import SwiftUI

enum CaptureHUDState: Equatable {
    case preparing
    case interrupted
    case idle
    case recording
    case blocked(CaptureReadinessReason)

    static func from(
        isSessionReady: Bool,
        isSessionInterrupted: Bool,
        isRecording: Bool,
        isReadyToRecord: Bool,
        readinessReason: CaptureReadinessReason
    ) -> CaptureHUDState {
        if isSessionInterrupted { return .interrupted }
        if !isSessionReady { return .preparing }
        if isRecording { return .recording }
        if isReadyToRecord { return .idle }
        return .blocked(readinessReason)
    }

    var shouldCompactControls: Bool {
        self == .recording
    }
}

struct StatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTheme.labelFont)
            .foregroundColor(AppTheme.onGlass.opacity(0.94))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .minimumScaleFactor(0.8)
            .lineLimit(1)
            .accessibilityLabel("録画状態")
            .accessibilityValue(text)
    }
}

struct SegmentedDurationControl: View {
    let durations: [TimeInterval]
    @Binding var selection: TimeInterval
    let iconAngle: Angle

    var body: some View {
        HStack(spacing: AppTheme.spacingS) {
            ForEach(durations, id: \.self) { d in
                let selected = selection == d
                Button {
                    selection = d
                } label: {
                    Text(durationLabel(d))
                        .font(AppTheme.labelFont)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .foregroundColor(selected ? AppTheme.onAccent : AppTheme.onGlass)
                        .frame(width: 44, height: 44)
                        .background(selected ? AppTheme.accent : AppTheme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.stroke, lineWidth: selected ? 0 : 1))
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel("録画時間 \(Int(d)) 秒")
            }
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        "\(Int(duration.rounded()))s"
    }
}

struct CaptureButton: View {
    let isRecording: Bool
    let progress: Double
    let isReady: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .strokeBorder(AppTheme.onGlass.opacity(0.9), lineWidth: 3.5)
                    .frame(width: 70, height: 70)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 30, style: .continuous)
                    .fill(isRecording ? AppTheme.danger : AppTheme.onGlass)
                    .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isRecording)

                Circle()
                    .trim(from: 0.0, to: progress)
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                if !isReady && !isRecording {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.onGlass)
                }
            }
            .frame(minWidth: 80, minHeight: 80)
        }
        .disabled(!isReady && !isRecording)
        .accessibilityLabel(isRecording ? "録画停止" : "録画開始")
    }
}

struct CameraTopControlBar: View {
    let compact: Bool
    let isTorchOn: Bool
    let isTorchAvailable: Bool
    let isGridOn: Bool
    let iconAngle: Angle
    let onTorch: () -> Void
    let onGrid: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Button(action: onTorch) {
                Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isTorchAvailable ? (isTorchOn ? .yellow : AppTheme.onGlass) : .gray)
                    .rotationEffect(iconAngle)
                    .frame(width: 44, height: 44)
            }
            .disabled(!isTorchAvailable)
            .buttonStyle(SquishableButtonStyle())
            .accessibilityLabel("ライト")
            .accessibilityHint("ライトのオン・オフを切り替えます")

            Spacer()

            HStack(spacing: AppTheme.spacingS) {
                Button(action: onGrid) {
                    Image(systemName: "squareshape.split.3x3")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(isGridOn ? AppTheme.accent : AppTheme.onGlass)
                        .rotationEffect(iconAngle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel("グリッド")
                .accessibilityHint("構図ガイドを表示または非表示にします")

                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(AppTheme.onGlass)
                        .rotationEffect(iconAngle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel("設定")
                .accessibilityHint("日付スタンプなどの設定を開きます")
            }
        }
        .padding(.horizontal, AppTheme.spacingM)
        .padding(.vertical, compact ? 8 : 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusM).stroke(AppTheme.stroke, lineWidth: 1))
        .padding(.horizontal, AppTheme.spacingM)
        .padding(.top, AppTheme.spacingS)
        .scaleEffect(compact ? 0.96 : 1)
        .opacity(compact ? 0.72 : 1)
        .animation(.easeInOut(duration: 0.2), value: compact)
    }
}

struct CameraBottomControlBar: View {
    let compact: Bool
    let durations: [TimeInterval]
    @Binding var selectedDuration: TimeInterval
    let iconAngle: Angle
    let latestThumbnail: UIImage?
    let isRecording: Bool
    let recordingProgress: Double
    let isReadyToRecord: Bool
    let readinessHint: String?
    let onOpenLibrary: () -> Void
    let onShutter: () -> Void
    let onSwitchCamera: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacingM) {
            if !compact {
                SegmentedDurationControl(durations: durations, selection: $selectedDuration, iconAngle: iconAngle)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .center, spacing: 20) {
                Button(action: onOpenLibrary) {
                    Group {
                        if let thumb = latestThumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusS, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.radiusS)
                                        .stroke(AppTheme.onGlass.opacity(0.92), lineWidth: 1)
                                )
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 24, weight: .semibold))
                                .rotationEffect(iconAngle)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(SquishableButtonStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel("ライブラリ")
                .accessibilityHint("保存済みの動画一覧を開きます")

                CaptureButton(
                    isRecording: isRecording,
                    progress: recordingProgress,
                    isReady: isReadyToRecord,
                    onTap: onShutter
                )
                .frame(maxWidth: .infinity)

                Button(action: onSwitchCamera) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .rotationEffect(iconAngle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SquishableButtonStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel("カメラ切替")
                .accessibilityHint("前面カメラと背面カメラを切り替えます")
            }
            .foregroundColor(AppTheme.onGlass)

            if let hint = readinessHint {
                StatusChip(text: hint)
            }
        }
        .padding(.top, AppTheme.spacingL)
        .padding(.bottom, 32)
        .padding(.horizontal, AppTheme.spacingM)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.radiusL).stroke(AppTheme.stroke, lineWidth: 1))
        .padding(.horizontal, AppTheme.spacingS)
        .animation(.easeInOut(duration: 0.2), value: compact)
    }
}
