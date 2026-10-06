import AVFoundation
import CoreLocation

struct CaptureStampSaveDecision: Equatable {
    let shouldRenderDuringCapture: Bool
    let shouldSaveAsPhotoKitEdit: Bool
    let storedRenderingMode: StampRenderingMode
}

enum CaptureStampSavePolicy {
    static func decision(
        requestedMode: StampRenderingMode,
        stampEnabled: Bool,
        processedStampApplied: Bool? = nil
    ) -> CaptureStampSaveDecision {
        let shouldRender = requestedMode == .burnOnCapture && stampEnabled
        let shouldSaveAsEdit = shouldRender && processedStampApplied == true
        return CaptureStampSaveDecision(
            shouldRenderDuringCapture: shouldRender,
            shouldSaveAsPhotoKitEdit: shouldSaveAsEdit,
            storedRenderingMode: shouldRender && !shouldSaveAsEdit
                ? .playbackOverlay
                : requestedMode
        )
    }
}

final class CameraPermissionService {
    func preparePermissions(
        onAuthorized: @escaping () -> Void,
        onDenied: @escaping (String, String) -> Void
    ) {
        func reportDenied(title: String, message: String) {
            DispatchQueue.main.async {
                onDenied(title, message)
            }
        }

        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            onAuthorized()
        }
        #else
        func requestMicrophone() {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            switch status {
            case .authorized:
                DispatchQueue.main.async { onAuthorized() }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        DispatchQueue.main.async { onAuthorized() }
                    } else {
                        reportDenied(
                            title: L10n.text("マイクへのアクセスが必要です"),
                            message: L10n.text("動画と周囲の音を残すため、設定アプリからマイクへのアクセスを許可してください。")
                        )
                    }
                }
            default:
                reportDenied(
                    title: L10n.text("マイクへのアクセスが必要です"),
                    message: L10n.text("動画と周囲の音を残すため、設定アプリからマイクへのアクセスを許可してください。")
                )
            }
        }

        func requestCameraThenMicrophone() {
            let videoAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
            switch videoAuthStatus {
            case .authorized:
                requestMicrophone()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        requestMicrophone()
                    } else {
                        reportDenied(
                            title: L10n.text("カメラへのアクセスが必要です"),
                            message: L10n.text("動画を撮影するため、設定アプリからカメラへのアクセスを許可してください。")
                        )
                    }
                }
            default:
                reportDenied(
                    title: L10n.text("カメラへのアクセスが必要です"),
                    message: L10n.text("動画を撮影するため、設定アプリからカメラへのアクセスを許可してください。")
                )
            }
        }
        requestCameraThenMicrophone()
        #endif
    }
}

final class CaptureSavePipeline {
    private let postProcessPipeline: VideoPostProcessPipeline
    private let assetLibraryWriter: AssetLibraryWriter
    private let stampRecipeStore: VideoStampRecipeStore
    private let temporaryFileStore: TemporaryFileStore

    init(
        postProcessPipeline: VideoPostProcessPipeline,
        assetLibraryWriter: AssetLibraryWriter,
        stampRecipeStore: VideoStampRecipeStore,
        temporaryFileStore: TemporaryFileStore
    ) {
        self.postProcessPipeline = postProcessPipeline
        self.assetLibraryWriter = assetLibraryWriter
        self.stampRecipeStore = stampRecipeStore
        self.temporaryFileStore = temporaryFileStore
    }

    func processAndSaveRecording(
        outputURL: URL,
        location: CLLocation?,
        context: VideoPostProcessContext,
        renderingMode: StampRenderingMode
    ) async throws -> SavedRecordingResult {
        let processingDecision = CaptureStampSavePolicy.decision(
            requestedMode: renderingMode,
            stampEnabled: context.stampEnabled
        )
        let processingContext = processingDecision.shouldRenderDuringCapture
            ? context
            : context.replacingStampEnabled(false)
        let processed = try await postProcessPipeline.processRecordedVideo(
            inputURL: outputURL,
            context: processingContext
        )
        let identifier: String
        let saveDecision = CaptureStampSavePolicy.decision(
            requestedMode: renderingMode,
            stampEnabled: context.stampEnabled,
            processedStampApplied: processed.stampApplied
        )
        var storedRenderingMode = saveDecision.storedRenderingMode
        var didAttachBurnedStamp = false
        if saveDecision.shouldSaveAsPhotoKitEdit {
            let saveResult = try await assetLibraryWriter.saveVideo(
                originalURL: outputURL,
                renderedURL: processed.finalURL,
                adjustmentData: try VlogishStampAdjustment.makePhotoAdjustment(context: context),
                location: location
            )
            identifier = saveResult.identifier
            didAttachBurnedStamp = saveResult.didAttachRenderedContent
            if !saveResult.didAttachRenderedContent {
                // 原本だけの保存へフォールバックした場合、アプリ内表示を失わない。
                storedRenderingMode = .playbackOverlay
            }
        } else {
            identifier = try await assetLibraryWriter.saveVideo(
                url: processed.finalURL,
                location: location
            )
            if processed.finalURL != outputURL,
               temporaryFileStore.manages(outputURL) {
                temporaryFileStore.removeIfExists(at: outputURL)
            }
        }
        do {
            try await stampRecipeStore.save(VideoStampRecipe(
                assetLocalIdentifier: identifier,
                context: context,
                renderingMode: storedRenderingMode,
                visibilityOverride: nil
            ))
        } catch {
            // 写真への保存は完了しているため失敗扱いにして再保存させない。
            // レシピだけが失われたことはログへ残し、重複動画の生成を防ぐ。
            AppLog.save.error(
                "stamp_recipe.save.fail asset=\(identifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)"
            )
        }
        return SavedRecordingResult(
            identifier: identifier,
            stampApplied: didAttachBurnedStamp,
            didFallback: processed.didFallback
                || (processingDecision.shouldRenderDuringCapture && !didAttachBurnedStamp)
        )
    }
}
