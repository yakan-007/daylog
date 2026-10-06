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
}

struct CaptureScreenView<Preview: View>: View {
    let state: CaptureScreenState
    let latestThumbnail: UIImage?
    let todayTimeline: CaptureTodayTimeline
    let coachMark: CaptureCoachMark?
    let actions: CaptureScreenActions
    private let preview: Preview

    /// 上部バーの下端と、下の操作部の上端（グローバル座標）。この間だけでピント合わせを受け付ける。
    @State private var topChromeBottom: CGFloat = 0
    @State private var dockTop: CGFloat = .greatestFiniteMagnitude

    init(
        state: CaptureScreenState,
        latestThumbnail: UIImage?,
        todayTimeline: CaptureTodayTimeline,
        coachMark: CaptureCoachMark? = nil,
        actions: CaptureScreenActions,
        @ViewBuilder preview: () -> Preview
    ) {
        self.state = state
        self.latestThumbnail = latestThumbnail
        self.todayTimeline = todayTimeline
        self.coachMark = coachMark
        self.actions = actions
        self.preview = preview()
    }

    var body: some View {
        ZStack {
            preview
                .ignoresSafeArea()

            CameraInteractionSurface(
                isEnabled: state.isReadyToRecord && !state.isRecording,
                focusableRect: focusableGlobalRect,
                focusPoint: state.focusPoint,
                onTap: actions.onFocus,
                onLongPress: actions.onLockFocusAndExposure,
                onExposureChanged: actions.onExposureChanged,
                onExposureEnded: actions.onExposureEnded,
                onZoomChanged: actions.onZoomChanged,
                onZoomEnded: actions.onZoomEnded
            )
            .ignoresSafeArea()

            // 上下だけを少し落として、白い操作部を映像の上でも読めるようにする。
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.32), location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.5), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if state.isGridVisible {
                CameraGridOverlay()
                    .allowsHitTesting(false)
            }

            // 操作面と同じく全画面の座標で描く（安全領域ぶんズレないように）。
            GeometryReader { proxy in
                if state.isFocusIndicatorVisible, let point = state.focusPoint {
                    FocusRingView(
                        point: point,
                        bounds: focusableLocalRect(in: proxy),
                        exposureBias: state.exposureBias,
                        exposureBiasRange: state.exposureBiasRange,
                        isLocked: state.isFocusAndExposureLocked
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                CaptureTopBar(
                    state: state,
                    todayTimeline: todayTimeline,
                    onToggleTorch: actions.onToggleTorch,
                    onToggleGrid: actions.onToggleGrid,
                    onOpenSettings: actions.onOpenSettings,
                    onOpenToday: actions.onOpenLibrary
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { value in
                    topChromeBottom = value
                }
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
                    todayTimeline: todayTimeline,
                    coachMark: coachMark,
                    onSelectDuration: actions.onSelectDuration,
                    onSelectZoom: actions.onSelectZoom,
                    onOpenLibrary: actions.onOpenLibrary,
                    onShutter: actions.onShutter,
                    onSwitchCamera: actions.onSwitchCamera
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minY
                } action: { value in
                    dockTop = value
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 10)
            .padding(.horizontal, 8)

        }
        .background(Color.black.ignoresSafeArea())
    }

    /// ピント合わせを受け付ける範囲（グローバル座標）。左右は画面いっぱい。
    private var focusableGlobalRect: CGRect {
        let margin: CGFloat = 8
        let top = topChromeBottom + margin
        let bottom = dockTop - margin
        // 計測前や極端に狭い場合は制限しない。
        guard bottom.isFinite, bottom - top > 120 else { return .infinite }
        return CGRect(x: -10_000, y: top, width: 20_000, height: bottom - top)
    }

    private func focusableLocalRect(in proxy: GeometryProxy) -> CGRect {
        let size = proxy.size
        let rect = focusableGlobalRect
        guard !rect.isInfinite else { return CGRect(origin: .zero, size: size) }
        let originY = proxy.frame(in: .global).minY
        return CGRect(x: 0, y: rect.minY - originY, width: size.width, height: rect.height)
    }
}

private struct CameraInteractionSurface: UIViewRepresentable {
    let isEnabled: Bool
    /// ウィンドウ座標。ここから外れたタップ・長押し・明るさ調整は受け付けない。
    let focusableRect: CGRect
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
        tap.delegate = context.coordinator
        longPress.delegate = context.coordinator

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
            // ピンチ（ズーム）は画面のどこからでも。
            if gestureRecognizer is UIPinchGestureRecognizer {
                return true
            }
            // 上部バーや下の操作部の上では、ピントを合わせない。
            guard parent.focusableRect.contains(gestureRecognizer.location(in: nil)) else {
                return false
            }
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
            todayTimeline: CaptureTodayTimeline(
                clipDates: [-9, -6.5, -6, -3.2, -1].map { Date().addingTimeInterval($0 * 3_600) }
            ),
            coachMark: .shutter,
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
                onSelectZoom: { _ in }
            )
        ) {
            LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .previewDisplayName("Capture")
    }
}
#endif
