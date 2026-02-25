import Foundation
import SwiftUI
import Photos
import AVFoundation

final class CaptureScreenViewModel: ObservableObject {
    @Published var selectedDuration: TimeInterval = 3.0
    let durations: [TimeInterval] = [1.0, 2.0, 3.0, 4.0, 5.0]

    @Published var recordingProgress: Double = 0.0
    @Published var currentOrientation: UIDeviceOrientation = .portrait
    @Published var showGrid: Bool = false

    @Published var focusPoint: CGPoint? = nil
    @Published var showFocusIndicator: Bool = false
    @Published var showExposureSlider: Bool = false
    @Published var exposureValue: Float = 0.0

    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var lastZoomFactor: CGFloat = 1.0
    @Published var showZoomIndicator: Bool = false

    @Published var showPhotoSheet: Bool = false
    @Published var showSettings: Bool = false
    @Published var isTorchOn: Bool = false

    @Published var isCaptureUIActive: Bool = false
    @Published var latestThumbnail: UIImage? = nil
    @Published var showCaptureOnboarding: Bool = false

    private var progressTimer: Timer?
    private var focusOverlayTimer: Timer?
    private var lastShutterTapAt: Date = .distantPast
    private var activeDurationForProgress: TimeInterval = 3.0

    deinit {
        progressTimer?.invalidate()
        focusOverlayTimer?.invalidate()
    }

    func handleShutterTap(cameraService: CameraService) {
        let now = Date()
        if now.timeIntervalSince(lastShutterTapAt) < 0.3 { return }
        lastShutterTapAt = now

        if isCaptureUIActive {
            stopRecording(cameraService: cameraService)
        } else {
            guard cameraService.isReadyToRecord else { return }
            startRecording(cameraService: cameraService)
        }
    }

    func startRecording(cameraService: CameraService) {
        FeedbackManager.shared.triggerFeedback(soundEnabled: true)
        activeDurationForProgress = selectedDuration
        cameraService.startRecording(duration: selectedDuration, orientation: currentOrientation)
    }

    func stopRecording(cameraService: CameraService) {
        FeedbackManager.shared.triggerFeedback(soundEnabled: true)
        cameraService.stopRecording()
    }

    func handleRecordingChanged(_ isRecording: Bool) {
        withAnimation(.spring()) { self.isCaptureUIActive = isRecording }
        if isRecording {
            startProgressTimer()
        } else {
            stopProgressTimer()
        }
    }

    func setFocusPoint(_ point: CGPoint) {
        focusPoint = point
        exposureValue = 0

        withAnimation {
            showFocusIndicator = true
            showExposureSlider = true
        }

        focusOverlayTimer?.invalidate()
        focusOverlayTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self else { return }
            withAnimation {
                self.showFocusIndicator = false
                self.showExposureSlider = false
            }
        }
    }

    func applyPinchChanged(_ value: CGFloat, cameraService: CameraService) {
        let requested = lastZoomFactor * value
        let clamped = clampZoom(requested, cameraService: cameraService)
        currentZoomFactor = clamped
        cameraService.setZoom(factor: clamped)
        withAnimation(.spring()) { showZoomIndicator = true }
    }

    func applyPinchEnded(cameraService: CameraService) {
        lastZoomFactor = clampZoom(currentZoomFactor, cameraService: cameraService)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            withAnimation(.spring()) { self.showZoomIndicator = false }
        }
    }

    func handleCameraPositionChanged(newPosition: AVCaptureDevice.Position, cameraService: CameraService) {
        if newPosition != .back { isTorchOn = false }
        let z = clampZoom(currentZoomFactor, cameraService: cameraService)
        currentZoomFactor = z
        lastZoomFactor = z
    }

    func handleTorchAvailabilityChanged(_ available: Bool) {
        if !available { isTorchOn = false }
    }

    func handleSessionReadyChanged(_ ready: Bool, cameraService: CameraService) {
        guard ready else { return }
        let z = clampZoom(currentZoomFactor, cameraService: cameraService)
        currentZoomFactor = z
        lastZoomFactor = z
        cameraService.setZoom(factor: z)
    }

    func initializeZoom(cameraService: CameraService) {
        let initialZoom = clampZoom(1.0, cameraService: cameraService)
        currentZoomFactor = initialZoom
        lastZoomFactor = initialZoom
        cameraService.setZoom(factor: initialZoom)
    }

    func updateLatestThumbnail(preferredAssetIdentifier: String? = nil) {
        let asset: PHAsset?
        if let preferredAssetIdentifier {
            let byId = PHAsset.fetchAssets(withLocalIdentifiers: [preferredAssetIdentifier], options: nil)
            asset = byId.firstObject ?? latestAssetInDaylogAlbum()
        } else {
            asset = latestAssetInDaylogAlbum()
        }
        guard let asset else { return }

        let manager = PHImageManager.default()
        let target = CGSize(width: 200, height: 200)
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .fastFormat
        requestOptions.resizeMode = .fast
        requestOptions.isSynchronous = false

        manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: requestOptions) { [weak self] image, _ in
            if let image {
                self?.latestThumbnail = image
            }
        }
    }

    func captureReadinessHint(cameraService: CameraService) -> String? {
        if isCaptureUIActive { return "録画中" }
        if cameraService.isReadyToRecord { return nil }

        switch cameraService.captureReadinessReason {
        case .warmingUp:
            return "カメラ準備中…"
        case .permissionsMissing:
            return "権限が不足しています"
        case .interrupted:
            return "他アプリ使用中のため待機中"
        case .ready:
            return nil
        }
    }

    func clampZoom(_ zoom: CGFloat, cameraService: CameraService) -> CGFloat {
        let range = userZoomRange(cameraService: cameraService)
        return min(max(zoom, range.lowerBound), range.upperBound)
    }

    private func userZoomRange(cameraService: CameraService) -> ClosedRange<CGFloat> {
        let deviceRange = cameraService.zoomRange
        let lower = max(1.0, deviceRange.lowerBound)
        let upper = max(lower, min(deviceRange.upperBound, 10.0))
        return lower...upper
    }

    private func startProgressTimer() {
        recordingProgress = 0
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let duration = max(0.1, self.activeDurationForProgress)
            self.recordingProgress += 0.05 / duration
            if self.recordingProgress >= 1.0 {
                self.stopProgressTimer()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        recordingProgress = 0
    }

    private func latestAssetInDaylogAlbum() -> PHAsset? {
        let collectionOptions = PHFetchOptions()
        collectionOptions.predicate = NSPredicate(format: "title = %@", "daylog")
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: collectionOptions)
        guard let album = collections.firstObject else { return nil }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let videos = PHAsset.fetchAssets(in: album, options: options)
        return videos.firstObject
    }
}
