import Combine
import CoreGraphics
@preconcurrency import AVFoundation
import OSLog

private enum CaptureReadinessReason: Equatable {
    case warmingUp
    case permissionsMissing
    case interrupted
    case ready
}

final class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var state = CameraEngineState() {
        didSet {
            // 準備中に戻ったら、準備完了の判定をやり直す（判定は一度出したら次のリセットまで止まる）。
            if state.session == .preparing, oldValue.session != .preparing {
                readinessMonitor.reset()
            }
        }
    }

    private let captureSession = CaptureSessionController()
    private var recordingTimer: Timer?
    private let readinessMonitor = CaptureReadinessMonitor()
    private var pendingStartDuration: TimeInterval?
    private var currentPlannedDuration: TimeInterval?
    private var sessionDidStartObserver: NSObjectProtocol?
    private let permissionService: CameraPermissionService
    private let settingsStore: VlogishSettingsStore
    private let temporaryFileStore: TemporaryFileStore
    private let captureRecoveryStore: CaptureRecoveryStore
    private let saveCoordinator: CaptureSaveCoordinator
    private var isCaptureModeSuspended = false
    private var captureModeGeneration = 0
    private var currentCapturedAt: Date?

    var session: AVCaptureSession { captureSession.session }
    var previewLayer: AVCaptureVideoPreviewLayer { captureSession.previewLayer }
    var zoomRange: ClosedRange<CGFloat> { captureSession.zoomRange }
    var zoomOptions: [CameraZoomOption] { captureSession.zoomOptions }
    var currentZoomFactor: CGFloat { captureSession.currentZoomFactor }
    var exposureBiasRange: ClosedRange<Float> { captureSession.exposureBiasRange }
    var currentExposureBias: Float { captureSession.currentExposureBias }

    init(
        permissionService: CameraPermissionService = CameraPermissionService(),
        postProcessPipeline: VideoPostProcessPipeline = VideoPostProcessPipeline(),
        assetLibraryWriter: AssetLibraryWriter = AssetLibraryWriter(albumName: AppIdentity.photoAlbumName),
        settingsStore: VlogishSettingsStore = VlogishSettingsStore(),
        temporaryFileStore: TemporaryFileStore = TemporaryFileStore(),
        locationService: CaptureLocationService = CaptureLocationService(),
        captureRecoveryStore: CaptureRecoveryStore = CaptureRecoveryStore(),
        stampRecipeStore: VideoStampRecipeStore = VideoStampRecipeStore(),
        placeNameResolver: any PlaceNameResolving = PlaceNameResolver()
    ) {
        self.permissionService = permissionService
        self.settingsStore = settingsStore
        self.temporaryFileStore = temporaryFileStore
        self.captureRecoveryStore = captureRecoveryStore
        let savePipeline = CaptureSavePipeline(
            postProcessPipeline: postProcessPipeline,
            assetLibraryWriter: assetLibraryWriter,
            stampRecipeStore: stampRecipeStore,
            temporaryFileStore: temporaryFileStore
        )
        self.saveCoordinator = CaptureSaveCoordinator(
            pipeline: savePipeline,
            settingsStore: settingsStore,
            locationService: locationService,
            placeNameResolver: placeNameResolver
        )
        super.init()
        if let recoverableCapture = captureRecoveryStore.recoverableCaptures().first {
            state.recoverableCapture = recoverableCapture
            state.saveFailure = .unsavedCaptureAvailable
        }
        sessionDidStartObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.handleSessionDidStartRunning()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruption(_:)), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruptionEnded(_:)), name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRuntimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit {
        if let sessionDidStartObserver {
            NotificationCenter.default.removeObserver(sessionDidStartObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func updateState(_ update: @escaping (inout CameraEngineState) -> Void) {
        if Thread.isMainThread {
            update(&state)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                update(&self.state)
            }
        }
    }

    private func updateCaptureReadiness(_ reason: CaptureReadinessReason) {
        updateState { state in
            let session: CameraSessionState
            switch reason {
            case .warmingUp:
                session = .preparing
            case .permissionsMissing:
                session = .blocked
            case .interrupted:
                session = .interrupted
            case .ready:
                session = .ready
            }
            guard state.session != session else { return }
            state.session = session
            switch reason {
            case .warmingUp:
                AppLog.capture.info("capture_state=warming_up")
            case .permissionsMissing:
                AppLog.capture.warning("capture_state=permissions_missing")
            case .interrupted:
                AppLog.capture.warning("capture_state=interrupted")
            case .ready:
                AppLog.capture.info("capture_state=ready")
            }
        }
    }

    private func setupSession() {
        // 1〜3秒の短い撮影でも位置情報が間に合うよう、録画開始前から取得する。
        saveCoordinator.prepareForRecording()
#if targetEnvironment(simulator)
        AppLog.capture.debug("Simulator detected; skipping real camera setup.")
        updateState { $0.session = .ready }
#else
        updateCaptureReadiness(.warmingUp)
        configureAudioSession()
        captureSession.setCaptureOrientation(.current)
        switch captureSession.configure(sampleBufferDelegate: self) {
        case .configured(let isTorchAvailable):
            updateState { $0.isTorchAvailable = isTorchAvailable }
            readinessMonitor.reset()
            captureSession.startRunning()
        case .unavailable:
            updateState { $0.session = .unavailable }
        }
#endif
    }

    private func configureAudioSession() {
        #if !targetEnvironment(simulator)
        AudioSessionMode.activateCapture()
        #endif
    }

    @MainActor
    func resumeCaptureMode() {
        guard isCaptureModeSuspended else { return }
        isCaptureModeSuspended = false
        captureModeGeneration += 1
        guard state.session != .blocked, state.session != .unavailable else { return }
        configureAudioSession()
        saveCoordinator.prepareForRecording()
        captureSession.setCaptureOrientation(.current)
        readinessMonitor.reset()
        updateCaptureReadiness(.warmingUp)
        captureSession.startRunning()
    }

    @MainActor
    func suspendCaptureMode() async {
        guard !isCaptureModeSuspended else { return }
        isCaptureModeSuspended = true
        captureModeGeneration += 1
        let generation = captureModeGeneration
        if state.isRecording || pendingStartDuration != nil || captureSession.isRecording {
            stopRecording()
        } else {
            saveCoordinator.cancelRecording()
        }
        updateState { $0.session = .preparing }
        await captureSession.stopRunning()
        guard isCaptureModeSuspended,
              captureModeGeneration == generation else { return }
        updateState { $0.session = .preparing }
        #if !targetEnvironment(simulator)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            AppLog.capture.error("Failed to deactivate capture audio session: \(error.localizedDescription)")
        }
        #endif
    }

    func startRecording(duration: TimeInterval) {
        guard state.session == .ready, state.savePhase == .idle else { return }
        #if !targetEnvironment(simulator)
        guard !captureSession.isRecording else { return }
        #endif
        AppLog.capture.info("capture.start duration=\(duration, privacy: .public)")
        captureSession.setCaptureOrientation(.current)
        configureAudioSession()
        saveCoordinator.prepareForRecording()
        recordingTimer?.invalidate()
        currentCapturedAt = Date()

        #if targetEnvironment(simulator)
        AppLog.capture.debug("SIMULATOR: Faking recording start.")
        currentPlannedDuration = duration
        updateState { $0.isRecording = true }
        recordingTimer = Timer.scheduledTimer(
            withTimeInterval: duration,
            repeats: false
        ) { [weak self] _ in
            self?.stopRecording()
        }
        #else
        if !captureSession.isReadyForRecording {
            pendingStartDuration = duration
            currentPlannedDuration = duration
        } else {
            currentPlannedDuration = duration
            startRecordingNow()
        }
        #endif
    }

    private func startRecordingNow() {
        #if !targetEnvironment(simulator)
        do {
            let tempURL = try temporaryFileStore.makeURL(
                prefix: "capture",
                pathExtension: "mov"
            )
            captureSession.startRecording(
                to: tempURL,
                delegate: self
            ) { [weak self] result in
                guard let self, case .failure(let error) = result else { return }
                AppLog.capture.error(
                    "capture.start.fail reason=\(error.localizedDescription, privacy: .private)"
                )
                self.temporaryFileStore.removeIfExists(at: tempURL)
                self.saveCoordinator.cancelRecording()
                self.pendingStartDuration = nil
                self.currentPlannedDuration = nil
                self.currentCapturedAt = nil
                self.updateState { state in
                    state.isRecording = false
                    state.savePhase = .idle
                }
                if let operationError = error as? CaptureSessionOperationError,
                   case .audioUnavailable = operationError {
                    self.reportSaveFailure(.audioRecordingUnavailable)
                } else {
                    self.reportSaveFailure(.recordingFailed)
                }
            }
        } catch {
            AppLog.capture.error(
                "capture.temp.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            saveCoordinator.cancelRecording()
            pendingStartDuration = nil
            currentPlannedDuration = nil
            currentCapturedAt = nil
            reportSaveFailure(.storageUnavailable)
        }
        #endif
    }

    private func handleSessionDidStartRunning() {
        if pendingStartDuration != nil,
           !captureSession.isRecording,
           captureSession.isReadyForRecording {
            pendingStartDuration = nil
            startRecordingNow()
        }
    }

    func stopRecording() {
        #if !targetEnvironment(simulator)
        captureSession.stopRecording()
        #else
        AppLog.capture.debug("SIMULATOR: Faking recording stop.")
        currentCapturedAt = nil
        #endif
        pendingStartDuration = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        currentPlannedDuration = nil
        updateState { $0.isRecording = false }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        updateState { state in
            state.savePhase = .idle
            state.saveFailure = nil
            state.isRecording = true
            if let d = self.currentPlannedDuration {
                self.recordingTimer = Timer.scheduledTimer(
                    withTimeInterval: d,
                    repeats: false
                ) { [weak self] _ in
                    self?.stopRecording()
                }
            }
        }
    }

    func switchCamera() {
        guard state.session == .ready, !state.isRecording else { return }
        readinessMonitor.reset()
        updateState { $0.session = .preparing }
        captureSession.switchCamera { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let isTorchAvailable):
                self.updateState { state in
                    state.isTorchAvailable = isTorchAvailable
                    state.session = .preparing
                }
            case .failure(let error):
                AppLog.capture.error(
                    "capture.switch.fail reason=\(error.localizedDescription, privacy: .private)"
                )
                self.updateState { $0.session = .ready }
            }
        }
    }

    func focus(
        at point: CGPoint,
        locksFocusAndExposure: Bool
    ) {
        captureSession.focus(
            at: point,
            locksFocusAndExposure: locksFocusAndExposure
        )
    }

    func setExposureBias(_ bias: Float) {
        captureSession.setExposureBias(bias)
    }

    func setZoom(factor: CGFloat) {
        captureSession.setZoom(factor: factor)
    }

    func refreshPreviewOrientation() {
        captureSession.setCaptureOrientation(.current)
        captureSession.refreshPreviewRotation()
    }

    func setTorch(
        on: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        captureSession.setTorch(enabled: on) { result in
            switch result {
            case .success(let isEnabled):
                completion(isEnabled)
            case .failure(let error):
                AppLog.capture.error(
                    "capture.torch.fail reason=\(error.localizedDescription, privacy: .private)"
                )
                completion(false)
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let capturedAt = currentCapturedAt ?? Date()
        currentCapturedAt = nil
        let recordingFinishedSuccessfully: Bool = if let error {
            ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? NSNumber)?.boolValue == true
        } else {
            true
        }
        guard recordingFinishedSuccessfully else {
            if let error {
                AppLog.capture.error("Error recording video: \(error.localizedDescription)")
                reportSaveFailure(VlogishFailureMapper.captureSaveFailure(from: error))
            } else {
                reportSaveFailure(.recordingFailed)
            }
            temporaryFileStore.removeIfExists(at: outputFileURL)
            saveCoordinator.cancelRecording()
            recordingTimer?.invalidate()
            recordingTimer = nil
            currentPlannedDuration = nil
            pendingStartDuration = nil
            updateState { state in
                state.isRecording = false
                state.savePhase = .idle
            }
            return
        }
        if let error {
            AppLog.capture.notice(
                "capture.finish.recoverable reason=\(error.localizedDescription, privacy: .private)"
            )
        }
        recordingTimer?.invalidate()
        recordingTimer = nil
        currentPlannedDuration = nil
        pendingStartDuration = nil
        AppLog.capture.info("capture.stop")
        updateState { state in
            state.isRecording = false
            state.savePhase = .recorded
        }
        Task { [weak self] in
            guard let self else { return }
            let stagedCapture: RecoverableCapture?
            let saveURL: URL
            do {
                let capture = try self.captureRecoveryStore.stageCapture(
                    at: outputFileURL,
                    capturedAt: capturedAt
                )
                stagedCapture = capture
                saveURL = capture.url
                self.updateState { $0.recoverableCapture = capture }
            } catch {
                stagedCapture = nil
                saveURL = outputFileURL
                AppLog.storage.error(
                    "recovery.stage.fail reason=\(error.localizedDescription, privacy: .private)"
                )
            }
            do {
                await MainActor.run {
                    self.updateState { $0.savePhase = .processing }
                }
                let result = try await self.saveCoordinator.saveRecording(
                    at: saveURL,
                    capturedAt: capturedAt
                )
                if let stagedCapture {
                    self.captureRecoveryStore.discard(stagedCapture)
                }
                let nextRecovery = self.captureRecoveryStore.recoverableCaptures().first
                AppLog.save.info("save.success stamp_applied=\(result.stampApplied, privacy: .public) fallback=\(result.didFallback, privacy: .public)")
                await MainActor.run {
                    self.updateState { state in
                        state.lastSavedAssetLocalIdentifier = result.identifier
                        state.savePhase = .saved
                        state.recoverableCapture = nextRecovery
                        if nextRecovery != nil {
                            state.saveFailure = .unsavedCaptureAvailable
                        }
                    }
                }
            } catch AssetLibraryWriterError.permissionDenied {
                AppLog.save.error("save.fail reason=permission_denied")
                await MainActor.run { self.updateState { $0.savePhase = .idle } }
                self.reportSaveFailure(.photoLibraryPermission)
            } catch {
                AppLog.save.error("save.fail reason=\(error.localizedDescription, privacy: .private)")
                await MainActor.run { self.updateState { $0.savePhase = .idle } }
                self.reportSaveFailure(VlogishFailureMapper.captureSaveFailure(from: error))
            }
        }
    }

    func acknowledgeIndexedSave() {
        updateState { state in
            guard state.savePhase == .saved else { return }
            state.savePhase = .indexed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.updateState { state in
                    guard state.savePhase == .indexed else { return }
                    state.savePhase = .idle
                }
            }
        }
    }
    func prepare() {
        permissionService.preparePermissions(
            onAuthorized: {
                self.updateCaptureReadiness(.warmingUp)
                self.updateState { state in
                    state.permissionIssue = nil
                    state.isPermissionAlertPresented = false
                }
                self.setupSession()
            },
            onDenied: { title, message in
                AppLog.permission.error("permission.denied title=\(title, privacy: .public)")
                self.updateCaptureReadiness(.permissionsMissing)
                self.showPermissionAlert(title: title, message: message)
            }
        )
    }

    func clearSaveError() {
        updateState { $0.saveFailure = nil }
    }

    func discardRecoverableCapture() {
        guard let capture = state.recoverableCapture else { return }
        captureRecoveryStore.discard(capture)
        let nextRecovery = captureRecoveryStore.recoverableCaptures().first
        updateState { state in
            state.recoverableCapture = nextRecovery
            state.saveFailure = nextRecovery == nil ? nil : .unsavedCaptureAvailable
        }
    }

    func dismissPermissionAlert() {
        updateState { $0.isPermissionAlertPresented = false }
    }

    private func reportSaveFailure(_ failure: VlogishFailure) {
        updateState { $0.saveFailure = failure }
    }

    private func showPermissionAlert(title: String, message: String) {
        updateState { state in
            state.permissionIssue = CameraPermissionIssue(title: title, message: message)
            state.isPermissionAlertPresented = true
            state.session = .blocked
        }
    }

    // MARK: - Session interruption handling
    @objc private func handleSessionInterruption(_ notification: Notification) {
        saveCoordinator.cancelRecording()
        readinessMonitor.reset()
        updateState { state in
            state.session = .interrupted
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.currentPlannedDuration = nil
            self.pendingStartDuration = nil
            self.currentCapturedAt = nil
            state.isRecording = false
        }
        updateCaptureReadiness(.interrupted)
        if let userInfo = notification.userInfo,
           let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) {
            AppLog.capture.warning("Session interrupted: \(String(describing: reason), privacy: .public)")
        } else {
            AppLog.capture.warning("Session interrupted")
        }
    }
    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        guard !isCaptureModeSuspended else { return }
        readinessMonitor.reset()
        updateCaptureReadiness(.warmingUp)
        captureSession.startRunning()
        AppLog.capture.info("Session interruption ended")
    }
    @objc private func handleRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            AppLog.capture.error("Session runtime error: \(error.localizedDescription)")
        }
        readinessMonitor.reset()
        updateState { state in
            state.session = .preparing
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.currentPlannedDuration = nil
            self.pendingStartDuration = nil
            self.currentCapturedAt = nil
            state.isRecording = false
        }
        updateCaptureReadiness(.warmingUp)
        saveCoordinator.cancelRecording()
        if !isCaptureModeSuspended {
            captureSession.startRunning()
        }
    }

    // MARK: - Capture readiness
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        switch readinessMonitor.observeFrame(
            isDeviceAdjusting: captureSession.isDeviceAdjusting
        ) {
        case .ready:
            markReadyToRecord()
        case .timedOut:
            AppLog.capture.info("warmup.timeout_reached")
            markReadyToRecord()
        case .waiting, .settled:
            break
        }
    }

    private func markReadyToRecord() {
        guard captureSession.isReadyForRecording else {
            AppLog.capture.error("Capture warm-up completed without video and audio recording connections.")
            updateState { $0.session = .unavailable }
            return
        }
        updateState { state in
            guard state.session == .preparing else { return }
            state.session = .ready
            AppLog.capture.info("capture_state=ready")
            if self.pendingStartDuration != nil {
                self.pendingStartDuration = nil
                self.startRecordingNow()
            }
        }
    }
}
