import SwiftUI
import UIKit
import AVFoundation
import Photos
import CoreLocation
import OSLog

enum CaptureReadinessReason: Equatable {
    case warmingUp
    case permissionsMissing
    case interrupted
    case ready
}

class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, CLLocationManagerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    //
    // Operation API (UI-facing):
    // - All mutating camera operations execute on `sessionQueue` for consistency.
    // - Public setters clamp to safe device ranges.
    // - Optional completion(Bool) indicates success; callers can ignore.
    //   Example:
    //     camera.setZoom(factor: 2.0)
    //     camera.focus(at: tapPoint)
    //     camera.setExposure(bias: 0.3)
    //     camera.toggleTorch(on: true)
    // - Snapshot helpers to query ranges:
    //     camera.zoomRange, camera.exposureBiasRange, camera.isTorchAvailable
    //
    @Published var isRecording = false
    @Published var isSessionReady = false
    @Published var isSessionInterrupted = false
    @Published var permissionDenied = false
    @Published var permissionAlertTitle = "アクセスが必要です"
    @Published var permissionAlertMessage = ""
    @Published var isTorchAvailable = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isReadyToRecord = false
    @Published var captureReadinessReason: CaptureReadinessReason = .warmingUp
    @Published var lastSavedAssetLocalIdentifier: String?
    @Published var savePhase: CaptureSavePhase = .idle
    // Default on for release build UX; users can disable in Settings.
    @AppStorage("isDateStampEnabled") private var isDateStampEnabled: Bool = true
    @AppStorage("dateStampFormat") private var dateStampFormat: String = DateStampFormatter.compactDateTime
    @AppStorage("dateStampZeroPadded") private var dateStampZeroPadded: Bool = false
    @AppStorage("dateStampSize") private var dateStampSize: String = DateStampStyle.medium
    
    var session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let dataOutputQueue = DispatchQueue(label: "CameraService.DataOutputQueue")
    private var recordingTimer: Timer?
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var lastLocationTimestamp: Date = .distantPast
    var previewLayer: AVCaptureVideoPreviewLayer!
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var warmFrameCount = 0
    private var lastConfigChangeAt: Date = Date.distantPast
    private var stableConsecutiveFrames = 0
    private let minimumWarmFramesForReady = 3
    private let minimumStableFramesForReady = 2
    private let warmupTimeoutSeconds: TimeInterval = 1.0
    private let sessionQueue = DispatchQueue(label: "CameraService.SessionQueue")
    private let sessionQueueSpecific = DispatchSpecificKey<Void>()
    private var pendingStart: (duration: TimeInterval, orientation: UIDeviceOrientation)?
    private var currentPlannedDuration: TimeInterval?
    private let practicalMaxZoomFactor: CGFloat = 10.0
    private let permissionService: CameraPermissionService
    private let postProcessService: VideoPostProcessingService
    private let assetLibraryWriter: AssetLibraryWriter
    private let savePipeline: CaptureSavePipeline
    lazy var sessionController = CameraSessionController(
        prepareHandler: { [weak self] in self?.checkForPermissions() },
        switchHandler: { [weak self] in self?.switchCamera() },
        torchHandler: { [weak self] enabled in self?.toggleTorch(on: enabled) },
        zoomHandler: { [weak self] factor in self?.setZoom(factor: factor) },
        focusHandler: { [weak self] point in self?.focus(at: point) },
        restartHandler: { [weak self] in self?.restartSession() }
    )
    lazy var recordingController = VideoRecordingController(
        startHandler: { [weak self] duration, orientation in self?.startRecording(duration: duration, orientation: orientation) },
        stopHandler: { [weak self] in self?.stopRecording() }
    )
    // no export UI/monitoring

    init(
        permissionService: CameraPermissionService = CameraPermissionService(),
        postProcessService: VideoPostProcessingService = DefaultVideoPostProcessingService(),
        assetLibraryWriter: AssetLibraryWriter = AssetLibraryWriter(albumName: "daylog")
    ) {
        self.permissionService = permissionService
        self.postProcessService = postProcessService
        self.assetLibraryWriter = assetLibraryWriter
        self.savePipeline = CaptureSavePipeline(postProcessService: postProcessService, assetLibraryWriter: assetLibraryWriter)
        super.init()
        // Migrate older installs that never stored this key (legacy default was OFF).
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "isDateStampEnabled") == nil {
            defaults.set(true, forKey: "isDateStampEnabled")
        }
        // Mark sessionQueue for reentrancy checks
        sessionQueue.setSpecific(key: sessionQueueSpecific, value: ())
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.handleSessionDidStartRunning()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruption(_:)), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruptionEnded(_:)), name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRuntimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func updateCaptureReadiness(_ reason: CaptureReadinessReason) {
        DispatchQueue.main.async {
            guard self.captureReadinessReason != reason else { return }
            self.captureReadinessReason = reason
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

    func setupSession() {
#if targetEnvironment(simulator)
        AppLog.capture.debug("Simulator detected; skipping real camera setup.")
        DispatchQueue.main.async {
            self.isSessionReady = true
            self.isReadyToRecord = true
            self.updateCaptureReadiness(.ready)
        }
#else
        updateCaptureReadiness(.warmingUp)
        // Configure audio session for video recording
        configureAudioSession()

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        // Video Input using Discovery Session for best camera
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)

        let videoDevice = discoverySession.devices.first

        self.device = videoDevice
        guard let device = self.device else {
            AppLog.capture.error("No suitable video device found.")
            DispatchQueue.main.async { self.isSessionReady = true }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            self.videoInput = input
            if session.canAddInput(input) { session.addInput(input) }
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: self.previewLayer)
            DispatchQueue.main.async {
                self.cameraPosition = device.position
                self.isTorchAvailable = device.hasTorch && device.position == .back
            }
            // Prefer continuous AF/AE/AWB and center POI
            try? device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            if device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported {
                let center = CGPoint(x: 0.5, y: 0.5)
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            AppLog.capture.error("Error setting up video input: \(error.localizedDescription)")
            DispatchQueue.main.async { self.isSessionReady = true }
            return
        }

        // Audio Input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let input = try AVCaptureDeviceInput(device: audioDevice)
                self.audioInput = input
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                AppLog.capture.error("Error setting up audio input: \(error.localizedDescription)")
            }
        } else {
            AppLog.capture.error("No audio device found.")
        }

        // Outputs
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            session.addOutput(videoDataOutput)
        }
        // Configure connection defaults (mirroring/stabilization)
        if let conn = movieOutput.connection(with: .video) {
            // Mirroring: front = mirrored, back = not mirrored
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (self.cameraPosition == .front)
            }
            // Stabilization: prefer cinematicExtended / cinematic / auto
            if conn.isVideoStabilizationSupported {
                if conn.isVideoStabilizationSupported {
                    conn.preferredVideoStabilizationMode = .cinematicExtended
                    if conn.activeVideoStabilizationMode != .cinematicExtended {
                        conn.preferredVideoStabilizationMode = .cinematic
                    }
                    if conn.activeVideoStabilizationMode == .off {
                        conn.preferredVideoStabilizationMode = .auto
                    }
                }
            }
        }

        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionReady = true
                self.isReadyToRecord = false
                self.warmFrameCount = 0
                self.stableConsecutiveFrames = 0
                self.lastConfigChangeAt = Date()
            }
        }
#endif
    }

    private func configureAudioSession() {
        #if !targetEnvironment(simulator)
        AudioSessionMode.activateCapture()
        #endif
    }

    func resumeCaptureMode() {
        configureAudioSession()
        DispatchQueue.main.async {
            self.isSessionInterrupted = false
            self.isReadyToRecord = false
            self.warmFrameCount = 0
            self.stableConsecutiveFrames = 0
            self.lastConfigChangeAt = Date()
        }
        updateCaptureReadiness(.warmingUp)
        restartSession()
    }

    // Public restart for UI retry
    func restartSession() {
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func startRecording(duration: TimeInterval, orientation: UIDeviceOrientation) {
        guard !isSessionInterrupted else { return }
        AppLog.capture.info("capture.start duration=\(duration, privacy: .public)")
        configureAudioSession()
        locationManager.startUpdatingLocation()
        locationManager.requestLocation()
        recordingTimer?.invalidate()
        
        #if targetEnvironment(simulator)
        AppLog.capture.debug("SIMULATOR: Faking recording start.")
        DispatchQueue.main.async { self.isRecording = true }
        #else
        // If session isn't fully ready (no video connection yet or still stabilizing), queue the start
        if movieOutput.isRecording {
            return
        }
        if movieOutput.connection(with: .video) == nil || !session.isRunning {
            pendingStart = (duration, orientation)
            currentPlannedDuration = duration
        } else {
            currentPlannedDuration = duration
            startRecordingNow(duration: duration, orientation: orientation)
        }
        #endif
    }

    private func startRecordingNow(duration: TimeInterval, orientation: UIDeviceOrientation) {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            guard self.movieOutput.isRecording == false, let output = self.movieOutput.connection(with: .video) else { return }
            self.ensureAudioInputAttachedIfNeeded()
            // Prefer rotation angle (iOS 17+/supported devices). Avoid deprecated orientation APIs.
            if let rc = self.rotationCoordinator {
                let angle = rc.videoRotationAngleForHorizonLevelCapture
                if output.isVideoRotationAngleSupported(angle) {
                    output.videoRotationAngle = angle
                }
            }
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        }
        // Defer isRecording state and timer scheduling to didStartRecording delegate for accurate syncing
        #endif
    }

    private func ensureAudioInputAttachedIfNeeded() {
        let hasAudioInput = session.inputs.contains { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.audio)
        }
        if hasAudioInput { return }
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            AppLog.capture.error("No audio device found when ensuring input before recording.")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            guard session.canAddInput(input) else {
                AppLog.capture.warning("Cannot add audio input before recording.")
                return
            }
            session.beginConfiguration()
            session.addInput(input)
            session.commitConfiguration()
            audioInput = input
            AppLog.capture.info("Audio input reattached before recording.")
        } catch {
            AppLog.capture.error("Failed to reattach audio input: \(error.localizedDescription)")
        }
    }

    private func handleSessionDidStartRunning() {
        // If there was a pending start (e.g., very first shutter), try to start now
        if let pending = pendingStart, movieOutput.isRecording == false, movieOutput.connection(with: .video) != nil {
            pendingStart = nil
            startRecordingNow(duration: pending.duration, orientation: pending.orientation)
        }
    }

    func stopRecording() {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Faking recording stop.")
        #endif
        // Cancel any queued start to avoid odd toggling behavior
        pendingStart = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        currentPlannedDuration = nil
        DispatchQueue.main.async { self.isRecording = false }
    }

    // Accurate recording start callback (iOS provides this when file output begins)
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.savePhase = .idle
            self.isRecording = true
            if let d = self.currentPlannedDuration {
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { [weak self] _ in self?.stopRecording() }
            }
        }
    }

    func switchCamera() {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            guard let currentInput = self.videoInput else { return }
            self.session.removeInput(currentInput)

            let newPosition: AVCaptureDevice.Position = (currentInput.device.position == .back) ? .front : .back
            let deviceTypes: [AVCaptureDevice.DeviceType] = newPosition == .back ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera] : [.builtInWideAngleCamera]
            let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: newPosition)

            guard let newDevice = discoverySession.devices.first, let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                self.session.addInput(currentInput) // Put back the old input if something fails
                return
            }

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.device = newDevice
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: newDevice, previewLayer: self.previewLayer)
                DispatchQueue.main.async {
                    self.cameraPosition = newDevice.position
                    self.isTorchAvailable = newDevice.hasTorch && newDevice.position == .back
                    self.isReadyToRecord = false
                    self.updateCaptureReadiness(.warmingUp)
                    self.warmFrameCount = 0
                    self.stableConsecutiveFrames = 0
                    self.lastConfigChangeAt = Date()
                }
                if let conn = self.movieOutput.connection(with: .video) {
                    if conn.isVideoMirroringSupported {
                        conn.automaticallyAdjustsVideoMirroring = false
                        conn.isVideoMirrored = (newDevice.position == .front)
                    }
                    if conn.isVideoStabilizationSupported {
                        conn.preferredVideoStabilizationMode = .cinematicExtended
                        if conn.activeVideoStabilizationMode != .cinematicExtended {
                            conn.preferredVideoStabilizationMode = .cinematic
                        }
                        if conn.activeVideoStabilizationMode == .off {
                            conn.preferredVideoStabilizationMode = .auto
                        }
                    }
                }
            } else {
                self.session.addInput(currentInput)
            }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Camera switch requested. No action taken.")
        #endif
    }

    // Focus + exposure at a given screen point. Completion is invoked on sessionQueue.
    func focus(at point: CGPoint, completion: ((Bool) -> Void)? = nil) {
        #if !targetEnvironment(simulator)
        // Convert on the main thread (layer-bound), then configure on sessionQueue
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint; device.focusMode = .autoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint; device.exposureMode = .autoExpose }
                device.unlockForConfiguration()
                completion?(true)
            } catch {
                AppLog.capture.error("Failed to lock device for configuration: \(error.localizedDescription)")
                completion?(false)
            }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Focus requested at x=\(point.x, privacy: .public), y=\(point.y, privacy: .public). No action taken.")
        completion?(true)
        #endif
    }

    // Sets exposure bias within device supported range.
    func setExposure(bias: Float, completion: ((Bool) -> Void)? = nil) {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                let clampedBias = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
                device.setExposureTargetBias(clampedBias, completionHandler: nil)
                device.unlockForConfiguration()
                completion?(true)
            } catch {
                AppLog.capture.error("Failed to lock device for configuration: \(error.localizedDescription)")
                completion?(false)
            }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Exposure bias set to \(bias, privacy: .public). No action taken.")
        completion?(true)
        #endif
    }

    // Sets zoom factor within device supported range.
    func setZoom(factor: CGFloat, completion: ((Bool) -> Void)? = nil) {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                let upper = min(device.maxAvailableVideoZoomFactor, self.practicalMaxZoomFactor)
                let clamped = max(device.minAvailableVideoZoomFactor, min(factor, upper))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                completion?(true)
            } catch {
                AppLog.capture.error("Failed to lock device for configuration: \(error.localizedDescription)")
                completion?(false)
            }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Zoom requested with factor \(factor, privacy: .public). No action taken.")
        completion?(true)
        #endif
    }
    
    // Toggles torch mode if supported.
    func toggleTorch(on: Bool, completion: ((Bool) -> Void)? = nil) {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            guard let device = self.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if on {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                completion?(true)
            } catch {
                AppLog.capture.error("Failed to set torch mode: \(error.localizedDescription)")
                completion?(false)
            }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Torch toggle to \(on, privacy: .public) ignored.")
        completion?(true)
        #endif
    }

    // Snapshot helpers (read-only). Safe to call from UI for quick reads.
    var zoomRange: ClosedRange<CGFloat> {
        let minZ = device?.minAvailableVideoZoomFactor ?? 1.0
        let maxZ = min(device?.maxAvailableVideoZoomFactor ?? 1.0, practicalMaxZoomFactor)
        return minZ...maxZ
    }

    var exposureBiasRange: ClosedRange<Float> {
        let minB = device?.minExposureTargetBias ?? 0
        let maxB = device?.maxExposureTargetBias ?? 0
        return minB...maxB
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            if (error as NSError).code != -11806 { AppLog.capture.error("Error recording video: \(error.localizedDescription)") }
            return
        }
        AppLog.capture.info("capture.stop")
        DispatchQueue.main.async {
            self.savePhase = .recorded
        }
        let tagLocation = bestRecentLocation(maxAge: 60, maxHAcc: 100)
        AppLog.save.info("save.begin stamp_enabled=\(self.isDateStampEnabled, privacy: .public)")
        Task { [weak self] in
            guard let self else { return }
            do {
                let rawAsset = AVURLAsset(url: outputFileURL)
                let rawAudioTracks = try await rawAsset.loadTracks(withMediaType: .audio)
                AppLog.save.info("save.raw.audio_tracks=\(rawAudioTracks.count, privacy: .public)")
            } catch {
                AppLog.save.warning("save.raw.audio_probe_failed reason=\(error.localizedDescription, privacy: .public)")
            }
            let context = VideoPostProcessContext(
                stampEnabled: self.isDateStampEnabled,
                stampDate: Date(),
                format: self.dateStampFormat,
                zeroPadded: self.dateStampZeroPadded,
                sizeKey: self.dateStampSize
            )

            do {
                await MainActor.run {
                    self.savePhase = .processing
                }
                let result = try await self.savePipeline.processAndSaveRecording(
                    outputURL: outputFileURL,
                    location: tagLocation,
                    context: context
                )
                AppLog.save.info("save.success stamp_applied=\(result.processed.stampApplied, privacy: .public) fallback=\(result.processed.didFallback, privacy: .public)")
                await MainActor.run {
                    self.lastSavedAssetLocalIdentifier = result.identifier
                    self.savePhase = .saved
                }
            } catch AssetLibraryWriterError.permissionDenied {
                AppLog.save.error("save.fail reason=permission_denied")
                await MainActor.run {
                    self.savePhase = .idle
                }
                self.showPermissionAlert(
                    title: "写真へのアクセスが必要です",
                    message: "動画を保存するには、設定アプリから写真へのアクセスを許可してください。"
                )
            } catch {
                AppLog.save.error("save.fail reason=\(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.savePhase = .idle
                }
            }
            self.locationManager.stopUpdatingLocation()
        }
    }

    func acknowledgeIndexedSave() {
        DispatchQueue.main.async {
            guard self.savePhase == .saved else { return }
            self.savePhase = .indexed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if self.savePhase == .indexed {
                    self.savePhase = .idle
                }
            }
        }
    }
    func checkForPermissions() {
        locationManager.requestWhenInUseAuthorization()
        permissionService.preparePermissions(
            onAuthorized: {
                self.updateCaptureReadiness(.warmingUp)
                DispatchQueue.main.async { self.setupSession() }
            },
            onDenied: { title, message in
                AppLog.permission.error("permission.denied title=\(title, privacy: .public)")
                self.updateCaptureReadiness(.permissionsMissing)
                self.showPermissionAlert(title: title, message: message)
            }
        )
    }

    private func showPermissionAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.permissionAlertTitle = title
            self.permissionAlertMessage = message
            self.permissionDenied = true
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latest = locations.last {
            self.currentLocation = latest
            self.lastLocationTimestamp = Date()
        }
    }

    private func bestRecentLocation(maxAge: TimeInterval, maxHAcc: CLLocationAccuracy) -> CLLocation? {
        guard let loc = currentLocation else { return nil }
        let age = Date().timeIntervalSince(lastLocationTimestamp)
        if age <= maxAge && loc.horizontalAccuracy > 0 && loc.horizontalAccuracy <= maxHAcc {
            return loc
        }
        return nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { AppLog.location.error("Failed to get user location: \(error.localizedDescription)") }
    // RotationCoordinator handles recording orientation (iOS 17+). UI remains portrait.

    // MARK: - Session interruption handling
    @objc private func handleSessionInterruption(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isSessionInterrupted = true
            self.isReadyToRecord = false
            self.warmFrameCount = 0
            self.stableConsecutiveFrames = 0
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.currentPlannedDuration = nil
            self.pendingStart = nil
            self.isRecording = false
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
        DispatchQueue.main.async {
            self.isSessionInterrupted = false
            self.isReadyToRecord = false
            self.warmFrameCount = 0
            self.stableConsecutiveFrames = 0
        }
        updateCaptureReadiness(.warmingUp)
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
        AppLog.capture.info("Session interruption ended")
    }
    @objc private func handleRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            AppLog.capture.error("Session runtime error: \(error.localizedDescription)")
        }
        DispatchQueue.main.async {
            self.isReadyToRecord = false
            self.warmFrameCount = 0
            self.stableConsecutiveFrames = 0
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.currentPlannedDuration = nil
            self.pendingStart = nil
            self.isRecording = false
        }
        updateCaptureReadiness(.warmingUp)
        sessionQueue.async { self.session.startRunning() }
    }

    // MARK: - Video Data Output (warm-up)
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Count first few frames after configuration; mark ready when stable
        guard !isReadyToRecord else { return }
        warmFrameCount += 1
        var adjusting = false
        if let d = self.device {
            adjusting = d.isAdjustingExposure || d.isAdjustingWhiteBalance || d.isAdjustingFocus
        }
        if adjusting {
            stableConsecutiveFrames = 0
        } else {
            stableConsecutiveFrames += 1
        }
        // Prefer quick readiness once a few stable frames arrive.
        if warmFrameCount >= minimumWarmFramesForReady && stableConsecutiveFrames >= minimumStableFramesForReady {
            markReadyToRecord()
            return
        }

        // Fail-safe: if warm-up takes too long, unlock capture to improve perceived startup speed.
        if Date().timeIntervalSince(lastConfigChangeAt) >= warmupTimeoutSeconds && warmFrameCount >= 2 {
            AppLog.capture.info("warmup.timeout_reached seconds=\(self.warmupTimeoutSeconds, privacy: .public)")
            markReadyToRecord()
        }
    }

    private func markReadyToRecord() {
        DispatchQueue.main.async {
            guard !self.isReadyToRecord else { return }
            self.isReadyToRecord = true
            self.updateCaptureReadiness(.ready)
            if let pending = self.pendingStart {
                self.pendingStart = nil
                self.startRecordingNow(duration: pending.duration, orientation: pending.orientation)
            }
        }
    }
}

class CameraPreviewController: UIViewController {
    var cameraService: CameraService?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        #if !targetEnvironment(simulator)
            guard let previewLayer = cameraService?.previewLayer else { return }
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
        #endif
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if !targetEnvironment(simulator)
            view.layer.sublayers?.first?.frame = view.bounds
        #endif
    }
    
}

struct CameraView: UIViewControllerRepresentable {
    @ObservedObject var cameraService: CameraService
    func makeUIViewController(context: Context) -> CameraPreviewController {
        let controller = CameraPreviewController()
        controller.cameraService = cameraService
        return controller
    }
    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {}
}

// Helper to map device orientation → capture orientation
// No need for AVCaptureVideoOrientation mapping; use rotation angle when available (iOS 17+).
