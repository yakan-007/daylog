import CoreGraphics
import Foundation
@preconcurrency import AVFoundation

enum CaptureSessionConfigurationResult {
    case configured(isTorchAvailable: Bool)
    case unavailable
}

enum CaptureSessionOperationError: LocalizedError {
    case recordingUnavailable
    case audioUnavailable
    case cameraSwitchUnavailable
    case torchUnavailable

    var errorDescription: String? {
        switch self {
        case .recordingUnavailable:
            return L10n.text("録画接続を準備できませんでした。")
        case .audioUnavailable:
            return L10n.text("音声接続を準備できませんでした。")
        case .cameraSwitchUnavailable:
            return L10n.text("カメラを切り替えられませんでした。")
        case .torchUnavailable:
            return L10n.text("ライトを切り替えられませんでした。")
        }
    }
}

/// AVCaptureSession、入出力、端末操作を所有する低レベル境界。
/// 録画状態や保存状態は持たず、CameraServiceへUI状態を漏らさない。
final class CaptureSessionController {
    let session = AVCaptureSession()
    lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)

    private var device: AVCaptureDevice?
    private let deviceLock = NSLock()
    private var videoInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let dataOutputQueue = DispatchQueue(label: "CaptureSessionController.DataOutput")
    private let sessionQueue = DispatchQueue(label: "CaptureSessionController.Session")
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private let orientationLock = NSLock()
    private var captureOrientationMode = CaptureOrientationMode.portrait
    private var isConfigured = false
    private let practicalMaxZoomFactor: CGFloat = 10
    private var focusRestoreWorkItem: DispatchWorkItem?

    func configure(
        sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate
    ) -> CaptureSessionConfigurationResult {
        if isConfigured {
            let device = currentDevice()
            return .configured(
                isTorchAvailable: device?.hasTorch == true && device?.position == .back
            )
        }
        #if targetEnvironment(simulator)
        isConfigured = true
        return .configured(isTorchAvailable: false)
        #else
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080)
            ? .hd1920x1080
            : .high

        guard let videoDevice = discoverDevice(position: .back) else {
            AppLog.capture.error("No suitable video device found.")
            return .unavailable
        }
        setCurrentDevice(videoDevice)

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(input) else { return .unavailable }
            session.addInput(input)
            videoInput = input
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: videoDevice,
                previewLayer: previewLayer
            )
            DispatchQueue.main.async { [weak self] in
                self?.refreshPreviewRotation()
            }
            configureContinuousCapture(on: videoDevice)
        } catch {
            AppLog.capture.error("Error setting up video input: \(error.localizedDescription)")
            return .unavailable
        }

        guard attachAudioInput() else { return .unavailable }
        guard session.canAddOutput(movieOutput) else {
            AppLog.capture.error("Movie output could not be attached.")
            return .unavailable
        }
        session.addOutput(movieOutput)
        movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        movieOutput.maxRecordedDuration = CMTime(seconds: 6, preferredTimescale: 600)
        guard hasActiveAudioConnection else {
            AppLog.capture.error("Movie output has no audio connection after configuration.")
            return .unavailable
        }
        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoDataOutput.setSampleBufferDelegate(
                sampleBufferDelegate,
                queue: dataOutputQueue
            )
            session.addOutput(videoDataOutput)
        }
        configureVideoConnection(for: videoDevice.position)
        configureInitialCameraControls(on: videoDevice)
        isConfigured = true
        return .configured(
            isTorchAvailable: videoDevice.hasTorch && videoDevice.position == .back
        )
        #endif
    }

    func startRunning() {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
        #endif
    }

    func stopRunning() async {
        #if !targetEnvironment(simulator)
        let session = self.session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
        #endif
    }

    var isReadyForRecording: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return session.isRunning
            && movieOutput.connection(with: .video) != nil
            && hasAudioInput
            && hasActiveAudioConnection
        #endif
    }

    var isRecording: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return movieOutput.isRecording
        #endif
    }

    func startRecording(
        to outputURL: URL,
        delegate: AVCaptureFileOutputRecordingDelegate,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if targetEnvironment(simulator)
        completion(.success(()))
        #else
        sessionQueue.async {
            guard !self.movieOutput.isRecording,
                  let connection = self.movieOutput.connection(with: .video) else {
                DispatchQueue.main.async {
                    completion(.failure(CaptureSessionOperationError.recordingUnavailable))
                }
                return
            }
            guard self.hasAudioInput,
                  self.hasActiveAudioConnection else {
                AppLog.capture.error("Recording aborted because audio connection is unavailable.")
                DispatchQueue.main.async {
                    completion(.failure(CaptureSessionOperationError.audioUnavailable))
                }
                return
            }
            if let coordinator = self.rotationCoordinator {
                let angle = CaptureRotationPolicy.angle(
                    closestTo: coordinator.videoRotationAngleForHorizonLevelCapture,
                    mode: self.currentCaptureOrientationMode()
                )
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
        #endif
    }

    func stopRecording() {
        #if !targetEnvironment(simulator)
        sessionQueue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
        #endif
    }

    func switchCamera(completion: @escaping (Result<Bool, Error>) -> Void) {
        #if targetEnvironment(simulator)
        AppLog.capture.debug("SIMULATOR: Camera switch requested. No action taken.")
        completion(.success(false))
        #else
        sessionQueue.async {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            guard let currentInput = self.videoInput else {
                DispatchQueue.main.async {
                    completion(.failure(CaptureSessionOperationError.cameraSwitchUnavailable))
                }
                return
            }
            self.disableTorchIfNeeded(on: currentInput.device)
            self.session.removeInput(currentInput)

            let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back
                ? .front
                : .back
            guard let newDevice = self.discoverDevice(position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice),
                  self.session.canAddInput(newInput) else {
                if self.session.canAddInput(currentInput) {
                    self.session.addInput(currentInput)
                }
                DispatchQueue.main.async {
                    completion(.failure(CaptureSessionOperationError.cameraSwitchUnavailable))
                }
                return
            }

            self.session.addInput(newInput)
            self.videoInput = newInput
            self.setCurrentDevice(newDevice)
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: newDevice,
                previewLayer: self.previewLayer
            )
            DispatchQueue.main.async { [weak self] in
                self?.refreshPreviewRotation()
            }
            self.configureContinuousCapture(on: newDevice)
            self.configureVideoConnection(for: newPosition)
            self.configureInitialCameraControls(on: newDevice)
            let isTorchAvailable = newDevice.hasTorch && newPosition == .back
            DispatchQueue.main.async {
                completion(.success(isTorchAvailable))
            }
        }
        #endif
    }

    func focus(
        at layerPoint: CGPoint,
        locksFocusAndExposure: Bool
    ) {
        #if targetEnvironment(simulator)
        AppLog.capture.debug(
            "SIMULATOR: Focus requested at x=\(layerPoint.x, privacy: .public), y=\(layerPoint.y, privacy: .public). No action taken."
        )
        #else
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        sessionQueue.async {
            guard let device = self.currentDevice() else { return }
            self.focusRestoreWorkItem?.cancel()
            self.focusRestoreWorkItem = nil
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                }
                device.unlockForConfiguration()
                if !locksFocusAndExposure {
                    self.scheduleContinuousFocusRestore(on: device, after: 1.2)
                }
            } catch {
                AppLog.capture.error("Failed to focus camera: \(error.localizedDescription)")
            }
        }
        #endif
    }

    private func scheduleContinuousFocusRestore(
        on device: AVCaptureDevice,
        after delay: TimeInterval
    ) {
        let workItem = DispatchWorkItem { [weak self, weak device] in
            guard let self,
                  let device,
                  device === self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                AppLog.capture.warning(
                    "Failed to restore continuous focus: \(error.localizedDescription)"
                )
            }
        }
        focusRestoreWorkItem = workItem
        sessionQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func setExposureBias(_ bias: Float) {
        #if targetEnvironment(simulator)
        AppLog.capture.debug(
            "SIMULATOR: Exposure bias requested at \(bias, privacy: .public). No action taken."
        )
        #else
        sessionQueue.async {
            guard let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                let target = min(
                    max(bias, device.minExposureTargetBias),
                    device.maxExposureTargetBias
                )
                device.setExposureTargetBias(target, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                AppLog.capture.error(
                    "Failed to set exposure bias: \(error.localizedDescription)"
                )
            }
        }
        #endif
    }

    func setZoom(factor: CGFloat) {
        #if targetEnvironment(simulator)
        AppLog.capture.debug(
            "SIMULATOR: Zoom requested with factor \(factor, privacy: .public). No action taken."
        )
        #else
        sessionQueue.async {
            guard let device = self.currentDevice() else { return }
            do {
                try device.lockForConfiguration()
                let upper = min(
                    device.maxAvailableVideoZoomFactor,
                    self.practicalMaxZoomFactor
                )
                let target = max(
                    device.minAvailableVideoZoomFactor,
                    min(factor, upper)
                )
                device.cancelVideoZoomRamp()
                device.ramp(toVideoZoomFactor: target, withRate: 12)
                device.unlockForConfiguration()
            } catch {
                AppLog.capture.error("Failed to zoom camera: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func setCaptureOrientation(_ mode: CaptureOrientationMode) {
        orientationLock.lock()
        captureOrientationMode = mode
        orientationLock.unlock()
        refreshPreviewRotation()
    }

    func refreshPreviewRotation() {
        #if !targetEnvironment(simulator)
        let update = { [weak self] in
            guard let self,
                  let coordinator = self.rotationCoordinator,
                  let connection = self.previewLayer.connection else { return }
            let angle = CaptureRotationPolicy.angle(
                closestTo: coordinator.videoRotationAngleForHorizonLevelPreview,
                mode: self.currentCaptureOrientationMode()
            )
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
        #endif
    }

    func setTorch(
        enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        #if targetEnvironment(simulator)
        AppLog.capture.debug(
            "SIMULATOR: Torch toggle to \(enabled, privacy: .public) ignored."
        )
        completion(.success(false))
        #else
        sessionQueue.async {
            guard let device = self.currentDevice(), device.hasTorch else {
                DispatchQueue.main.async {
                    completion(.failure(CaptureSessionOperationError.torchUnavailable))
                }
                return
            }
            do {
                try device.lockForConfiguration()
                if enabled {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                let isEnabled = device.torchMode == .on
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    completion(.success(isEnabled))
                }
            } catch {
                AppLog.capture.error("Failed to set torch mode: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        #endif
    }

    var zoomRange: ClosedRange<CGFloat> {
        guard let device = currentDevice() else { return 1...1 }
        let upper = min(device.maxAvailableVideoZoomFactor, practicalMaxZoomFactor)
        return device.minAvailableVideoZoomFactor...upper
    }

    var zoomOptions: [CameraZoomOption] {
        guard let device = currentDevice() else { return [.standard] }
        let maximum = min(device.maxAvailableVideoZoomFactor, practicalMaxZoomFactor)
        let switchFactors: [CGFloat] = device.virtualDeviceSwitchOverVideoZoomFactors.map {
            CGFloat($0.doubleValue)
        }
        let secondaryFactors: [CGFloat] = device.activeFormat.secondaryNativeResolutionZoomFactors
        let nativeFactors = [device.minAvailableVideoZoomFactor]
            + switchFactors
            + secondaryFactors
        return CameraZoomPolicy.options(
            minimumDeviceFactor: device.minAvailableVideoZoomFactor,
            maximumDeviceFactor: maximum,
            displayMultiplier: displayZoomMultiplier(for: device),
            nativeDeviceFactors: nativeFactors
        )
    }

    var currentZoomFactor: CGFloat {
        currentDevice()?.videoZoomFactor ?? 1
    }

    var exposureBiasRange: ClosedRange<Float> {
        guard let device = currentDevice() else { return 0...0 }
        // カメラの全範囲は極端な値を含むため、一般撮影向けの±2EVに制限する。
        let minimum = max(device.minExposureTargetBias, -2)
        let maximum = min(device.maxExposureTargetBias, 2)
        guard minimum <= maximum else { return 0...0 }
        return minimum...maximum
    }

    var currentExposureBias: Float {
        currentDevice()?.exposureTargetBias ?? 0
    }

    var isDeviceAdjusting: Bool {
        guard let device = currentDevice() else { return false }
        return device.isAdjustingExposure
            || device.isAdjustingWhiteBalance
            || device.isAdjustingFocus
    }

    private func discoverDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        ).devices.first
    }

    private func setCurrentDevice(_ device: AVCaptureDevice?) {
        deviceLock.lock()
        self.device = device
        deviceLock.unlock()
    }

    private func currentDevice() -> AVCaptureDevice? {
        deviceLock.lock()
        defer { deviceLock.unlock() }
        return device
    }

    private func currentCaptureOrientationMode() -> CaptureOrientationMode {
        orientationLock.lock()
        defer { orientationLock.unlock() }
        return captureOrientationMode
    }

    private func configureContinuousCapture(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = center
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = center
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            let supportsThirtyFPS = device.activeFormat.videoSupportedFrameRateRanges
                .contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
            if supportsThirtyFPS {
                let frameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            AppLog.capture.warning(
                "Failed to configure continuous camera controls: \(error.localizedDescription)"
            )
        }
    }

    private func configureInitialCameraControls(on device: AVCaptureDevice) {
        focusRestoreWorkItem?.cancel()
        focusRestoreWorkItem = nil
        do {
            try device.lockForConfiguration()
            let maximum = min(device.maxAvailableVideoZoomFactor, practicalMaxZoomFactor)
            device.videoZoomFactor = CameraZoomPolicy.defaultDeviceFactor(
                minimumDeviceFactor: device.minAvailableVideoZoomFactor,
                maximumDeviceFactor: maximum,
                displayMultiplier: displayZoomMultiplier(for: device)
            )
            if device.minExposureTargetBias <= 0,
               device.maxExposureTargetBias >= 0 {
                device.setExposureTargetBias(0, completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch {
            AppLog.capture.warning(
                "Failed to configure initial camera controls: \(error.localizedDescription)"
            )
        }
    }

    private func displayZoomMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            let multiplier = device.displayVideoZoomFactorMultiplier
            if multiplier.isFinite, multiplier > 0 {
                return multiplier
            }
        }

        // iOS 17では広角レンズの切替倍率を表示上の1xとして逆算する。
        guard device.isVirtualDevice,
              let wideIndex = device.constituentDevices.firstIndex(where: {
                  $0.deviceType == .builtInWideAngleCamera
              }),
              wideIndex > 0 else {
            return 1
        }
        let switchFactors = device.virtualDeviceSwitchOverVideoZoomFactors
        guard switchFactors.indices.contains(wideIndex - 1) else { return 1 }
        let wideDeviceFactor = CGFloat(switchFactors[wideIndex - 1].doubleValue)
        return wideDeviceFactor > 0 ? 1 / wideDeviceFactor : 1
    }

    private func disableTorchIfNeeded(on device: AVCaptureDevice) {
        guard device.hasTorch, device.torchMode == .on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            AppLog.capture.warning(
                "Failed to disable torch before switching cameras: \(error.localizedDescription)"
            )
        }
    }

    private var hasActiveAudioConnection: Bool {
        guard let connection = movieOutput.connection(with: .audio) else { return false }
        return connection.isEnabled
    }

    private var hasAudioInput: Bool {
        session.inputs.contains { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.audio)
        }
    }

    private func attachAudioInput() -> Bool {
        guard !hasAudioInput else { return true }
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            AppLog.capture.error("No audio device found.")
            return false
        }
        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            guard session.canAddInput(input) else {
                AppLog.capture.error("Audio input could not be attached to capture session.")
                return false
            }
            session.addInput(input)
            return true
        } catch {
            AppLog.capture.error("Error setting up audio input: \(error.localizedDescription)")
            return false
        }
    }

    private func configureVideoConnection(for position: AVCaptureDevice.Position) {
        guard let connection = movieOutput.connection(with: .video) else { return }
        let codec: AVVideoCodecType = movieOutput.availableVideoCodecTypes.contains(.hevc)
            ? .hevc
            : .h264
        movieOutput.setOutputSettings(
            [AVVideoCodecKey: codec],
            for: connection
        )
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
        guard connection.isVideoStabilizationSupported else { return }
        connection.preferredVideoStabilizationMode = .cinematicExtended
        if connection.activeVideoStabilizationMode != .cinematicExtended {
            connection.preferredVideoStabilizationMode = .cinematic
        }
        if connection.activeVideoStabilizationMode == .off {
            connection.preferredVideoStabilizationMode = .auto
        }
    }
}
