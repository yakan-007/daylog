import SwiftUI
import PhotosUI
import Photos
import CoreMotion
import AVFoundation

// Custom Button Style for visual feedback on press
struct SquishableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.05), value: configuration.isPressed)
    }
}

struct GridView: View {
    var body: some View {
        ZStack {
            HStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1)
                Spacer()
            }
            VStack {
                Spacer()
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var captureViewModel = CaptureScreenViewModel()
    @AppStorage("hasSeenCaptureOnboarding") private var hasSeenCaptureOnboarding: Bool = false
    
    // Motion-based orientation so icons rotate even with UI lock
    final class MotionOrientationManager: ObservableObject {
        private let motion = CMMotionManager()
        @Published var angle: Angle = .degrees(0)
        func start() {
            guard motion.isDeviceMotionAvailable else { return }
            motion.deviceMotionUpdateInterval = 0.2
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let g = data?.gravity else { return }
                if abs(g.x) > abs(g.y) {
                    // Landscape
                    self?.angle = Angle.degrees(g.x > 0 ? -90 : 90)
                } else {
                    // Portrait or upside down
                    self?.angle = Angle.degrees(g.y < 0 ? 0 : 180)
                }
            }
        }
        func stop() {
            motion.stopDeviceMotionUpdates()
        }
    }

    @StateObject private var motionOrientation = MotionOrientationManager()
    private var iconAngle: Angle { motionOrientation.angle }
    private var hudState: CaptureHUDState {
        CaptureHUDState.from(
            isSessionReady: cameraService.isSessionReady,
            isSessionInterrupted: cameraService.isSessionInterrupted,
            isRecording: captureViewModel.isCaptureUIActive,
            isReadyToRecord: cameraService.isReadyToRecord,
            readinessReason: cameraService.captureReadinessReason
        )
    }

    var body: some View {
        ZStack {
            // The camera view, with gestures, is the base layer.
            cameraViewWithGestures

            // The ZStack for indicators that appear in the center.
            ZStack {
                if captureViewModel.showGrid { GridView() }
                GeometryReader { geo in
                    if captureViewModel.showFocusIndicator, let point = captureViewModel.focusPoint { focusIndicator(at: point, in: geo.size) }
                }
                if captureViewModel.showZoomIndicator { zoomIndicator() }
            }
            .opacity(cameraService.isSessionReady ? 1 : 0)
            .animation(.easeInOut, value: cameraService.isSessionReady)

            // Top and Bottom bars are placed directly in the main ZStack.
            CameraTopControlBar(
                compact: hudState.shouldCompactControls,
                isTorchOn: captureViewModel.isTorchOn,
                isTorchAvailable: cameraService.isTorchAvailable,
                isGridOn: captureViewModel.showGrid,
                iconAngle: iconAngle,
                onTorch: { captureViewModel.isTorchOn.toggle() },
                onGrid: { captureViewModel.showGrid.toggle() },
                onSettings: { captureViewModel.showSettings = true }
            )
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(cameraService.isSessionReady ? (captureViewModel.isCaptureUIActive ? 0.22 : 1) : 0)
                .animation(.easeInOut(duration: 0.2), value: cameraService.isSessionReady)
                .animation(.easeInOut(duration: 0.2), value: captureViewModel.isCaptureUIActive)

            CameraBottomControlBar(
                compact: hudState.shouldCompactControls,
                durations: captureViewModel.durations,
                selectedDuration: $captureViewModel.selectedDuration,
                iconAngle: iconAngle,
                latestThumbnail: captureViewModel.latestThumbnail,
                isRecording: captureViewModel.isCaptureUIActive,
                recordingProgress: captureViewModel.recordingProgress,
                isReadyToRecord: cameraService.isReadyToRecord,
                readinessHint: captureReadinessHint,
                onOpenLibrary: { captureViewModel.showPhotoSheet = true },
                onShutter: {
                    captureViewModel.handleShutterTap(cameraService: cameraService)
                },
                onSwitchCamera: { cameraService.switchCamera() }
            )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(cameraService.isSessionReady ? (captureViewModel.isCaptureUIActive ? 0.88 : 1) : 0)
                .animation(.easeInOut(duration: 0.2), value: cameraService.isSessionReady)
                .animation(.easeInOut(duration: 0.2), value: captureViewModel.isCaptureUIActive)

            // Loading indicator shown on top when the session is not ready.
            if !cameraService.isSessionReady {
                Color.black.ignoresSafeArea()
                StatusChip(text: "カメラを準備中...")
                    .transition(.opacity.combined(with: .scale))
            }

            // Session interruption overlay
            if cameraService.isSessionInterrupted {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("カメラが一時的に使用できません")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                    Button(action: { cameraService.restartSession() }) {
                        Text("再試行")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .foregroundColor(AppTheme.onAccent)
                            .clipShape(Capsule())
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusM))
                .shadow(radius: 10)
            }

        }
        .onChange(of: captureViewModel.isTorchOn) { _, newValue in
            cameraService.toggleTorch(on: newValue)
        }
        .onChange(of: captureViewModel.exposureValue) { _, newValue in
            cameraService.setExposure(bias: newValue)
        }
        .onChange(of: cameraService.cameraPosition) { _, newPos in
            captureViewModel.handleCameraPositionChanged(newPosition: newPos, cameraService: cameraService)
        }
        .onChange(of: cameraService.isTorchAvailable) { _, available in
            captureViewModel.handleTorchAvailabilityChanged(available)
        }
        .onChange(of: cameraService.isSessionReady) { _, ready in
            captureViewModel.handleSessionReadyChanged(ready, cameraService: cameraService)
        }
        .onAppear {
            cameraService.checkForPermissions()
            motionOrientation.start()
            captureViewModel.initializeZoom(cameraService: cameraService)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                captureViewModel.updateLatestThumbnail()
            }
            if !hasSeenCaptureOnboarding {
                captureViewModel.showCaptureOnboarding = true
                hasSeenCaptureOnboarding = true
            }
        }
        .onDisappear { motionOrientation.stop() }
        .onChange(of: cameraService.isRecording) { _, rec in
            captureViewModel.handleRecordingChanged(rec)
        }
        .onChange(of: cameraService.lastSavedAssetLocalIdentifier) { _, id in
            guard let id else { return }
            captureViewModel.updateLatestThumbnail(preferredAssetIdentifier: id)
        }
        .sheet(isPresented: $captureViewModel.showPhotoSheet) {
            PhotoSheetView()
        }
        .sheet(isPresented: $captureViewModel.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $captureViewModel.showCaptureOnboarding) {
            CaptureOnboardingView {
                captureViewModel.showCaptureOnboarding = false
            }
        }
        .alert(cameraService.permissionAlertTitle, isPresented: $cameraService.permissionDenied) {
            Button("設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text(cameraService.permissionAlertMessage)
        }
        // Export UI intentionally removed: keep capture flow uninterrupted
    }
    
    // MARK: - Gestures
    var cameraViewWithGestures: some View {
        CameraView(cameraService: cameraService)
            .ignoresSafeArea()
            .simultaneousGesture(pinchToZoomGesture)
            .simultaneousGesture(tapToFocusGesture)
    }

    var tapToFocusGesture: some Gesture {
        SpatialTapGesture().onEnded { event in
            captureViewModel.setFocusPoint(event.location)
            cameraService.focus(at: event.location)
        }
    }
    
    var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                captureViewModel.applyPinchChanged(value, cameraService: cameraService)
            }
            .onEnded { _ in
                captureViewModel.applyPinchEnded(cameraService: cameraService)
            }
    }
    
    // MARK: - UI Components
    
    @ViewBuilder
    private func focusIndicator(at point: CGPoint, in size: CGSize) -> some View {
        let boxWidth: CGFloat = 75
        let spacing: CGFloat = 12
        let sliderWidth: CGFloat = 120
        let margin: CGFloat = 8
        let needsLeft = (point.x + boxWidth + spacing + sliderWidth + margin) > size.width
        let offset: CGFloat = 80
        let posX = needsLeft ? max(margin + (boxWidth + (captureViewModel.showExposureSlider ? sliderWidth + spacing : 0)) / 2,
                                   point.x - offset)
                              : min(size.width - margin - (boxWidth + (captureViewModel.showExposureSlider ? sliderWidth + spacing : 0)) / 2,
                                   point.x + offset)

        let sliderView = VStack(spacing: 8) {
            Image(systemName: "sun.max.fill").foregroundColor(.yellow)
            Slider(value: $captureViewModel.exposureValue, in: -1.5...1.5, step: 0.1)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: sliderWidth, height: sliderWidth)
        .transition(.opacity)

        Group {
            if needsLeft {
                HStack(spacing: spacing) {
                    if captureViewModel.showExposureSlider { sliderView }
                    Rectangle().stroke(Color.yellow, lineWidth: 2).frame(width: boxWidth, height: boxWidth)
                }
            } else {
                HStack(spacing: spacing) {
                    Rectangle().stroke(Color.yellow, lineWidth: 2).frame(width: boxWidth, height: boxWidth)
                    if captureViewModel.showExposureSlider { sliderView }
                }
            }
        }
        .position(x: posX, y: point.y)
        .transition(.opacity.combined(with: .scale))
    }
    
    @ViewBuilder
    private func zoomIndicator() -> some View {
        Text(String(format: "%.1fx", captureViewModel.clampZoom(captureViewModel.currentZoomFactor, cameraService: cameraService)))
            .font(AppTheme.bodyFont.weight(.bold))
            .foregroundColor(AppTheme.onGlass)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(Capsule().stroke(AppTheme.accent.opacity(0.9), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 4)
            .transition(.opacity)
    }
    
    // MARK: - Helper Functions

    private var captureReadinessHint: String? {
        captureViewModel.captureReadinessHint(cameraService: cameraService)
    }
}

// MARK: - View Helpers (none required for iOS 17+)

private struct CaptureOnboardingView: View {
    var onStart: () -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 18) {
                Text("最短で撮る3ステップ")
                    .font(.system(size: 24, weight: .bold))
                step(title: "1. 秒数を選ぶ", detail: "下部の 1〜5 秒をタップ")
                step(title: "2. シャッターを押す", detail: "準備完了後に中央ボタンで撮影")
                step(title: "3. 右下で切替", detail: "前後カメラをすぐ変更できます")
                Spacer()
                Button(action: onStart) {
                    Text("撮影をはじめる")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accent)
                        .foregroundColor(AppTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("撮影をはじめる")
                .accessibilityHint("オンボーディングを閉じてカメラ画面に戻ります")
            }
            .padding(20)
            .navigationTitle("使い方")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func step(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(detail)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}
