import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers

/// 撮影後変換と日次結合で共有する動画出力規則。
struct VideoEncodingPolicy {
    let storageMode: VideoStorageMode

    var exportPresets: [String] {
        switch storageMode {
        case .standard:
            return [AVAssetExportPresetHighestQuality]
        case .compact:
            // HEVCを優先し、利用できない端末では720p H.264へ切り替える。
            return [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720]
        }
    }

    var frameDuration: CMTime {
        CMTime(value: 1, timescale: 30)
    }

    func renderSize(for sourceSize: CGSize) -> CGSize {
        guard storageMode == .compact else { return sourceSize }
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > 1280 else { return sourceSize }
        let scale = 1280 / longestSide
        return CGSize(
            width: even(sourceSize.width * scale),
            height: even(sourceSize.height * scale)
        )
    }

    func preferredOutputType(from supportedTypes: [AVFileType]) -> AVFileType? {
        if supportedTypes.contains(.mp4) { return .mp4 }
        if supportedTypes.contains(.mov) { return .mov }
        return supportedTypes.first
    }

    static func pathExtension(for fileType: AVFileType) -> String {
        if let extensionName = UTType(fileType.rawValue)?.preferredFilenameExtension {
            return extensionName
        }
        switch fileType {
        case .mov:
            return "mov"
        default:
            return "mp4"
        }
    }

    private func even(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }
}
