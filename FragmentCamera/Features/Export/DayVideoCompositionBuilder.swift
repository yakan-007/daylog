import CoreGraphics
import Foundation
@preconcurrency import AVFoundation

struct BuiltDayVideoComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let containsAudio: Bool
}

/// 素材AVAssetを配列に保持せず、1本ずつCompositionへ移してメモリの山を作らない。
final class DayVideoCompositionBuilder {
    private struct ClipLayout {
        let start: CMTime
        let duration: CMTime
        let preferredTransform: CGAffineTransform
        let orientedRect: CGRect
        let orientedSize: CGSize
    }

    func build(
        sourceCount: Int,
        storageMode: VideoStorageMode,
        stampContexts: [VideoPostProcessContext?] = [],
        textOverlaysByClip: [[VlogResolvedTextOverlay]] = [],
        progress: @Sendable (Double) -> Void = { _ in },
        assetAt: (Int) async throws -> AVAsset
    ) async throws -> BuiltDayVideoComposition {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw DayVideoExporterError.missingVideoTrack
        }
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var layouts: [ClipLayout] = []
        layouts.reserveCapacity(sourceCount)
        var cursor: CMTime = .zero
        var containsAudio = false

        for index in 0..<sourceCount {
            try Task.checkCancellation()
            let sourceAsset = try await assetAt(index)
            let assetDuration = try await sourceAsset.load(.duration)
            guard let sourceVideoTrack = try await sourceAsset
                    .loadTracks(withMediaType: .video)
                    .first else {
                throw DayVideoExporterError.missingVideoTrack
            }
            let sourceVideoTrackRange = try await sourceVideoTrack.load(.timeRange)
            guard let videoRange = MediaTrackTiming.usableVideoRange(
                assetDuration: assetDuration,
                trackRange: sourceVideoTrackRange
            ) else {
                throw DayVideoExporterError.missingVideoTrack
            }

            try compositionVideoTrack.insertTimeRange(
                videoRange,
                of: sourceVideoTrack,
                at: cursor
            )

            if let sourceAudioTrack = try await sourceAsset
                .loadTracks(withMediaType: .audio)
                .first,
               let compositionAudioTrack,
               let audioInsertion = MediaTrackTiming.audioInsertion(
                audioRange: try await sourceAudioTrack.load(.timeRange),
                videoRange: videoRange,
                destinationCursor: cursor
               ) {
                containsAudio = true
                try compositionAudioTrack.insertTimeRange(
                    audioInsertion.sourceRange,
                    of: sourceAudioTrack,
                    at: audioInsertion.destinationStart
                )
            }

            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let orientedRect = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
            let orientedSize = CGSize(
                width: abs(orientedRect.width),
                height: abs(orientedRect.height)
            )
            layouts.append(
                ClipLayout(
                    start: cursor,
                    duration: videoRange.duration,
                    preferredTransform: preferredTransform,
                    orientedRect: orientedRect,
                    orientedSize: orientedSize
                )
            )
            cursor = CMTimeAdd(cursor, videoRange.duration)
            progress(Double(index + 1) / Double(max(sourceCount, 1)))
        }

        // 音声のない素材だけの日では、空の音声トラックを残すと書き出し側が
        // 「未対応のメディア」と判定することがあるためCompositionから外す。
        if !containsAudio, let compositionAudioTrack {
            composition.removeTrack(compositionAudioTrack)
        }

        let encodingPolicy = VideoEncodingPolicy(storageMode: storageMode)
        let sourceRenderSize = DayVideoExportPolicy.preferredCanvasSourceSize(
            sizes: layouts.map(\.orientedSize),
            durations: layouts.map { $0.duration.seconds }
        )
        let renderSize = encodingPolicy.renderSize(for: sourceRenderSize)
        let instructions = layouts.map { layout in
            makeInstruction(
                layout: layout,
                compositionTrack: compositionVideoTrack,
                renderSize: renderSize
            )
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = encodingPolicy.frameDuration
        if stampContexts.count == layouts.count || textOverlaysByClip.count == layouts.count {
            let timedStamps: [TimedVideoStamp] = layouts.enumerated().compactMap { index, layout in
                guard stampContexts.count == layouts.count else { return nil }
                return stampContexts[index].map {
                    TimedVideoStamp(
                        context: $0,
                        start: layout.start,
                        duration: layout.duration,
                        contentFrame: contentFrame(
                            for: layout,
                            renderSize: renderSize
                        )
                    )
                }
            }
            let timedTextOverlays: [TimedVlogTextOverlay] = layouts.enumerated().flatMap { index, layout -> [TimedVlogTextOverlay] in
                guard textOverlaysByClip.count == layouts.count else { return [] }
                let clipDuration = max(layout.duration.seconds, 0)
                return textOverlaysByClip[index].compactMap { overlay -> TimedVlogTextOverlay? in
                    let start = min(max(overlay.timeRange.start, 0), clipDuration)
                    let end = min(max(overlay.timeRange.end ?? clipDuration, 0), clipDuration)
                    guard end > start else { return nil }
                    return TimedVlogTextOverlay(
                        overlay: overlay,
                        start: CMTimeAdd(
                            layout.start,
                            CMTime(seconds: start, preferredTimescale: 600)
                        ),
                        duration: CMTime(seconds: end - start, preferredTimescale: 600),
                        contentFrame: contentFrame(for: layout, renderSize: renderSize)
                    )
                }
            }
            DateStampLayerFactory.installTimedStamps(
                on: videoComposition,
                renderSize: renderSize,
                stamps: timedStamps,
                vlogTextOverlays: timedTextOverlays
            )
        }
        return BuiltDayVideoComposition(
            composition: composition,
            videoComposition: videoComposition,
            containsAudio: containsAudio
        )
    }

    private func makeInstruction(
        layout: ClipLayout,
        compositionTrack: AVCompositionTrack,
        renderSize: CGSize
    ) -> AVMutableVideoCompositionInstruction {
        let translation = CGAffineTransform(
            translationX: -layout.orientedRect.origin.x,
            y: -layout.orientedRect.origin.y
        )
        let scale = contentScale(for: layout, renderSize: renderSize)
        let destinationFrame = contentFrame(for: layout, renderSize: renderSize)
        let centered = CGAffineTransform(
            translationX: destinationFrame.origin.x,
            y: destinationFrame.origin.y
        )
        let transform = layout.preferredTransform
            .concatenating(translation)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(centered)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: compositionTrack
        )
        layerInstruction.setTransform(transform, at: layout.start)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: layout.start,
            duration: layout.duration
        )
        instruction.layerInstructions = [layerInstruction]
        return instruction
    }

    private func contentScale(
        for layout: ClipLayout,
        renderSize: CGSize
    ) -> CGFloat {
        min(
            1,
            min(
                renderSize.width / max(layout.orientedSize.width, 1),
                renderSize.height / max(layout.orientedSize.height, 1)
            )
        )
    }

    private func contentFrame(
        for layout: ClipLayout,
        renderSize: CGSize
    ) -> CGRect {
        let scale = contentScale(for: layout, renderSize: renderSize)
        let size = CGSize(
            width: layout.orientedSize.width * scale,
            height: layout.orientedSize.height * scale
        )
        return CGRect(
            x: (renderSize.width - size.width) / 2,
            y: (renderSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
