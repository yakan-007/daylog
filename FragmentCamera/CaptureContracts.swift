import Foundation
import AVFoundation
import CoreGraphics
import UIKit

struct CaptureStateSnapshot: Equatable {
    let isRecording: Bool
    let isSessionReady: Bool
    let isSessionInterrupted: Bool
    let isReadyToRecord: Bool
    let isTorchAvailable: Bool
    let cameraPosition: AVCaptureDevice.Position
    let readinessReason: CaptureReadinessReason
}

protocol CaptureCommand: AnyObject {
    func startRecording(duration: TimeInterval, orientation: UIDeviceOrientation)
    func stopRecording()
    func switchCamera()
    func focus(at point: CGPoint, completion: ((Bool) -> Void)?)
    func setExposure(bias: Float, completion: ((Bool) -> Void)?)
    func setZoom(factor: CGFloat, completion: ((Bool) -> Void)?)
    func toggleTorch(on: Bool, completion: ((Bool) -> Void)?)
}
