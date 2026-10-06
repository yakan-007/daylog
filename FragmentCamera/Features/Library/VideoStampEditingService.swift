import AVFoundation
import Foundation
import Photos

struct EditableVideoStamp: Sendable {
    let context: VideoPostProcessContext
    let clipDuration: TimeInterval
    let videoAspectRatio: Double
    /// 保存済みの編集。まだ編集していないクリップでは、共通設定から作った初期状態が入る。
    let clipEdit: VlogClipEdit
    /// まだ一度も保存していないクリップか。
    let isFirstEdit: Bool
    /// 共通の日付スタンプ設定（「全体設定に戻す」と、日付・時刻を後から出す時の書式に使う）。
    let stampSettings: DateStampSettings
    /// 撮影場所の名前。取得できない時は nil（「場所」を足せない）。
    let placeName: String?
    let sourceMetadata: VlogClipSourceMetadata
    let commonStampEnabled: Bool
    let commonElements: Set<DateStampElement>
    let visibilityOverride: VideoStampVisibilityOverride
    let canUsePlace: Bool
    let requiresVideoRegeneration: Bool
}

final class VideoStampEditingService {
    private let postProcessPipeline: VideoPostProcessPipeline
    private let temporaryFileStore: TemporaryFileStore
    private let stampRecipeStore: VideoStampRecipeStore
    private let clipEditStore: VlogClipEditStore
    private let placeNameResolver: any PlaceNameResolving
    private let settingsStore: VlogishSettingsStore

    init(
        postProcessPipeline: VideoPostProcessPipeline,
        temporaryFileStore: TemporaryFileStore,
        stampRecipeStore: VideoStampRecipeStore,
        clipEditStore: VlogClipEditStore,
        placeNameResolver: any PlaceNameResolving = PlaceNameResolver(),
        settingsStore: VlogishSettingsStore = VlogishSettingsStore()
    ) {
        self.postProcessPipeline = postProcessPipeline
        self.temporaryFileStore = temporaryFileStore
        self.stampRecipeStore = stampRecipeStore
        self.clipEditStore = clipEditStore
        self.placeNameResolver = placeNameResolver
        self.settingsStore = settingsStore
    }

    func load(assetLocalIdentifier: String) async throws -> EditableVideoStamp {
        let asset = try asset(localIdentifier: assetLocalIdentifier)
        guard var recipe = await stampRecipeStore.recipe(for: assetLocalIdentifier) else {
            throw VlogishStampEditingError.recipeUnavailable
        }

        if recipe.renderingMode == .burnOnCapture {
            let input = try await contentEditingInput(for: asset)
            if let adjustmentData = input.adjustmentData,
               VlogishStampAdjustment.canHandle(adjustmentData),
               let adjustedContext = try? VlogishStampAdjustment.context(
                from: adjustmentData
               ) {
                recipe = VideoStampRecipe(
                    assetLocalIdentifier: assetLocalIdentifier,
                    context: adjustedContext,
                    renderingMode: .burnOnCapture,
                    visibilityOverride: recipe.visibilityOverride
                )
                try? await stampRecipeStore.save(recipe)
            }
        }
        let commonSettings = settingsStore.dateStampSettings
        let effectiveSettings = commonSettings.applying(recipe.visibilityOverride)
        let context = effectiveSettings.recordingContext(
            capturedAt: recipe.context.stampDate,
            placeName: recipe.context.placeName,
            timeZoneIdentifier: recipe.context.timeZoneIdentifier,
            storageMode: recipe.context.storageMode
        )
        let videoAspectRatio = asset.pixelHeight > 0
            ? Double(asset.pixelWidth) / Double(asset.pixelHeight)
            : 9.0 / 16.0
        var placeName = context.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if placeName?.isEmpty ?? true, let location = asset.location {
            placeName = await placeNameResolver.placeName(for: location)
        }
        let savedEdit = try await clipEditStore.edit(for: assetLocalIdentifier)
        let clipEdit = savedEdit ?? VlogClipEdit(
            assetLocalIdentifier: assetLocalIdentifier,
            // 初めて開いた時は、共通設定の日付スタンプをそのまま置いておく。
            block: VlogStampLayerSeeder.block(settings: effectiveSettings, placeName: placeName),
            sourceTimeZoneIdentifier: context.timeZoneIdentifier
        )
        return EditableVideoStamp(
            context: context,
            clipDuration: asset.duration,
            videoAspectRatio: videoAspectRatio,
            clipEdit: clipEdit,
            isFirstEdit: savedEdit == nil,
            stampSettings: commonSettings,
            placeName: placeName,
            sourceMetadata: VlogClipSourceMetadata(
                capturedAt: context.stampDate,
                capturedPlaceName: context.placeName,
                timeZoneIdentifier: context.timeZoneIdentifier
            ),
            commonStampEnabled: commonSettings.isEnabled,
            commonElements: commonSettings.elements,
            visibilityOverride: recipe.visibilityOverride ?? .none,
            canUsePlace: asset.location != nil || context.placeName != nil,
            requiresVideoRegeneration: recipe.renderingMode == .burnOnCapture
        )
    }

    func saveClipEdit(_ edit: VlogClipEdit, clipDuration: TimeInterval) async throws {
        try await clipEditStore.save(edit, clipDuration: clipDuration)
    }

    /// 編集内容の保存と「共通スタンプを隠す」設定を、ひとまとまりの操作として行う。
    ///
    /// 後半（共通スタンプを隠す）が失敗したら、前半の編集内容を元に戻してから失敗を返す。
    /// 途中まで保存されて、次の再生・書き出しで共通スタンプと編集の文字が二重に出ることを防ぐ。
    func saveClipEdit(
        _ edit: VlogClipEdit,
        clipDuration: TimeInterval,
        hidingCommonStamp: Bool
    ) async throws {
        let identifier = edit.assetLocalIdentifier
        let previous = try await clipEditStore.edit(for: identifier)
        try await clipEditStore.save(edit, clipDuration: clipDuration)
        guard hidingCommonStamp else { return }
        do {
            try await apply(
                assetLocalIdentifier: identifier,
                visibilityOverride: VideoStampVisibilityOverride(hidesStamp: true, hiddenElements: [])
            )
        } catch {
            do {
                if let previous {
                    try await clipEditStore.save(previous, clipDuration: clipDuration)
                } else {
                    try await clipEditStore.removeEdit(for: identifier)
                }
            } catch let rollbackError {
                AppLog.storage.error(
                    "clip_edit.rollback.fail reason=\(rollbackError.localizedDescription, privacy: .private)"
                )
            }
            throw error
        }
    }

    /// 編集画面専用のプレビュー。通常再生の状態機械とは共有せず、閉じたら必ず破棄する。
    @MainActor
    @discardableResult
    func requestPreviewPlayerItem(
        assetLocalIdentifier: String,
        completion: @escaping @MainActor (Result<AVPlayerItem, Error>) -> Void
    ) throws -> PHImageRequestID {
        let asset = try asset(localIdentifier: assetLocalIdentifier)
        return AssetPlaybackLoader.shared.requestPlayerItem(
            for: asset,
            deliveryMode: .automatic,
            timeout: 20,
            completion: completion
        )
    }

    @MainActor
    func cancelPreviewRequest(_ requestID: PHImageRequestID?) {
        AssetPlaybackLoader.shared.cancel(requestID)
    }

    func apply(
        assetLocalIdentifier: String,
        visibilityOverride: VideoStampVisibilityOverride?
    ) async throws {
        let asset = try asset(localIdentifier: assetLocalIdentifier)
        guard let existingRecipe = await stampRecipeStore.recipe(
            for: assetLocalIdentifier
        ) else {
            throw VlogishStampEditingError.recipeUnavailable
        }
        let renderingMode = existingRecipe.renderingMode
        let effectiveSettings = settingsStore.dateStampSettings
            .applying(visibilityOverride)
        var storedContext = existingRecipe.context
        if effectiveSettings.shouldResolvePlaceName(
            storedPlaceName: storedContext.placeName,
            hasAssetLocation: asset.location != nil
        ),
           let location = asset.location {
            storedContext = storedContext.replacingPlaceName(
                await placeNameResolver.placeName(for: location)
            )
        }
        let renderContext = effectiveSettings.recordingContext(
            capturedAt: storedContext.stampDate,
            placeName: storedContext.placeName,
            timeZoneIdentifier: storedContext.timeZoneIdentifier,
            storageMode: storedContext.storageMode
        )

        if renderingMode == .playbackOverlay {
            try await stampRecipeStore.save(VideoStampRecipe(
                assetLocalIdentifier: assetLocalIdentifier,
                context: storedContext,
                renderingMode: renderingMode,
                visibilityOverride: visibilityOverride
            ))
            return
        }

        let input = try await contentEditingInput(for: asset)
        guard let audiovisualAsset = input.audiovisualAsset else {
            throw VlogishStampEditingError.inputUnavailable
        }

        let renderedURL = try await postProcessPipeline.renderEditedVideo(
            asset: audiovisualAsset,
            context: renderContext
        )
        defer {
            if temporaryFileStore.manages(renderedURL) {
                temporaryFileStore.removeIfExists(at: renderedURL)
            }
        }

        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = try VlogishStampAdjustment.makePhotoAdjustment(context: renderContext)
        do {
            if FileManager.default.fileExists(atPath: output.renderedContentURL.path) {
                try FileManager.default.removeItem(at: output.renderedContentURL)
            }
            try FileManager.default.copyItem(
                at: renderedURL,
                to: output.renderedContentURL
            )
        } catch {
            throw VlogishStampEditingError.renderedContentUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: asset)
                request.contentEditingOutput = output
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? VlogishStampEditingError.commitFailed
                    )
                }
            }
        }
        do {
            try await stampRecipeStore.save(VideoStampRecipe(
                assetLocalIdentifier: assetLocalIdentifier,
                context: storedContext,
                renderingMode: renderingMode,
                visibilityOverride: visibilityOverride
            ))
        } catch {
            // 焼き込みモードでは PhotoKit adjustment が正本なので、動画の編集成功を
            // 取り消さない。次回読込時に adjustment とレシピを再同期する。
            AppLog.save.error(
                "stamp_recipe.update.fail asset=\(assetLocalIdentifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func asset(localIdentifier: String) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        ).firstObject else {
            throw VlogishStampEditingError.assetUnavailable
        }
        return asset
    }

    private func contentEditingInput(for asset: PHAsset) async throws -> PHContentEditingInput {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = VlogishStampAdjustment.canHandle

        return try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, info in
                if let input {
                    continuation.resume(returning: input)
                } else if let error = info[PHContentEditingInputErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: VlogishStampEditingError.inputUnavailable)
                }
            }
        }
    }
}
