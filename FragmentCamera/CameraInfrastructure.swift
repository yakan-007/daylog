import AVFoundation
import CoreLocation
import Photos
import UIKit

final class CameraPermissionService {
    func preparePermissions(onAuthorized: @escaping () -> Void, onDenied: @escaping (String, String) -> Void) {
        func reportDenied(title: String, message: String) {
            DispatchQueue.main.async {
                onDenied(title, message)
            }
        }

        func requestCapturePermissions() {
            #if targetEnvironment(simulator)
            DispatchQueue.main.async {
                onAuthorized()
            }
            #else
            let videoAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
            let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if videoAuthStatus == .authorized && audioAuthStatus == .authorized {
                DispatchQueue.main.async {
                    onAuthorized()
                }
                return
            }

            AVCaptureDevice.requestAccess(for: .video) { videoGranted in
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    if videoGranted && audioGranted {
                        DispatchQueue.main.async {
                            onAuthorized()
                        }
                    } else {
                        reportDenied(
                            title: "カメラへのアクセスが必要です",
                            message: "このアプリの撮影機能を利用するには、設定アプリからカメラとマイクへのアクセスを許可してください。"
                        )
                    }
                }
            }
            #endif
        }

        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch photoStatus {
        case .authorized, .limited:
            requestCapturePermissions()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    requestCapturePermissions()
                } else {
                    reportDenied(
                        title: "写真へのアクセスが必要です",
                        message: "撮影動画の保存や一覧表示のため、設定アプリから写真へのアクセスを許可してください。"
                    )
                }
            }
        default:
            reportDenied(
                title: "写真へのアクセスが必要です",
                message: "撮影動画の保存や一覧表示のため、設定アプリから写真へのアクセスを許可してください。"
            )
        }
    }

    func currentCameraPermissionState() -> CapturePermissionState {
        #if targetEnvironment(simulator)
        return .granted
        #else
        let video = AVCaptureDevice.authorizationStatus(for: .video)
        let audio = AVCaptureDevice.authorizationStatus(for: .audio)
        if video == .authorized && audio == .authorized {
            return .granted
        }
        if video == .denied || audio == .denied || video == .restricted || audio == .restricted {
            return .denied
        }
        return .unknown
        #endif
    }
}

final class CameraSessionController {
    private let prepareHandler: () -> Void
    private let switchHandler: () -> Void
    private let torchHandler: (Bool) -> Void
    private let zoomHandler: (CGFloat) -> Void
    private let focusHandler: (CGPoint) -> Void
    private let restartHandler: () -> Void

    init(
        prepareHandler: @escaping () -> Void,
        switchHandler: @escaping () -> Void,
        torchHandler: @escaping (Bool) -> Void,
        zoomHandler: @escaping (CGFloat) -> Void,
        focusHandler: @escaping (CGPoint) -> Void,
        restartHandler: @escaping () -> Void
    ) {
        self.prepareHandler = prepareHandler
        self.switchHandler = switchHandler
        self.torchHandler = torchHandler
        self.zoomHandler = zoomHandler
        self.focusHandler = focusHandler
        self.restartHandler = restartHandler
    }

    func prepareSession() { prepareHandler() }
    func switchCamera() { switchHandler() }
    func setTorch(enabled: Bool) { torchHandler(enabled) }
    func setZoom(factor: CGFloat) { zoomHandler(factor) }
    func focus(at point: CGPoint) { focusHandler(point) }
    func restartIfNeeded() { restartHandler() }
}

final class VideoRecordingController {
    private let startHandler: (TimeInterval, UIDeviceOrientation) -> Void
    private let stopHandler: () -> Void

    init(
        startHandler: @escaping (TimeInterval, UIDeviceOrientation) -> Void,
        stopHandler: @escaping () -> Void
    ) {
        self.startHandler = startHandler
        self.stopHandler = stopHandler
    }

    func startRecording(duration: TimeInterval, orientation: UIDeviceOrientation) {
        startHandler(duration, orientation)
    }

    func stopRecording() {
        stopHandler()
    }
}

final class CaptureSavePipeline {
    private let postProcessService: VideoPostProcessingService
    private let assetLibraryWriter: AssetLibraryWriter

    init(postProcessService: VideoPostProcessingService, assetLibraryWriter: AssetLibraryWriter) {
        self.postProcessService = postProcessService
        self.assetLibraryWriter = assetLibraryWriter
    }

    func processAndSaveRecording(
        outputURL: URL,
        location: CLLocation?,
        context: VideoPostProcessContext
    ) async throws -> (identifier: String, processed: ProcessedVideoResult) {
        let processed = try await postProcessService.process(inputURL: outputURL, context: context)
        let identifier = try await assetLibraryWriter.saveVideo(url: processed.finalURL, location: location)
        return (identifier, processed)
    }
}
