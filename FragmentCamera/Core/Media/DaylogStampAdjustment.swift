import Foundation
import Photos

enum VlogishStampAdjustment {
    static let formatIdentifier = "com.leo.vlogish.stamp"
    static let formatVersion = "2.0"

    static func makePhotoAdjustment(
        context: VideoPostProcessContext
    ) throws -> PHAdjustmentData {
        PHAdjustmentData(
            formatIdentifier: formatIdentifier,
            formatVersion: formatVersion,
            data: try JSONEncoder().encode(context)
        )
    }

    static func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        adjustmentData.formatIdentifier == formatIdentifier
            && adjustmentData.formatVersion == formatVersion
    }

    static func context(from adjustmentData: PHAdjustmentData) throws -> VideoPostProcessContext {
        guard canHandle(adjustmentData) else {
            throw VlogishStampEditingError.unsupportedAdjustment
        }
        return try JSONDecoder().decode(
            VideoPostProcessContext.self,
            from: adjustmentData.data
        )
    }
}

enum VlogishStampEditingError: LocalizedError {
    case assetUnavailable
    case recipeUnavailable
    case unsupportedAdjustment
    case inputUnavailable
    case renderedContentUnavailable
    case commitFailed

    var errorDescription: String? {
        switch self {
        case .assetUnavailable:
            return L10n.text("動画が写真ライブラリに見つかりません。")
        case .recipeUnavailable:
            return L10n.text("この動画にはスタンプ編集情報がありません。")
        case .unsupportedAdjustment:
            return L10n.text("この動画の編集情報を読み込めません。")
        case .inputUnavailable:
            return L10n.text("スタンプなしの原本を読み込めませんでした。")
        case .renderedContentUnavailable:
            return L10n.text("編集後の動画を準備できませんでした。")
        case .commitFailed:
            return L10n.text("編集した動画を写真ライブラリへ反映できませんでした。")
        }
    }
}
