import AVFoundation
import Combine
import SwiftUI

protocol CaptureUseCase {
    func prepare() async
    func startRecording(duration: TimeInterval) async throws
    func stopRecording() async
    func switchCamera() async
    func setTorch(enabled: Bool) async
    func setZoom(factor: CGFloat) async
    func focus(at point: CGPoint) async
}

final class CameraSessionService {
    private let sessionController: CameraSessionController

    init(cameraService: CameraService) {
        self.sessionController = cameraService.sessionController
    }

    func prepareSession() {
        sessionController.prepareSession()
    }

    func switchCamera() {
        sessionController.switchCamera()
    }

    func setTorch(enabled: Bool) {
        sessionController.setTorch(enabled: enabled)
    }

    func setZoom(factor: CGFloat) {
        sessionController.setZoom(factor: factor)
    }

    func focus(at point: CGPoint) {
        sessionController.focus(at: point)
    }
}

final class VideoRecordingService {
    private let recordingController: VideoRecordingController

    init(cameraService: CameraService) {
        self.recordingController = cameraService.recordingController
    }

    func startRecording(duration: TimeInterval) {
        recordingController.startRecording(duration: duration, orientation: .portrait)
    }

    func stopRecording() {
        recordingController.stopRecording()
    }
}

final class DefaultCaptureUseCase: CaptureUseCase {
    let cameraService: CameraService
    private let sessionService: CameraSessionService
    private let recordingService: VideoRecordingService

    init(cameraService: CameraService) {
        self.cameraService = cameraService
        self.sessionService = CameraSessionService(cameraService: cameraService)
        self.recordingService = VideoRecordingService(cameraService: cameraService)
    }

    func prepare() async {
        await MainActor.run {
            sessionService.prepareSession()
        }
    }

    func startRecording(duration: TimeInterval) async throws {
        await MainActor.run {
            recordingService.startRecording(duration: duration)
        }
    }

    func stopRecording() async {
        await MainActor.run {
            recordingService.stopRecording()
        }
    }

    func switchCamera() async {
        await MainActor.run {
            sessionService.switchCamera()
        }
    }

    func setTorch(enabled: Bool) async {
        await MainActor.run {
            sessionService.setTorch(enabled: enabled)
        }
    }

    func setZoom(factor: CGFloat) async {
        await MainActor.run {
            sessionService.setZoom(factor: factor)
        }
    }

    func focus(at point: CGPoint) async {
        await MainActor.run {
            sessionService.focus(at: point)
        }
    }
}

@MainActor
final class CaptureFeatureViewModel: ObservableObject {
    @Published var state = CaptureState()
    @Published var showGrid = false
    @Published var showSettings = false
    @Published var focusPoint: CGPoint?
    @Published var showFocusIndicator = false
    @Published var currentZoomFactor: CGFloat = 1
    @Published var latestSavedAssetIdentifier: String?
    @Published var showPermissionCard = false
    @Published var permissionTitle = "アクセスが必要です"
    @Published var permissionMessage = ""

    let cameraService: CameraService
    private let useCase: DefaultCaptureUseCase
    private var cancellables: Set<AnyCancellable> = []
    private var progressTimer: Timer?
    private var lastZoomFactor: CGFloat = 1

    init(useCase: DefaultCaptureUseCase) {
        self.useCase = useCase
        self.cameraService = useCase.cameraService
        bindCameraState()
    }

    deinit {
        progressTimer?.invalidate()
    }

    func prepare() {
        Task {
            await useCase.prepare()
        }
    }

    func handleShutterTap() {
        if cameraService.isRecording {
            Task { await useCase.stopRecording() }
            return
        }
        guard cameraService.isReadyToRecord else { return }
        FeedbackManager.shared.triggerFeedback(soundEnabled: true)
        Task {
            try? await useCase.startRecording(duration: state.selectedDuration)
        }
    }

    func toggleTorch() {
        state.torchEnabled.toggle()
        let enabled = state.torchEnabled
        Task {
            await useCase.setTorch(enabled: enabled)
        }
    }

    func switchCamera() {
        FeedbackManager.shared.triggerFeedback(soundEnabled: false)
        Task {
            await useCase.switchCamera()
        }
    }

    func setDuration(_ duration: TimeInterval) {
        state.selectedDuration = duration
    }

    func focus(at point: CGPoint) {
        focusPoint = point
        withAnimation(.easeOut(duration: 0.18)) {
            showFocusIndicator = true
        }
        Task {
            await useCase.focus(at: point)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            withAnimation(.easeOut(duration: 0.18)) {
                self?.showFocusIndicator = false
            }
        }
    }

    func applyPinchChanged(_ value: CGFloat) {
        let requestedZoom = lastZoomFactor * value
        let range = cameraService.zoomRange
        let zoom = min(max(requestedZoom, max(1, range.lowerBound)), min(range.upperBound, 10))
        currentZoomFactor = zoom
        Task {
            await useCase.setZoom(factor: zoom)
        }
    }

    func applyPinchEnded() {
        lastZoomFactor = currentZoomFactor
    }

    func acknowledgeIndexedSave() {
        cameraService.acknowledgeIndexedSave()
    }

    func resumeCaptureMode() {
        cameraService.resumeCaptureMode()
    }

    func openSettingsApp() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var isShowingPermissionAlert: Binding<Bool> {
        Binding(
            get: { self.cameraService.permissionDenied },
            set: { self.cameraService.permissionDenied = $0 }
        )
    }

    var isReadyToRecord: Bool {
        if case .ready = state.session {
            return true
        }
        return false
    }

    var statusText: String? {
        switch state.recording {
        case .recording(_, let remaining):
            return "残り \(String(format: "%.1f", remaining)) 秒"
        case .saving(let phase):
            switch phase {
            case .recorded:
                return "保存準備中"
            case .processing:
                return "仕上げ中"
            case .saved:
                return "保存完了"
            case .indexed:
                return "今日に反映"
            case .idle:
                return nil
            }
        case .idle:
            switch state.session {
            case .preparing:
                return "カメラ準備中"
            case .interrupted:
                return "他アプリの使用終了を待っています"
            case .blocked:
                return "権限を確認してください"
            case .ready:
                return nil
            }
        }
    }

    private func bindCameraState() {
        cameraService.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.handleRecordingChanged(isRecording)
                self?.syncState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            cameraService.$isSessionReady,
            cameraService.$isSessionInterrupted,
            cameraService.$isTorchAvailable,
            cameraService.$savePhase
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.syncState()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            cameraService.$cameraPosition,
            cameraService.$captureReadinessReason,
            cameraService.$permissionDenied
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.syncState()
        }
        .store(in: &cancellables)

        cameraService.$lastSavedAssetLocalIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] identifier in
                self?.latestSavedAssetIdentifier = identifier
            }
            .store(in: &cancellables)
    }

    private func handleRecordingChanged(_ isRecording: Bool) {
        progressTimer?.invalidate()
        guard isRecording else { return }
        let duration = state.selectedDuration
        state.recording = .recording(progress: 0, remaining: duration)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .recording(let progress, let remaining) = self.state.recording else { return }
                let nextProgress = min(progress + (0.05 / max(duration, 0.1)), 1)
                let nextRemaining = max(0, remaining - 0.05)
                self.state.recording = .recording(progress: nextProgress, remaining: nextRemaining)
            }
        }
    }

    private func syncState() {
        state.permission = cameraService.permissionDenied ? .denied : .granted
        showPermissionCard = cameraService.permissionDenied
        permissionTitle = cameraService.permissionAlertTitle
        permissionMessage = cameraService.permissionAlertMessage
        if cameraService.isSessionInterrupted {
            state.session = .interrupted
        } else if cameraService.permissionDenied {
            state.session = .blocked(cameraService.captureReadinessReason)
        } else if cameraService.isReadyToRecord {
            state.session = .ready
        } else {
            state.session = .preparing
        }

        state.isTorchAvailable = cameraService.isTorchAvailable
        state.cameraPosition = cameraService.cameraPosition == .front ? .front : .back
        if !cameraService.isTorchAvailable {
            state.torchEnabled = false
        }

        if cameraService.isRecording == false {
            switch cameraService.savePhase {
            case .idle:
                if case .recording = state.recording {
                    state.recording = .idle
                } else if case .saving = state.recording {
                    state.recording = .idle
                }
            default:
                state.recording = .saving(cameraService.savePhase)
            }
        }
    }
}
