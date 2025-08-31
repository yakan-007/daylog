import SwiftUI
import PhotosUI
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
    
    // --- Features ---
    @State private var selectedDuration: TimeInterval = 3.0
    private let durations: [TimeInterval] = [1.0, 2.0, 3.0, 4.0, 5.0]
    @State private var recordingProgress: Double = 0.0
    @State private var progressTimer: Timer?
    @State private var currentOrientation: UIDeviceOrientation = .portrait
    @State private var showGrid: Bool = false
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var lastZoomFactor: CGFloat = 1.0
    @State private var showZoomIndicator: Bool = false
    @State private var showPhotoSheet: Bool = false
    @State private var showSettings: Bool = false
    @State private var isTorchOn: Bool = false
    @State private var exposureValue: Float = 0.0
    @State private var showExposureSlider: Bool = false
    @State private var exposureTimer: Timer?
    @State private var isCaptureUIActive: Bool = false
    
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

    var body: some View {
        ZStack {
            // The camera view, with gestures, is the base layer.
            cameraViewWithGestures

            // The ZStack for indicators that appear in the center.
            ZStack {
                if showGrid { GridView() }
                GeometryReader { geo in
                    if showFocusIndicator, let point = focusPoint { focusIndicator(at: point, in: geo.size) }
                }
                if showZoomIndicator { zoomIndicator() }
            }
            .opacity(cameraService.isSessionReady ? 1 : 0)
            .animation(.easeInOut, value: cameraService.isSessionReady)

            // Top and Bottom bars are placed directly in the main ZStack.
            topBar()
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(cameraService.isSessionReady ? 1 : 0)
                .animation(.easeInOut, value: cameraService.isSessionReady)

            bottomBar()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(cameraService.isSessionReady ? 1 : 0)
                .animation(.easeInOut, value: cameraService.isSessionReady)

            // Loading indicator shown on top when the session is not ready.
            if !cameraService.isSessionReady {
                Color.black.ignoresSafeArea()
                Text("カメラを準備中...")
                    .foregroundColor(.white)
                    .transition(.opacity)
            }
        }
        .onChange(of: isTorchOn) { _, newValue in
            cameraService.toggleTorch(on: newValue)
        }
        .onChange(of: exposureValue) { _, newValue in
            cameraService.setExposure(bias: newValue)
        }
        .onChange(of: cameraService.cameraPosition) { _, newPos in
            if newPos != .back { isTorchOn = false }
        }
        .onChange(of: cameraService.isTorchAvailable) { _, available in
            if !available { isTorchOn = false }
        }
        .onAppear {
            cameraService.checkForPermissions()
            motionOrientation.start()
        }
        .onDisappear { motionOrientation.stop() }
        .sheet(isPresented: $showPhotoSheet) {
            PhotoSheetView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("カメラへのアクセスが必要です", isPresented: $cameraService.permissionDenied) {
            Button("設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("このアプリの全機能を利用するには、設定アプリからカメラへのアクセスを許可してください。")
        }
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
            setFocusPoint(event.location)
            cameraService.focus(at: event.location)
        }
    }
    
    var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newZoomFactor = lastZoomFactor * value
                self.currentZoomFactor = newZoomFactor
                cameraService.setZoom(factor: newZoomFactor)
                withAnimation(.spring()) { self.showZoomIndicator = true }
            }
            .onEnded { value in
                self.lastZoomFactor = currentZoomFactor
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation(.spring()) { self.showZoomIndicator = false }
                }
            }
    }
    
    // MARK: - UI Components
    // The uiOverlay property is now removed. topBar and bottomBar are called directly.
    
    @ViewBuilder
    private func topBar() -> some View {
        HStack {
            Button(action: { isTorchOn.toggle() }) {
                Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20))
                    .foregroundColor(cameraService.isTorchAvailable ? (isTorchOn ? .yellow : .white) : .gray)
                    .rotationEffect(iconAngle)
            }
            .disabled(!cameraService.isTorchAvailable)
            .buttonStyle(SquishableButtonStyle())
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: { showGrid.toggle() }) {
                    Image(systemName: "squareshape.split.3x3")
                        .font(.system(size: 20))
                        .foregroundColor(showGrid ? Color(hex: 0xFFC857) : .white)
                        .rotationEffect(iconAngle)
                }
                .buttonStyle(SquishableButtonStyle())
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .rotationEffect(iconAngle)
                }
                .buttonStyle(SquishableButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassPanel(radius: 16)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bottomBar() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 20) {
                ForEach(durations, id: \.self) { d in
                    durationChip(d)
                }
            }
            
            HStack(alignment: .center, spacing: 20) {
                Button(action: { self.showPhotoSheet = true }) {
                    // Placeholder for photo library thumbnail
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24))
                        .rotationEffect(iconAngle)
                }
                .buttonStyle(SquishableButtonStyle())
                .frame(maxWidth: .infinity)

                Button(action: { if isCaptureUIActive { stopRecording() } else { startRecording() } }) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 3.5)
                            .frame(width: 70, height: 70)
                        
                        Rectangle()
                            .fill(isCaptureUIActive ? .red : .white)
                            .frame(width: isCaptureUIActive ? 30 : 60, height: isCaptureUIActive ? 30 : 60)
                            .cornerRadius(isCaptureUIActive ? 8 : 30)
                            .animation(.spring(), value: isCaptureUIActive)
                        
                        Circle()
                            .trim(from: 0.0, to: recordingProgress)
                            .stroke(Color(hex: 0xFFC857), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: { cameraService.switchCamera() }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 24))
                        .rotationEffect(iconAngle)
                }
                .buttonStyle(SquishableButtonStyle())
                .frame(maxWidth: .infinity)
            }
            .foregroundColor(.white)
        }
        .padding(.top, 16)
        .padding(.bottom, 32)
        .padding(.horizontal, 12)
        .glassPanel(radius: 20, shadowOpacity: 0.25)
    }

    private func durationChip(_ d: TimeInterval) -> some View {
        let isSel = (self.selectedDuration == d)
        let base = Text(String(format: "%.0fs", d))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isSel ? Color.black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .clipShape(Capsule())
            .rotationEffect(iconAngle)
        return Button(action: { self.selectedDuration = d }) {
            Group {
                if isSel {
                    base.background(Color(hex: 0xFFC857))
                } else {
                    base.background(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(SquishableButtonStyle())
    }
    
    @ViewBuilder
    private func focusIndicator(at point: CGPoint, in size: CGSize) -> some View {
        let boxWidth: CGFloat = 75
        let spacing: CGFloat = 12
        let sliderWidth: CGFloat = 120
        let margin: CGFloat = 8
        let needsLeft = (point.x + boxWidth + spacing + sliderWidth + margin) > size.width
        let offset: CGFloat = 80
        let posX = needsLeft ? max(margin + (boxWidth + (showExposureSlider ? sliderWidth + spacing : 0)) / 2,
                                   point.x - offset)
                              : min(size.width - margin - (boxWidth + (showExposureSlider ? sliderWidth + spacing : 0)) / 2,
                                   point.x + offset)

        let sliderView = VStack(spacing: 8) {
            Image(systemName: "sun.max.fill").foregroundColor(.yellow)
            Slider(value: $exposureValue, in: -1.5...1.5, step: 0.1)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: sliderWidth, height: sliderWidth)
        .transition(.opacity)

        Group {
            if needsLeft {
                HStack(spacing: spacing) {
                    if showExposureSlider { sliderView }
                    Rectangle().stroke(Color.yellow, lineWidth: 2).frame(width: boxWidth, height: boxWidth)
                }
            } else {
                HStack(spacing: spacing) {
                    Rectangle().stroke(Color.yellow, lineWidth: 2).frame(width: boxWidth, height: boxWidth)
                    if showExposureSlider { sliderView }
                }
            }
        }
        .position(x: posX, y: point.y)
        .transition(.opacity.combined(with: .scale))
    }
    
    @ViewBuilder
    private func zoomIndicator() -> some View {
        Text(String(format: "%.1fx", currentZoomFactor))
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(Capsule().stroke(Color(hex: 0xFFC857).opacity(0.9), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 4)
            .transition(.opacity)
    }
    
    // MARK: - Helper Functions
    private func setFocusPoint(_ point: CGPoint) {
        self.focusPoint = point
        self.exposureValue = 0
        
        withAnimation { 
            self.showFocusIndicator = true
            self.showExposureSlider = true
        }
        
        exposureTimer?.invalidate()
        exposureTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            withAnimation {
                self.showFocusIndicator = false
                self.showExposureSlider = false
            }
        }
    }
    
    private func startRecording() {
        FeedbackManager.shared.triggerFeedback(soundEnabled: true)
        isCaptureUIActive = true
        cameraService.startRecording(duration: selectedDuration, orientation: self.currentOrientation)
        startProgressTimer()
    }
    
    private func stopRecording() {
        FeedbackManager.shared.triggerFeedback(soundEnabled: true)
        cameraService.stopRecording()
        stopProgressTimer()
        isCaptureUIActive = false
    }
    
    private func startProgressTimer() {
        recordingProgress = 0.0
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            self.recordingProgress += 0.05 / self.selectedDuration
            if self.recordingProgress >= 1.0 { self.stopProgressTimer() }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        recordingProgress = 0.0
    }
}

// MARK: - View Helpers (none required for iOS 17+)
