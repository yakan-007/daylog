import Foundation
import AVFoundation

enum VideoPostProcessError: LocalizedError {
    case inputMissing
    case audioTrackMissing
    case videoTrackMissing
    case compositionVideoTrackUnavailable
    case compositionAudioTrackUnavailable

    var errorDescription: String? {
        switch self {
        case .inputMissing:
            return L10n.text("録画ファイルが見つかりません。")
        case .audioTrackMissing:
            return L10n.text("録画ファイルに音声が含まれていません。")
        case .videoTrackMissing:
            return L10n.text("録画ファイルに映像が含まれていません。")
        case .compositionVideoTrackUnavailable:
            return L10n.text("映像の仕上げ処理を開始できませんでした。")
        case .compositionAudioTrackUnavailable:
            return L10n.text("音声の仕上げ処理を開始できませんでした。")
        }
    }
}

struct VideoPostProcessContext: Codable, Equatable, Sendable {
    let stampEnabled: Bool
    let stampDate: Date
    let format: String
    let zeroPadded: Bool
    let timeStyle: DateStampTimeStyle
    let sizeKey: String
    let position: DateStampPosition
    let elements: Set<DateStampElement>
    let fadesOut: Bool
    let placeName: String?
    let timeZoneIdentifier: String
    let storageMode: VideoStorageMode

    init(
        stampEnabled: Bool,
        stampDate: Date,
        format: String,
        zeroPadded: Bool,
        timeStyle: DateStampTimeStyle,
        sizeKey: String,
        position: DateStampPosition,
        elements: Set<DateStampElement>,
        fadesOut: Bool,
        placeName: String?,
        timeZoneIdentifier: String,
        storageMode: VideoStorageMode
    ) {
        self.stampEnabled = stampEnabled
        self.stampDate = stampDate
        self.format = format
        self.zeroPadded = zeroPadded
        self.timeStyle = timeStyle
        self.sizeKey = sizeKey
        self.position = position
        self.elements = elements
        self.fadesOut = fadesOut
        self.placeName = placeName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.storageMode = storageMode
    }

    var stampTimeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }

    func replacingStampEnabled(_ isEnabled: Bool) -> VideoPostProcessContext {
        VideoPostProcessContext(
            stampEnabled: isEnabled,
            stampDate: stampDate,
            format: format,
            zeroPadded: zeroPadded,
            timeStyle: timeStyle,
            sizeKey: sizeKey,
            position: position,
            elements: elements,
            fadesOut: fadesOut,
            placeName: placeName,
            timeZoneIdentifier: timeZoneIdentifier,
            storageMode: storageMode
        )
    }

    func replacingPlaceName(_ updatedPlaceName: String?) -> VideoPostProcessContext {
        VideoPostProcessContext(
            stampEnabled: stampEnabled,
            stampDate: stampDate,
            format: format,
            zeroPadded: zeroPadded,
            timeStyle: timeStyle,
            sizeKey: sizeKey,
            position: position,
            elements: elements,
            fadesOut: fadesOut,
            placeName: updatedPlaceName,
            timeZoneIdentifier: timeZoneIdentifier,
            storageMode: storageMode
        )
    }
}

final class VideoPostProcessPipeline {
    private let temporaryFileStore: TemporaryFileStore
    private let mediaExporter: MediaExporter

    init(
        temporaryFileStore: TemporaryFileStore = TemporaryFileStore(),
        mediaExporter: MediaExporter? = nil
    ) {
        self.temporaryFileStore = temporaryFileStore
        self.mediaExporter = mediaExporter ?? MediaExporter(temporaryFileStore: temporaryFileStore)
    }

    func processRecordedVideo(inputURL: URL, context: VideoPostProcessContext) async throws -> ProcessedVideoResult {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw VideoPostProcessError.inputMissing
        }

        let sourceAsset = AVURLAsset(url: inputURL)
        guard let sourceAudioTrack = try await sourceAsset
            .loadTracks(withMediaType: .audio)
            .first else {
            throw VideoPostProcessError.audioTrackMissing
        }
        guard let sourceVideoTrack = try await sourceAsset
            .loadTracks(withMediaType: .video)
            .first else {
            throw VideoPostProcessError.videoTrackMissing
        }
        let assetDuration = try await sourceAsset.load(.duration)
        let sourceVideoTrackRange = try await sourceVideoTrack.load(.timeRange)
        guard let videoRange = MediaTrackTiming.usableVideoRange(
            assetDuration: assetDuration,
            trackRange: sourceVideoTrackRange
        ) else {
            throw VideoPostProcessError.videoTrackMissing
        }
        guard let audioInsertion = MediaTrackTiming.audioInsertion(
            audioRange: try await sourceAudioTrack.load(.timeRange),
            videoRange: videoRange,
            destinationCursor: .zero
        ) else {
            throw VideoPostProcessError.audioTrackMissing
        }

        let requiresTranscode = context.stampEnabled || context.storageMode == .compact
        guard requiresTranscode else {
            return ProcessedVideoResult(
                finalURL: inputURL,
                stampApplied: false,
                didFallback: false
            )
        }

        do {
            let processedURL = try await exportProcessedVideo(
                sourceVideoTrack: sourceVideoTrack,
                videoRange: videoRange,
                sourceAudioTrack: sourceAudioTrack,
                audioInsertion: audioInsertion,
                context: context
            )
            return ProcessedVideoResult(
                finalURL: processedURL,
                stampApplied: context.stampEnabled,
                didFallback: false
            )
        } catch {
            AppLog.save.warning("save.postprocess.fail compact=\(context.storageMode == .compact, privacy: .public) reason=\(error.localizedDescription, privacy: .private)")
            guard context.storageMode == .standard else { throw error }
            return ProcessedVideoResult(
                finalURL: inputURL,
                stampApplied: false,
                didFallback: true
            )
        }
    }

    func renderEditedVideo(
        asset: AVAsset,
        context: VideoPostProcessContext
    ) async throws -> URL {
        guard let sourceAudioTrack = try await asset
            .loadTracks(withMediaType: .audio)
            .first else {
            throw VideoPostProcessError.audioTrackMissing
        }
        guard let sourceVideoTrack = try await asset
            .loadTracks(withMediaType: .video)
            .first else {
            throw VideoPostProcessError.videoTrackMissing
        }
        let assetDuration = try await asset.load(.duration)
        let sourceVideoTrackRange = try await sourceVideoTrack.load(.timeRange)
        guard let videoRange = MediaTrackTiming.usableVideoRange(
            assetDuration: assetDuration,
            trackRange: sourceVideoTrackRange
        ) else {
            throw VideoPostProcessError.videoTrackMissing
        }
        guard let audioInsertion = MediaTrackTiming.audioInsertion(
            audioRange: try await sourceAudioTrack.load(.timeRange),
            videoRange: videoRange,
            destinationCursor: .zero
        ) else {
            throw VideoPostProcessError.audioTrackMissing
        }
        return try await exportProcessedVideo(
            sourceVideoTrack: sourceVideoTrack,
            videoRange: videoRange,
            sourceAudioTrack: sourceAudioTrack,
            audioInsertion: audioInsertion,
            context: context
        )
    }

    private func exportProcessedVideo(
        sourceVideoTrack: AVAssetTrack,
        videoRange: CMTimeRange,
        sourceAudioTrack: AVAssetTrack,
        audioInsertion: AudioTrackInsertion,
        context: VideoPostProcessContext
    ) async throws -> URL {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoPostProcessError.compositionVideoTrackUnavailable
        }

        try compositionTrack.insertTimeRange(
            videoRange,
            of: sourceVideoTrack,
            at: .zero
        )

        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoPostProcessError.compositionAudioTrackUnavailable
        }
        try compositionAudioTrack.insertTimeRange(
            audioInsertion.sourceRange,
            of: sourceAudioTrack,
            at: audioInsertion.destinationStart
        )

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let sourceRenderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let encodingPolicy = VideoEncodingPolicy(storageMode: context.storageMode)
        let renderSize = encodingPolicy.renderSize(for: sourceRenderSize)
        let scale = renderSize.width / max(sourceRenderSize.width, 1)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = encodingPolicy.frameDuration

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        var finalTransform = preferredTransform
        let angle = atan2(finalTransform.b, finalTransform.a)
        let degrees = (angle * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if abs(abs(degrees) - 180) < 45 {
            finalTransform = finalTransform.rotated(by: .pi)
            finalTransform = finalTransform.translatedBy(x: sourceRenderSize.width, y: sourceRenderSize.height)
        }
        if scale < 1 {
            finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        if context.stampEnabled {
            DateStampLayerFactory.installSingleStamp(
                on: videoComposition,
                renderSize: renderSize,
                context: context
            )
        }

        return try await mediaExporter.export(
            asset: composition,
            videoComposition: videoComposition,
            encodingPolicy: encodingPolicy,
            outputPrefix: "processed",
            backgroundTaskName: "VlogishVideoSave",
            requiresAudioTrack: true
        )
    }

}
