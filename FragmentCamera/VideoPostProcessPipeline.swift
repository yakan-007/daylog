import Foundation
import AVFoundation
import UIKit

struct VideoPostProcessContext {
    let stampEnabled: Bool
    let stampDate: Date
    let format: String
    let zeroPadded: Bool
    let sizeKey: String
}

struct ProcessedVideo {
    let url: URL
    let stampApplied: Bool
    let usedFallback: Bool
}

final class VideoPostProcessPipeline {
    func processRecordedVideo(inputURL: URL, context: VideoPostProcessContext) async throws -> ProcessedVideo {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw NSError(domain: "VideoPostProcessPipeline", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Input video not found"])
        }
        guard context.stampEnabled else {
            return ProcessedVideo(url: inputURL, stampApplied: false, usedFallback: false)
        }

        do {
            let stampedURL = try await applyDateStamp(to: inputURL, context: context)
            try? FileManager.default.removeItem(at: inputURL)
            return ProcessedVideo(url: stampedURL, stampApplied: true, usedFallback: false)
        } catch {
            AppLog.save.warning("save.postprocess.fallback reason=\(error.localizedDescription, privacy: .public)")
            return ProcessedVideo(url: inputURL, stampApplied: false, usedFallback: true)
        }
    }

    private func applyDateStamp(to videoURL: URL, context: VideoPostProcessContext) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoPostProcessPipeline", code: -1002, userInfo: [NSLocalizedDescriptionKey: "Video track missing"])
        }

        let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let sourceHasAudio = (sourceAudioTrack != nil)

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VideoPostProcessPipeline", code: -1003, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition video track"])
        }

        let duration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        try compositionTrack.insertTimeRange(fullRange, of: videoTrack, at: .zero)

        if let sourceAudioTrack {
            guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw NSError(domain: "VideoPostProcessPipeline", code: -1004, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition audio track"])
            }
            try compositionAudioTrack.insertTimeRange(fullRange, of: sourceAudioTrack, at: .zero)
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))

        let textLayer = CATextLayer()
        textLayer.string = DateStampFormatter.string(
            from: context.stampDate,
            storedFormat: context.format,
            zeroPadded: context.zeroPadded
        )
        textLayer.font = "Menlo-Bold" as CFTypeRef
        textLayer.fontSize = DateStampStyle.fontSize(for: renderSize, sizeKey: context.sizeKey)
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.backgroundColor = UIColor.clear.cgColor
        textLayer.alignmentMode = .right
        textLayer.shadowOpacity = 0.6
        textLayer.shadowRadius = 2
        textLayer.shadowOffset = CGSize(width: 0, height: 1)
        textLayer.contentsScale = await MainActor.run { UIScreen.main.scale }
        textLayer.frame = CGRect(
            x: 0,
            y: DateStampStyle.topMargin(for: renderSize),
            width: renderSize.width - DateStampStyle.rightMargin(for: renderSize),
            height: DateStampStyle.textHeight(for: renderSize, sizeKey: context.sizeKey)
        )

        let videoLayer = CALayer(); videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let overlayLayer = CALayer(); overlayLayer.frame = CGRect(origin: .zero, size: renderSize); overlayLayer.addSublayer(textLayer)
        let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        var finalTransform = preferredTransform
        let angle = atan2(finalTransform.b, finalTransform.a)
        let deg = (angle * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if abs(abs(deg) - 180) < 45 {
            finalTransform = finalTransform.rotated(by: .pi)
            finalTransform = finalTransform.translatedBy(x: renderSize.width, y: renderSize.height)
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.beginTime = AVCoreAnimationBeginTimeAtZero + 2.0
        fade.duration = 0.5
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        textLayer.add(fade, forKey: "fade")

        let exportBaseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VideoPostProcessPipeline", code: -1005, userInfo: [NSLocalizedDescriptionKey: "Failed to create exporter"])
        }
        exporter.videoComposition = videoComposition
        let supported = exporter.supportedFileTypes
        let (outType, outURL): (AVFileType, URL) = {
            if supported.contains(.mp4) { return (.mp4, exportBaseURL.appendingPathExtension("mp4")) }
            if supported.contains(.mov) { return (.mov, exportBaseURL.appendingPathExtension("mov")) }
            if let first = supported.first { return (first, exportBaseURL.appendingPathExtension(first.rawValue)) }
            return (.mov, exportBaseURL.appendingPathExtension("mov"))
        }()

        let taskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "StampExport", expirationHandler: nil)
        }
        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        try await exporter.export(to: outURL, as: outType)

        if sourceHasAudio {
            let outAsset = AVURLAsset(url: outURL)
            let outAudioTracks = try await outAsset.loadTracks(withMediaType: .audio)
            if outAudioTracks.isEmpty {
                throw NSError(domain: "VideoPostProcessPipeline", code: -1006, userInfo: [NSLocalizedDescriptionKey: "Stamped video lost audio track"])
            }
        }

        return outURL
    }
}
