import Combine
import UIKit

struct CaptureFeatureState: Equatable {
    var engine = CameraEngineState()
    var selectedDuration: TimeInterval = 3
    var isTorchEnabled = false
    var isGridVisible = false
    var focusPoint: CGPoint?
    var isFocusIndicatorVisible = false
    var zoomFactor: CGFloat = 1
    var zoomOptions: [CameraZoomOption] = [.standard]
    var exposureBias: Float = 0
    var exposureBiasRange: ClosedRange<Float> = 0...0
    var isFocusAndExposureLocked = false
    var recordingProgress = 0.0
    var recordingRemaining: TimeInterval?
}

@MainActor
final class CaptureFeatureViewModel: ObservableObject {
    @Published private(set) var state: CaptureFeatureState

    let cameraService: CameraService
    private let settingsStore: DaylogSettingsStore
    private var cancellables: Set<AnyCancellable> = []
    private var progressTask: Task<Void, Never>?
    private var lastZoomFactor: CGFloat = 1
    private var exposureDragStart: Float?
    private var focusIndicatorGeneration = 0
    private var hasPrepared = false

    init(
        cameraService: CameraService,
        settingsStore: DaylogSettingsStore = DaylogSettingsStore()
    ) {
        self.cameraService = cameraService
        self.settingsStore = settingsStore
        let duration = CaptureDurationPolicy.normalized(settingsStore.selectedCaptureDuration)
        self.state = CaptureFeatureState(selectedDuration: duration)
        settingsStore.selectedCaptureDuration = duration
        bindCameraState()
    }

    deinit {
        progressTask?.cancel()
    }

    var screenState: CaptureScreenState {
        CapturePresenter.makeState(capture: state)
    }

    func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        cameraService.prepare()
    }

    func refreshPermissionsIfNeeded() {
        guard hasPrepared, state.engine.session == .blocked else { return }
        cameraService.prepare()
    }

    func handleShutterTap() {
        if state.engine.isRecording {
            cameraService.stopRecording()
            return
        }
        guard state.engine.session == .ready else { return }
        cameraService.startRecording(duration: state.selectedDuration)
    }

    func toggleTorch() {
        guard state.engine.isTorchAvailable else { return }
        let requestedValue = !state.isTorchEnabled
        state.isTorchEnabled = requestedValue
        cameraService.setTorch(on: requestedValue) { [weak self] actualValue in
            self?.state.isTorchEnabled = actualValue
        }
    }

    func toggleGrid() {
        state.isGridVisible.toggle()
    }

    func switchCamera() {
        resetVisibleCameraAdjustments()
        cameraService.switchCamera()
    }

    func setDuration(_ duration: TimeInterval) {
        let validDuration = CaptureDurationPolicy.normalized(duration)
        guard validDuration != state.selectedDuration else { return }
        state.selectedDuration = validDuration
        settingsStore.selectedCaptureDuration = validDuration
    }

    func focus(at point: CGPoint) {
        focusIndicatorGeneration += 1
        state.focusPoint = point
        state.isFocusIndicatorVisible = true
        state.exposureBias = 0
        state.isFocusAndExposureLocked = false
        exposureDragStart = nil
        cameraService.focus(at: point, locksFocusAndExposure: false)
        cameraService.setExposureBias(0)
        scheduleFocusIndicatorDismiss(after: 2.2)
    }

    func lockFocusAndExposure(at point: CGPoint) {
        focusIndicatorGeneration += 1
        state.focusPoint = point
        state.isFocusIndicatorVisible = true
        state.exposureBias = 0
        state.isFocusAndExposureLocked = true
        exposureDragStart = nil
        cameraService.focus(at: point, locksFocusAndExposure: true)
        cameraService.setExposureBias(0)
    }

    func applyExposureChanged(_ verticalTranslation: CGFloat) {
        guard state.focusPoint != nil,
              state.exposureBiasRange.lowerBound < state.exposureBiasRange.upperBound else {
            return
        }
        if exposureDragStart == nil {
            exposureDragStart = state.exposureBias
        }
        let start = exposureDragStart ?? state.exposureBias
        let requested = start - Float(verticalTranslation / 90)
        let bias = min(
            max(requested, state.exposureBiasRange.lowerBound),
            state.exposureBiasRange.upperBound
        )
        state.exposureBias = bias
        state.isFocusIndicatorVisible = true
        focusIndicatorGeneration += 1
        cameraService.setExposureBias(bias)
    }

    func applyExposureEnded() {
        exposureDragStart = nil
        guard !state.isFocusAndExposureLocked else { return }
        scheduleFocusIndicatorDismiss(after: 1.6)
    }

    func applyPinchChanged(_ value: CGFloat) {
        let requestedZoom = lastZoomFactor * value
        let range = cameraService.zoomRange
        let zoom = min(max(requestedZoom, max(1, range.lowerBound)), min(range.upperBound, 10))
        state.zoomFactor = zoom
        cameraService.setZoom(factor: zoom)
    }

    func applyPinchEnded() {
        lastZoomFactor = state.zoomFactor
    }

    func selectZoomFactor(_ factor: CGFloat) {
        let range = cameraService.zoomRange
        let zoom = min(max(factor, range.lowerBound), range.upperBound)
        guard zoom != state.zoomFactor else { return }
        state.zoomFactor = zoom
        lastZoomFactor = zoom
        cameraService.setZoom(factor: zoom)
    }

    func acknowledgeIndexedSave() {
        cameraService.acknowledgeIndexedSave()
    }

    func enterPlaybackMode() async {
        await cameraService.suspendCaptureMode()
        #if !targetEnvironment(simulator)
        AudioSessionMode.activatePlayback()
        #endif
    }

    func resumeCaptureMode() {
        cameraService.resumeCaptureMode()
    }

    func refreshPreviewOrientation() {
        cameraService.refreshPreviewOrientation()
    }

    func suspendCaptureMode() async {
        await cameraService.suspendCaptureMode()
    }

    func openSettingsApp() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func dismissPermissionAlert() {
        cameraService.dismissPermissionAlert()
    }

    func dismissSaveFailure() {
        cameraService.clearSaveError()
    }

    var permissionTitle: String {
        state.engine.permissionIssue?.title ?? L10n.text("アクセスが必要です")
    }

    var permissionMessage: String {
        state.engine.permissionIssue?.message ?? ""
    }

    var isPermissionAlertPresented: Bool {
        state.engine.isPermissionAlertPresented
    }

    var isSaveFailurePresented: Bool {
        state.engine.saveFailure != nil
    }

    var saveErrorMessage: String {
        let message = state.engine.saveFailure?.message ?? DaylogFailure.saveFailed.message
        guard state.engine.recoverableCapture != nil,
              state.engine.saveFailure != .unsavedCaptureAvailable else {
            return message
        }
        return L10n.text("%@ 撮影原本は端末内に保護されています。", message)
    }

    var saveErrorTitle: String {
        state.engine.saveFailure?.title ?? DaylogFailure.saveFailed.title
    }

    var saveErrorRequiresSettings: Bool {
        state.engine.saveFailure?.requiresSettings ?? false
    }

    var recoverableCaptureURL: URL? {
        state.engine.recoverableCapture?.url
    }

    var hasRecoverableCapture: Bool {
        recoverableCaptureURL != nil
    }

    func discardRecoverableCapture() {
        cameraService.discardRecoverableCapture()
    }

    private func bindCameraState() {
        cameraService.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] engine in
                guard let self else { return }
                let wasRecording = self.state.engine.isRecording
                let previousSession = self.state.engine.session
                self.state.engine = engine
                if !engine.isTorchAvailable {
                    self.state.isTorchEnabled = false
                }
                if wasRecording != engine.isRecording {
                    self.handleRecordingChanged(engine.isRecording)
                }
                if engine.session == .ready,
                   previousSession != .ready {
                    self.synchronizeCameraControls()
                }
                if !engine.isRecording, engine.savePhase == .idle {
                    self.state.recordingProgress = 0
                    self.state.recordingRemaining = nil
                }
            }
            .store(in: &cancellables)
    }

    private func synchronizeCameraControls() {
        state.zoomOptions = cameraService.zoomOptions
        state.zoomFactor = cameraService.currentZoomFactor
        lastZoomFactor = state.zoomFactor
        state.exposureBiasRange = cameraService.exposureBiasRange
        state.exposureBias = cameraService.currentExposureBias
        state.isFocusAndExposureLocked = false
        state.focusPoint = nil
        state.isFocusIndicatorVisible = false
        exposureDragStart = nil
    }

    private func resetVisibleCameraAdjustments() {
        focusIndicatorGeneration += 1
        state.focusPoint = nil
        state.isFocusIndicatorVisible = false
        state.exposureBias = 0
        state.exposureBiasRange = 0...0
        state.isFocusAndExposureLocked = false
        exposureDragStart = nil
    }

    private func scheduleFocusIndicatorDismiss(after delay: TimeInterval) {
        focusIndicatorGeneration += 1
        let generation = focusIndicatorGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.focusIndicatorGeneration == generation,
                  !self.state.isFocusAndExposureLocked else { return }
            self.state.isFocusIndicatorVisible = false
        }
    }

    private func handleRecordingChanged(_ isRecording: Bool) {
        progressTask?.cancel()
        progressTask = nil
        guard isRecording else {
            state.recordingRemaining = nil
            return
        }
        let duration = state.selectedDuration
        state.recordingProgress = 0
        state.recordingRemaining = duration
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled,
                      let self,
                      self.state.engine.isRecording,
                      let remaining = self.state.recordingRemaining else { return }
                self.state.recordingProgress = min(
                    self.state.recordingProgress + (0.05 / max(duration, 0.1)),
                    1
                )
                self.state.recordingRemaining = max(0, remaining - 0.05)
            }
        }
    }
}
