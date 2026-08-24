import SwiftUI
import UIKit

struct CaptureScreenActions {
    let onToggleTorch: () -> Void
    let onToggleGrid: () -> Void
    let onOpenSystemSettings: () -> Void
    let onOpenSettings: () -> Void
    let onSelectDuration: (TimeInterval) -> Void
    let onOpenLibrary: () -> Void
    let onShutter: () -> Void
    let onSwitchCamera: () -> Void
    let onFocus: (CGPoint) -> Void
    let onLockFocusAndExposure: (CGPoint) -> Void
    let onExposureChanged: (CGFloat) -> Void
    let onExposureEnded: () -> Void
    let onZoomChanged: (CGFloat) -> Void
    let onZoomEnded: () -> Void
    let onSelectZoom: (CGFloat) -> Void
    let onDismissIntro: () -> Void
}

struct CaptureScreenView<Preview: View>: View {
    let state: CaptureScreenState
    let latestThumbnail: UIImage?
    let todayClipCount: Int
    let showsIntro: Bool
    let actions: CaptureScreenActions
    private let preview: Preview

    init(
        state: CaptureScreenState,
        latestThumbnail: UIImage?,
        todayClipCount: Int,
        showsIntro: Bool,
        actions: CaptureScreenActions,
        @ViewBuilder preview: () -> Preview
    ) {
        self.state = state
        self.latestThumbnail = latestThumbnail
        self.todayClipCount = todayClipCount
        self.showsIntro = showsIntro
        self.actions = actions
        self.preview = preview()
    }

    var body: some View {
        ZStack {
            preview
                .ignoresSafeArea()

            CameraInteractionSurface(
                isEnabled: state.isReadyToRecord && !state.isRecording,
                focusPoint: state.focusPoint,
                onTap: actions.onFocus,
                onLongPress: actions.onLockFocusAndExposure,
                onExposureChanged: actions.onExposureChanged,
                onExposureEnded: actions.onExposureEnded,
                onZoomChanged: actions.onZoomChanged,
                onZoomEnded: actions.onZoomEnded
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .black.opacity(0.64)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if state.isGridVisible {
                CameraGridOverlay()
                    .allowsHitTesting(false)
            }

            GeometryReader { _ in
                if state.isFocusIndicatorVisible, let point = state.focusPoint {
                    FocusRingView(
                        point: point,
                        exposureBias: state.exposureBias,
                        exposureBiasRange: state.exposureBiasRange,
                        isLocked: state.isFocusAndExposureLocked
                    )
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                CaptureTopBar(
                    state: state,
                    onToggleTorch: actions.onToggleTorch,
                    onToggleGrid: actions.onToggleGrid,
                    onOpenSettings: actions.onOpenSettings
                )
                Spacer()
                CaptureCenterStatus(
                    statusText: state.statusText,
                    permissionMessage: state.permissionMessage,
                    onOpenSystemSettings: actions.onOpenSystemSettings
                )
                Spacer()
                CaptureBottomDock(
                    state: state,
                    latestThumbnail: latestThumbnail,
                    todayClipCount: todayClipCount,
                    onSelectDuration: actions.onSelectDuration,
                    onSelectZoom: actions.onSelectZoom,
                    onOpenLibrary: actions.onOpenLibrary,
                    onShutter: actions.onShutter,
                    onSwitchCamera: actions.onSwitchCamera
                )
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.horizontal, DaylogModernTheme.pagePadding)

            if showsIntro {
                CaptureIntroCard(onDismiss: actions.onDismissIntro)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

}

private struct CameraInteractionSurface: UIViewRepresentable {
    let isEnabled: Bool
    let focusPoint: CGPoint?
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void
    let onExposureChanged: (CGFloat) -> Void
    let onExposureEnded: () -> Void
    let onZoomChanged: (CGFloat) -> Void
    let onZoomEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        tap.require(toFail: longPress)

        let exposurePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleExposurePan(_:))
        )
        exposurePan.minimumNumberOfTouches = 1
        exposurePan.maximumNumberOfTouches = 1
        exposurePan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(exposurePan)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraInteractionSurface

        init(parent: CameraInteractionSurface) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let view = gesture.view else { return }
            parent.onTap(gesture.location(in: view))
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let view = gesture.view else { return }
            parent.onLongPress(gesture.location(in: view))
        }

        @objc func handleExposurePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began, .changed:
                parent.onExposureChanged(gesture.translation(in: view).y)
            case .ended, .cancelled, .failed:
                parent.onExposureEnded()
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                parent.onZoomChanged(gesture.scale)
            case .ended, .cancelled, .failed:
                parent.onZoomEnded()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }
            guard let focusPoint = parent.focusPoint,
                  let view = pan.view else { return false }
            let point = pan.location(in: view)
            return hypot(point.x - focusPoint.x, point.y - focusPoint.y) <= 120
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer
                || otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}

#if DEBUG
private struct CaptureScreenViewPreviews: PreviewProvider {
    static var previews: some View {
        CaptureScreenView(
            state: CaptureScreenState(
                selectedDuration: 3,
                durationOptions: CapturePresenter.durationOptions,
                isRecording: false,
                recordingProgress: 0,
                statusText: nil,
                isReadyToRecord: true,
                isTorchEnabled: false,
                isTorchAvailable: true,
                isGridVisible: true,
                zoomFactor: 1,
                zoomOptions: [
                    CameraZoomOption(deviceFactor: 1, displayFactor: 0.5),
                    CameraZoomOption(deviceFactor: 2, displayFactor: 1),
                    CameraZoomOption(deviceFactor: 4, displayFactor: 2),
                    CameraZoomOption(deviceFactor: 10, displayFactor: 5)
                ],
                focusPoint: nil,
                isFocusIndicatorVisible: false,
                exposureBias: 0,
                exposureBiasRange: -2...2,
                isFocusAndExposureLocked: false,
                permissionMessage: nil
            ),
            latestThumbnail: nil,
            todayClipCount: 4,
            showsIntro: false,
            actions: CaptureScreenActions(
                onToggleTorch: {},
                onToggleGrid: {},
                onOpenSystemSettings: {},
                onOpenSettings: {},
                onSelectDuration: { _ in },
                onOpenLibrary: {},
                onShutter: {},
                onSwitchCamera: {},
                onFocus: { _ in },
                onLockFocusAndExposure: { _ in },
                onExposureChanged: { _ in },
                onExposureEnded: {},
                onZoomChanged: { _ in },
                onZoomEnded: {},
                onSelectZoom: { _ in },
                onDismissIntro: {}
            )
        ) {
            LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .previewDisplayName("Capture")
    }
}
#endif
