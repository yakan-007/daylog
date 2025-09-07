import SwiftUI
import AVFoundation
import Photos

// MARK: - Camera Service
class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var isRecording = false
    @Published var currentPosition: AVCaptureDevice.Position = .back
    @Published var isSessionInterrupted = false

    private var session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var videoInput: AVCaptureDeviceInput?
    private var movieOutput = AVCaptureMovieFileOutput()

    override init() {
        super.init()
        setupSession()
        setupSessionObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()

            if let videoInput = self.videoInput {
                self.session.removeInput(videoInput)
                self.videoInput = nil
            }

            self.session.sessionPreset = .high

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition)
            guard let device = device else {
                print("Error: No \(self.currentPosition) camera found.")
                self.session.commitConfiguration()
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                } else {
                    print("Could not add video input to session")
                }
            } catch {
                print("Error setting up video input: \(error)")
            }

            if self.session.outputs.isEmpty {
                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
            }

            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func switchCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        setupSession()
    }

    func startRecording() {
        sessionQueue.async {
            guard let output = self.movieOutput.connection(with: .video) else { return }
            if output.isVideoOrientationSupported {
                let deviceOrientation = UIDevice.current.orientation
                let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) ?? .portrait
                output.videoOrientation = videoOrientation
            }

            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }

    func stopRecording() {
        sessionQueue.async {
            self.movieOutput.stopRecording()
            DispatchQueue.main.async {
                self.isRecording = false
            }
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error recording video: \(error.localizedDescription)")
            return
        }
        
        Task {
            do {
                try await PHPhotoLibrary.shared().performChangesAsync {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }
                print("Video saved successfully to photo library.")
            } catch {
                print("Error saving video: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Permissions
    func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    print("Camera access denied.")
                }
            }
        default:
            print("Camera access previously denied.")
        }
        
        let photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch photosStatus {
        case .authorized, .limited:
            break
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                if !(status == .authorized || status == .limited) {
                    print("Photo library access denied.")
                }
            }
        default:
            print("Photo library access previously denied.")
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        return preview
    }

    // MARK: - Session interruption handling
    private func setupSessionObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruption(_:)), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruptionEnded(_:)), name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRuntimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    @objc private func handleSessionInterruption(_ notification: Notification) {
        DispatchQueue.main.async { self.isSessionInterrupted = true }
        if let userInfo = notification.userInfo,
           let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) {
            print("Session interrupted: \(reason)")
        } else {
            print("Session interrupted")
        }
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { self.isSessionInterrupted = false }
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
        print("Session interruption ended")
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("Session runtime error: \(error)")
        }
        // Try to recover
        sessionQueue.async {
            self.session.startRunning()
        }
    }
}

// MARK: - Camera View (SwiftUI Bridge)
struct CameraView: UIViewControllerRepresentable {
    @ObservedObject var cameraService: CameraService

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let previewLayer = cameraService.getPreviewLayer()
        previewLayer.frame = viewController.view.bounds
        viewController.view.layer.addSublayer(previewLayer)
        
        viewController.view.layer.masksToBounds = true
        previewLayer.frame = viewController.view.bounds
        
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            previewLayer.frame = viewController.view.bounds
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// Helper extension to map UIDevice.Orientation to AVCaptureVideoOrientation
extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight // Note the mapping
        case .landscapeRight: self = .landscapeLeft // Note the mapping
        default: return nil
        }
    }
}

// MARK: - Async helpers
extension PHPhotoLibrary {
    func performChangesAsync(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.performChanges(changes) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    let err = NSError(domain: "PHPhotoLibrary.performChanges", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown failure saving to photo library"])
                    continuation.resume(throwing: err)
                }
            }
        }
    }
}
