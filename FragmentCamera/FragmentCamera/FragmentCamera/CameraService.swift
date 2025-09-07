import SwiftUI
import UIKit
import AVFoundation
import Photos
import CoreLocation
import OSLog

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
    @Published var isTorchAvailable = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isReadyToRecord = false
    // Default off to avoid slow post-processing between consecutive shots
    @AppStorage("isDateStampEnabled") private var isDateStampEnabled: Bool = false
    @AppStorage("dateStampFormat") private var dateStampFormat: String = "yy.MM.dd"
    
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
    private let sessionQueue = DispatchQueue(label: "CameraService.SessionQueue")
    private let sessionQueueSpecific = DispatchSpecificKey<Void>()
    private var pendingStart: (duration: TimeInterval, orientation: UIDeviceOrientation)?
    private var currentPlannedDuration: TimeInterval?
    // no export UI/monitoring

    override init() {
        super.init()
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

    func setupSession() {
#if targetEnvironment(simulator)
        AppLog.capture.debug("Simulator detected; skipping real camera setup.")
        DispatchQueue.main.async { self.isSessionReady = true }
#else
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
        let session = AVAudioSession.sharedInstance()
        do {
            // Use playAndRecord to allow shutter/feedback; tune for video capture
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.videoRecording)
            try session.setActive(true)
        } catch {
            AppLog.capture.error("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
        #endif
    }

    // Public restart for UI retry
    func restartSession() {
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func startRecording(duration: TimeInterval, orientation: UIDeviceOrientation) {
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
            } catch { AppLog.capture.error("Failed to lock device for configuration: \(error.localizedDescription)") }
            if completion != nil { completion?(false) }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Focus requested at \(point, privacy: .public). No action taken.")
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
            } catch { AppLog.capture.error("Failed to lock device for configuration: \(error.localizedDescription)") }
            if completion != nil { completion?(false) }
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
                let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                completion?(true)
            } catch { AppLog.capture.error("Failed to lock device for configuration: \(error.localizedDescription)") }
            if completion != nil { completion?(false) }
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
            }
            if completion != nil { completion?(false) }
        }
        #else
        AppLog.capture.debug("SIMULATOR: Torch toggle to \(on, privacy: .public) ignored.")
        completion?(true)
        #endif
    }

    // Snapshot helpers (read-only). Safe to call from UI for quick reads.
    var zoomRange: ClosedRange<CGFloat> {
        let minZ = device?.minAvailableVideoZoomFactor ?? 1.0
        let maxZ = device?.maxAvailableVideoZoomFactor ?? 1.0
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
        let tagLocation = bestRecentLocation(maxAge: 60, maxHAcc: 100)
        if isDateStampEnabled {
            addDateStamp(to: outputFileURL) { stampedVideoURL in
                guard let stampedVideoURL = stampedVideoURL else { return }
                self.saveVideoToLibrary(url: stampedVideoURL, location: tagLocation)
            }
        } else {
            saveVideoToLibrary(url: outputFileURL, location: tagLocation)
        }
    }
    
    private func getAlbum(completion: @escaping (PHAssetCollection?) -> Void) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", "daylog")
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let album = collections.firstObject { completion(album) } 
        else {
            var albumPlaceholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "daylog")
                albumPlaceholder = request.placeholderForCreatedAssetCollection
            }) { success, error in
                if success, let placeholder = albumPlaceholder {
                    let newCollections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                    completion(newCollections.firstObject)
                } else {
                    AppLog.export.error("Error creating album: \(error?.localizedDescription ?? "Unknown error")"); completion(nil)
                }
            }
        }
    }

    private func saveVideoToLibrary(url: URL, location: CLLocation?) {
        getAlbum { album in
            guard let album = album else { AppLog.export.error("Could not get or create album."); return }
            PHPhotoLibrary.shared().performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) else { return }
                assetRequest.location = location
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset, let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
            }) { success, error in
                if success {
                    AppLog.export.info("Video saved successfully and added to album.")
                    // Cleanup the temporary file
                    try? FileManager.default.removeItem(at: url)
                } else {
                    AppLog.export.error("Error saving video or adding to album: \(error?.localizedDescription ?? "Unknown error")")
                }
                // Stop location updates after save completes
                self.locationManager.stopUpdatingLocation()
            }
        }
    }

    private func trimHeadAndSave(url: URL) {
        let tagLocation = bestRecentLocation(maxAge: 60, maxHAcc: 100)
        Task {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                let trim = CMTime(seconds: 0.25, preferredTimescale: 600)
                let start = CMTimeCompare(duration, trim) > 0 ? trim : .zero
                let timeRange = CMTimeRange(start: start, duration: CMTimeSubtract(duration, start))
                let outBase = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { await MainActor.run { self.saveVideoToLibrary(url: url, location: tagLocation) }; return }
                let type: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
                let outURL = outBase.appendingPathExtension(type == .mp4 ? "mp4" : "mov")
                exporter.outputURL = outURL
                exporter.outputFileType = type
                exporter.timeRange = timeRange
                let taskID = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "TrimSave", expirationHandler: nil) }
                do {
                    try await exporter.export(to: outURL, as: type)
                    await MainActor.run {
                        self.saveVideoToLibrary(url: outURL, location: tagLocation)
                        UIApplication.shared.endBackgroundTask(taskID)
                    }
                } catch {
                    await MainActor.run {
                        self.saveVideoToLibrary(url: url, location: tagLocation)
                        UIApplication.shared.endBackgroundTask(taskID)
                    }
                }
            } catch {
                await MainActor.run { self.saveVideoToLibrary(url: url, location: tagLocation) }
            }
        }
    }
    
    private func addDateStamp(to videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: videoURL)
            Task {
                do {
                    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { completion(nil); return }
                    let composition = AVMutableComposition()
                    guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { completion(nil); return }
                let duration = try await asset.load(.duration)
                try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)

                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let preferredTransform = try await videoTrack.load(.preferredTransform)
                    let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
                    let renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))

                    // Text layer setup (top-right, monospaced, shadow)
                    let textLayer = CATextLayer()
                    let dateFormatter = DateFormatter(); dateFormatter.dateFormat = dateStampFormat
                    let fontSize = renderSize.height * 0.055
                    textLayer.string = dateFormatter.string(from: Date())
                    textLayer.font = "Menlo-Bold" as CFTypeRef
                    textLayer.fontSize = fontSize
                    textLayer.foregroundColor = UIColor.white.cgColor
                    textLayer.backgroundColor = UIColor.clear.cgColor
                    textLayer.alignmentMode = .right
                    textLayer.shadowOpacity = 0.6
                    textLayer.shadowRadius = 2
                    textLayer.shadowOffset = CGSize(width: 0, height: 1)
                    let scale = await MainActor.run { UIScreen.main.scale }
                    textLayer.contentsScale = scale
                    let topMargin = renderSize.height * 0.04
                    let rightMargin = renderSize.width * 0.05
                    textLayer.frame = CGRect(x: 0,
                                             y: topMargin,
                                             width: renderSize.width - rightMargin,
                                             height: renderSize.height * 0.1)

                    // Layers and composition
                let videoLayer = CALayer(); videoLayer.frame = CGRect(origin: .zero, size: renderSize)
                let overlayLayer = CALayer(); overlayLayer.frame = CGRect(origin: .zero, size: renderSize); overlayLayer.addSublayer(textLayer)
                // Parent layer must contain both videoLayer and overlay
                let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: renderSize)
                parentLayer.addSublayer(videoLayer)
                parentLayer.addSublayer(overlayLayer)
                let videoComposition = AVMutableVideoComposition(); videoComposition.renderSize = renderSize; videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
                let instruction = AVMutableVideoCompositionInstruction(); instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
                // Normalize upside-down orientation defensively
                var finalTransform = preferredTransform
                let angle = atan2(finalTransform.b, finalTransform.a) // radians
                let deg = (angle * 180 / .pi).truncatingRemainder(dividingBy: 360)
                if abs(abs(deg) - 180) < 45 { // around 180 degrees
                    finalTransform = finalTransform.rotated(by: .pi)
                    finalTransform = finalTransform.translatedBy(x: renderSize.width, y: renderSize.height)
                }
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack); layerInstruction.setTransform(finalTransform, at: .zero)
                instruction.layerInstructions = [layerInstruction]; videoComposition.instructions = [instruction]
                    // Show date only at start, then fade out
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 1.0
                    fade.toValue = 0.0
                    fade.beginTime = AVCoreAnimationBeginTimeAtZero + 2.0
                    fade.duration = 0.5
                    fade.fillMode = .forwards
                    fade.isRemovedOnCompletion = false
                    textLayer.add(fade, forKey: "fade")

                    // Export
                    let exportBaseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { completion(nil); return }
                    exporter.videoComposition = videoComposition
                    let supported = exporter.supportedFileTypes
                    let (outType, outURL): (AVFileType, URL) = {
                        if supported.contains(.mp4) { return (.mp4, exportBaseURL.appendingPathExtension("mp4")) }
                        if supported.contains(.mov) { return (.mov, exportBaseURL.appendingPathExtension("mov")) }
                        if let first = supported.first { return (first, exportBaseURL.appendingPathExtension(first.rawValue)) }
                        return (.mov, exportBaseURL.appendingPathExtension("mov"))
                    }()

                    let taskID = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "StampExport", expirationHandler: nil) }
                    do {
                        try await exporter.export(to: outURL, as: outType)
                        try? FileManager.default.removeItem(at: videoURL)
                        completion(outURL)
                    } catch {
                        AppLog.export.error("Failed to export (async): \(error.localizedDescription)")
                        completion(nil)
                    }
                    await MainActor.run { UIApplication.shared.endBackgroundTask(taskID) }
                } catch {
                    AppLog.export.error("Failed preparing composition: \(error.localizedDescription)")
                    completion(nil)
                }
            }
    }
    
    func checkForPermissions() {
        locationManager.requestWhenInUseAuthorization()
        #if targetEnvironment(simulator)
        setupSession()
        #else
        let videoAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if videoAuthStatus == .authorized && audioAuthStatus == .authorized {
            setupSession()
        } else {
            AVCaptureDevice.requestAccess(for: .video) { videoGranted in
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    if videoGranted && audioGranted {
                        DispatchQueue.main.async { self.setupSession() }
                    } else {
                        AppLog.permission.error("Camera or microphone access denied by user.")
                        DispatchQueue.main.async { self.permissionDenied = true }
                    }
                }
            }
        }
        #endif
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
        DispatchQueue.main.async { self.isSessionInterrupted = true }
        if let userInfo = notification.userInfo,
           let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) {
            AppLog.capture.warning("Session interrupted: \(String(describing: reason), privacy: .public)")
        } else {
            AppLog.capture.warning("Session interrupted")
        }
    }
    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { self.isSessionInterrupted = false }
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
        AppLog.capture.info("Session interruption ended")
    }
    @objc private func handleRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            AppLog.capture.error("Session runtime error: \(error.localizedDescription)")
        }
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
        // Require a minimum number of frames and several consecutive stable frames
        if warmFrameCount >= 5 && stableConsecutiveFrames >= 5 {
            DispatchQueue.main.async {
                self.isReadyToRecord = true
                if let pending = self.pendingStart {
                    self.pendingStart = nil
                    self.startRecordingNow(duration: pending.duration, orientation: pending.orientation)
                }
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
