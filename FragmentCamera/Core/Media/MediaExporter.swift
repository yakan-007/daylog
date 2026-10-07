import AVFoundation
import UIKit

enum MediaExporterError: LocalizedError {
    case exportSessionUnavailable
    case unsupportedOutputType
    case audioTrackMissing
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable:
            return L10n.text("書き出しセッションを作成できませんでした。")
        case .unsupportedOutputType:
            return L10n.text("この端末で使える書き出し形式が見つかりませんでした。")
        case .audioTrackMissing:
            return L10n.text("書き出した動画から音声が失われました。")
        case .exportFailed(let message):
            return message.isEmpty ? L10n.text("動画の書き出しに失敗しました。") : message
        }
    }
}

private final class MediaExportCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var exporter: AVAssetExportSession?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func register(_ exporter: AVAssetExportSession) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.exporter = exporter
            return true
        }
    }

    func unregister(_ exporter: AVAssetExportSession) {
        lock.withLock {
            guard self.exporter === exporter else { return }
            self.exporter = nil
        }
    }

    func cancel() {
        let exporter = lock.withLock { () -> AVAssetExportSession? in
            cancelled = true
            return self.exporter
        }
        exporter?.cancelExport()
    }
}

/// AVAssetExportSession.progressは書き出し中に読み取ることを想定した値。
/// 非Sendableなセッションをこの監視オブジェクトだけに閉じ込める。
private final class MediaExportProgressMonitor: @unchecked Sendable {
    private let exporter: AVAssetExportSession
    private let progress: @Sendable (Double) -> Void

    init(exporter: AVAssetExportSession, progress: @escaping @Sendable (Double) -> Void) {
        self.exporter = exporter
        self.progress = progress
    }

    func run() async {
        while !Task.isCancelled {
            progress(Double(exporter.progress))
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// 撮影後変換と日次結合で共有する、ファイル書き出しの唯一の実装。
final class MediaExporter {
    private let temporaryFileStore: TemporaryFileStore

    init(temporaryFileStore: TemporaryFileStore = TemporaryFileStore()) {
        self.temporaryFileStore = temporaryFileStore
    }

    func export(
        asset: AVAsset,
        videoComposition: AVVideoComposition?,
        encodingPolicy: VideoEncodingPolicy,
        outputPrefix: String,
        backgroundTaskName: String,
        requiresAudioTrack: Bool = false,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let cancellationController = MediaExportCancellationController()
        let taskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(
                withName: backgroundTaskName,
                expirationHandler: {
                    cancellationController.cancel()
                }
            )
        }

        do {
            let outputURL = try await withTaskCancellationHandler {
                try await performExport(
                    asset: asset,
                    videoComposition: videoComposition,
                    encodingPolicy: encodingPolicy,
                    outputPrefix: outputPrefix,
                    requiresAudioTrack: requiresAudioTrack,
                    cancellationController: cancellationController,
                    progress: progress
                )
            } onCancel: {
                cancellationController.cancel()
            }
            await endBackgroundTask(taskID)
            return outputURL
        } catch {
            await endBackgroundTask(taskID)
            throw error
        }
    }

    private func performExport(
        asset: AVAsset,
        videoComposition: AVVideoComposition?,
        encodingPolicy: VideoEncodingPolicy,
        outputPrefix: String,
        requiresAudioTrack: Bool,
        cancellationController: MediaExportCancellationController,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var lastError: Error?
        var createdExporter = false

        for preset in encodingPolicy.exportPresets {
            try Task.checkCancellation()
            guard !cancellationController.isCancelled else {
                throw CancellationError()
            }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            createdExporter = true
            guard cancellationController.register(exporter) else {
                throw CancellationError()
            }

            guard let outputType = encodingPolicy.preferredOutputType(
                from: exporter.supportedFileTypes
            ) else {
                cancellationController.unregister(exporter)
                lastError = MediaExporterError.unsupportedOutputType
                continue
            }

            let outputURL = try temporaryFileStore.makeURL(
                prefix: outputPrefix,
                pathExtension: VideoEncodingPolicy.pathExtension(for: outputType)
            )
            temporaryFileStore.removeIfExists(at: outputURL)
            exporter.outputURL = outputURL
            exporter.outputFileType = outputType
            exporter.shouldOptimizeForNetworkUse = true
            exporter.videoComposition = videoComposition

            do {
                progress(0)
                let progressMonitor = MediaExportProgressMonitor(
                    exporter: exporter,
                    progress: progress
                )
                let progressTask = Task {
                    await progressMonitor.run()
                }
                defer { progressTask.cancel() }
                try await exporter.export(to: outputURL, as: outputType)
                cancellationController.unregister(exporter)
                try Task.checkCancellation()
                guard !cancellationController.isCancelled else {
                    throw CancellationError()
                }
                if requiresAudioTrack {
                    let exportedAsset = AVURLAsset(url: outputURL)
                    let audioTracks = try await exportedAsset.loadTracks(withMediaType: .audio)
                    guard !audioTracks.isEmpty else {
                        throw MediaExporterError.audioTrackMissing
                    }
                }
                progress(1)
                return outputURL
            } catch {
                cancellationController.unregister(exporter)
                temporaryFileStore.removeIfExists(at: outputURL)
                if error is CancellationError
                    || Task.isCancelled
                    || cancellationController.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                AppLog.export.warning(
                    "media_export.retry preset=\(preset, privacy: .public) reason=\(error.localizedDescription, privacy: .private)"
                )
            }
        }

        guard createdExporter else {
            throw MediaExporterError.exportSessionUnavailable
        }
        if let lastError {
            // 容量不足やPhotoKit由来など、上位で原因別の案内を出せるよう
            // NSErrorのdomain/codeとunderlying errorを文字列へ潰さず返す。
            throw lastError
        }
        throw MediaExporterError.exportFailed("")
    }

    private func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) async {
        guard taskID != .invalid else { return }
        await MainActor.run {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}
