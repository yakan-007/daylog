import CoreGraphics
import Foundation

struct CameraZoomOption: Equatable, Hashable, Identifiable, Sendable {
    let deviceFactor: CGFloat
    let displayFactor: CGFloat

    var id: CGFloat { deviceFactor }

    var title: String {
        let rounded = displayFactor.rounded()
        if abs(displayFactor - rounded) < 0.01 {
            return "\(Int(rounded))×"
        }
        return String(format: "%.1f×", displayFactor)
    }

    static let standard = CameraZoomOption(deviceFactor: 1, displayFactor: 1)
}

/// AVCaptureDevice内部の倍率と、利用者が見る0.5x/1x等を分離する。
enum CameraZoomPolicy {
    static func options(
        minimumDeviceFactor: CGFloat,
        maximumDeviceFactor: CGFloat,
        displayMultiplier: CGFloat,
        nativeDeviceFactors: [CGFloat]
    ) -> [CameraZoomOption] {
        let multiplier = normalizedMultiplier(displayMultiplier)
        let minimum = max(1, minimumDeviceFactor)
        let maximum = max(minimum, maximumDeviceFactor)
        let defaultFactor = defaultDeviceFactor(
            minimumDeviceFactor: minimum,
            maximumDeviceFactor: maximum,
            displayMultiplier: multiplier
        )
        let candidates = nativeDeviceFactors + [minimum, defaultFactor]
        var seenDisplayFactors: [CGFloat] = []

        return candidates
            .filter { $0 >= minimum - 0.001 && $0 <= maximum + 0.001 }
            .sorted()
            .compactMap { deviceFactor in
                let displayFactor = normalizedDisplayFactor(deviceFactor * multiplier)
                guard displayFactor >= 0.5 - 0.01, displayFactor <= 10 + 0.01 else {
                    return nil
                }
                guard !seenDisplayFactors.contains(where: {
                    abs($0 - displayFactor) < 0.05
                }) else {
                    return nil
                }
                seenDisplayFactors.append(displayFactor)
                return CameraZoomOption(
                    deviceFactor: deviceFactor,
                    displayFactor: displayFactor
                )
            }
    }

    static func defaultDeviceFactor(
        minimumDeviceFactor: CGFloat,
        maximumDeviceFactor: CGFloat,
        displayMultiplier: CGFloat
    ) -> CGFloat {
        let multiplier = normalizedMultiplier(displayMultiplier)
        return min(
            max(1 / multiplier, minimumDeviceFactor),
            maximumDeviceFactor
        )
    }

    private static func normalizedMultiplier(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : 1
    }

    private static func normalizedDisplayFactor(_ value: CGFloat) -> CGFloat {
        let nearestHalf = (value * 2).rounded() / 2
        if abs(value - nearestHalf) < 0.06 {
            return nearestHalf
        }
        return (value * 10).rounded() / 10
    }
}

struct CaptureScreenState: Equatable {
    let selectedDuration: TimeInterval
    let durationOptions: [TimeInterval]
    let isRecording: Bool
    let recordingProgress: Double
    let statusText: String?
    let isReadyToRecord: Bool
    let isTorchEnabled: Bool
    let isTorchAvailable: Bool
    let isGridVisible: Bool
    let zoomFactor: CGFloat
    let zoomOptions: [CameraZoomOption]
    let focusPoint: CGPoint?
    let isFocusIndicatorVisible: Bool
    let exposureBias: Float
    let exposureBiasRange: ClosedRange<Float>
    let isFocusAndExposureLocked: Bool
    let permissionMessage: String?

    var isShutterEnabled: Bool {
        isReadyToRecord || isRecording
    }
}

enum CapturePresenter {
    static let durationOptions = CaptureDurationPolicy.options

    static func makeState(capture: CaptureFeatureState) -> CaptureScreenState {
        return CaptureScreenState(
            selectedDuration: capture.selectedDuration,
            durationOptions: durationOptions,
            isRecording: capture.engine.isRecording,
            recordingProgress: capture.recordingProgress,
            statusText: statusText(for: capture),
            isReadyToRecord: capture.engine.session == .ready
                && capture.engine.savePhase == .idle,
            isTorchEnabled: capture.isTorchEnabled,
            isTorchAvailable: capture.engine.isTorchAvailable,
            isGridVisible: capture.isGridVisible,
            zoomFactor: capture.zoomFactor,
            zoomOptions: capture.zoomOptions,
            focusPoint: capture.focusPoint,
            isFocusIndicatorVisible: capture.isFocusIndicatorVisible,
            exposureBias: capture.exposureBias,
            exposureBiasRange: capture.exposureBiasRange,
            isFocusAndExposureLocked: capture.isFocusAndExposureLocked,
            permissionMessage: capture.engine.permissionIssue?.message
        )
    }

    private static func statusText(for capture: CaptureFeatureState) -> String? {
        if capture.engine.isRecording {
            let remaining = capture.recordingRemaining ?? capture.selectedDuration
            return L10n.text("残り %.1f 秒", remaining)
        }

        switch capture.engine.savePhase {
        case .recorded:
            return L10n.text("動画を保護中")
        case .processing:
            return L10n.text("動画を保存中")
        case .saved:
            return L10n.text("今日の一覧を更新中")
        case .indexed:
            return L10n.text("今日に追加しました")
        case .idle:
            switch capture.engine.session {
            case .preparing:
                return L10n.text("カメラ準備中")
            case .interrupted:
                return L10n.text("他アプリの使用終了を待っています")
            case .blocked:
                return L10n.text("権限を確認してください")
            case .unavailable:
                return L10n.text("カメラを使用できません")
            case .ready:
                return nil
            }
        }
    }
}
