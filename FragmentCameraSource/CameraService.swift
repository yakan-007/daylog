import SwiftUI
import AVFoundation
import Photos

// MARK: - Camera Service
class CameraService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var isRecording = false
    @Published var currentPosition: AVCaptureDevice.Position = .back

    private var session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var movieOutput = AVCaptureMovieFileOutput()

    override init() {
        super.init()
        setupSession()
    }

    func setupSession() {
        session.beginConfiguration()

        if let videoInput = videoInput {
            session.removeInput(videoInput)
            self.videoInput = nil
        }

        session.sessionPreset = .high
        
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition)
        guard let device = device else { 
            print("Error: No \(self.currentPosition) camera found.")
            session.commitConfiguration()
            return
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.videoInput = newInput
            } else {
                print("Could not add video input to session")
            }
        } catch {
            print("Error setting up video input: \(error)")
        }
        
        if session.outputs.isEmpty {
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        }

        session.commitConfiguration()

        if !session.isRunning {
            DispatchQueue.global(qos: .background).async {
                self.session.startRunning()
            }
        }
    }

    func switchCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        setupSession()
    }

    func startRecording() {
        guard let output = movieOutput.connection(with: .video) else { return }
        if output.isVideoOrientationSupported {
            // Get the current device orientation
            let deviceOrientation = UIDevice.current.orientation
            let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) ?? .portrait
            output.videoOrientation = videoOrientation
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }

    func stopRecording() {
        movieOutput.stopRecording()
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error recording video: \(error.localizedDescription)")
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { saved, error in
            if saved {
                print("Video saved successfully to photo library.")
            } else if let error = error {
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
        
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
                if status != .authorized {
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