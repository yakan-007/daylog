import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers

/// 何のための書き出しか。写真に残すものは小さく、人に送るものは再生できる端末の多さを優先する。
enum VideoOutputPurpose: Sendable {
    /// 撮影後の保存と、編集の書き戻し（写真ライブラリに残る）。
    case library
    /// 1日分・1本の書き出し（共有シートで人に送る）。
    case sharing
    /// 同じ形式の分割ファイルをつなぐだけ。再エンコードしない。
    case passthrough
}

/// 撮影後変換と日次結合で共有する動画出力規則。
struct VideoEncodingPolicy {
    let storageMode: VideoStorageMode
    var purpose: VideoOutputPurpose = .sharing

    var exportPresets: [String] {
        switch (purpose, storageMode) {
        case (.passthrough, _):
            return [AVAssetExportPresetPassthrough]
        case (.library, .standard):
            // 撮影時と同じHEVCで書き戻す。H.264の最高画質だと元の動画より大きくなる。
            return [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
        case (.sharing, .standard):
            // 送り先の端末やサービスを選ばないH.264。
            return [AVAssetExportPresetHighestQuality]
        case (_, .compact):
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
        // つなぐだけの時は、分割ファイルごとに形式情報が少し違っても受け止められる mov にする。
        if purpose == .passthrough, supportedTypes.contains(.mov) { return .mov }
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
