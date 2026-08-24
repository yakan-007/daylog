import AVFoundation
import Foundation
import Photos

struct EditableVideoStamp: Sendable {
    let context: VideoPostProcessContext
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
    private let placeNameResolver: any PlaceNameResolving
    private let settingsStore: DaylogSettingsStore

    init(
        postProcessPipeline: VideoPostProcessPipeline,
        temporaryFileStore: TemporaryFileStore,
        stampRecipeStore: VideoStampRecipeStore,
        placeNameResolver: any PlaceNameResolving = PlaceNameResolver(),
        settingsStore: DaylogSettingsStore = DaylogSettingsStore()
    ) {
        self.postProcessPipeline = postProcessPipeline
        self.temporaryFileStore = temporaryFileStore
        self.stampRecipeStore = stampRecipeStore
        self.placeNameResolver = placeNameResolver
        self.settingsStore = settingsStore
    }

    func load(assetLocalIdentifier: String) async throws -> EditableVideoStamp {
        let asset = try asset(localIdentifier: assetLocalIdentifier)
        guard var recipe = await stampRecipeStore.recipe(for: assetLocalIdentifier) else {
            throw DaylogStampEditingError.recipeUnavailable
        }

        if recipe.renderingMode == .burnOnCapture {
            let input = try await contentEditingInput(for: asset)
            if let adjustmentData = input.adjustmentData,
               DaylogStampAdjustment.canHandle(adjustmentData),
               let adjustedContext = try? DaylogStampAdjustment.context(
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
        return EditableVideoStamp(
            context: context,
            commonStampEnabled: commonSettings.isEnabled,
            commonElements: commonSettings.elements,
            visibilityOverride: recipe.visibilityOverride ?? .none,
            canUsePlace: asset.location != nil || context.placeName != nil,
            requiresVideoRegeneration: recipe.renderingMode == .burnOnCapture
        )
    }

    func apply(
        assetLocalIdentifier: String,
        visibilityOverride: VideoStampVisibilityOverride?
    ) async throws {
        let asset = try asset(localIdentifier: assetLocalIdentifier)
        guard let existingRecipe = await stampRecipeStore.recipe(
            for: assetLocalIdentifier
        ) else {
            throw DaylogStampEditingError.recipeUnavailable
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
            throw DaylogStampEditingError.inputUnavailable
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
        output.adjustmentData = try DaylogStampAdjustment.makePhotoAdjustment(context: renderContext)
        do {
            if FileManager.default.fileExists(atPath: output.renderedContentURL.path) {
                try FileManager.default.removeItem(at: output.renderedContentURL)
            }
            try FileManager.default.copyItem(
                at: renderedURL,
                to: output.renderedContentURL
            )
        } catch {
            throw DaylogStampEditingError.renderedContentUnavailable
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
                        throwing: error ?? DaylogStampEditingError.commitFailed
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
            throw DaylogStampEditingError.assetUnavailable
        }
        return asset
    }

    private func contentEditingInput(for asset: PHAsset) async throws -> PHContentEditingInput {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = DaylogStampAdjustment.canHandle

        return try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, info in
                if let input {
                    continuation.resume(returning: input)
                } else if let error = info[PHContentEditingInputErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: DaylogStampEditingError.inputUnavailable)
                }
            }
        }
    }
}
