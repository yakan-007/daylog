import AVFoundation
import Photos

struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum DayVideoExportPhase: Equatable, Sendable {
    case locatingAssets(total: Int)
    case preparing
    case resolvingStamps(current: Int, total: Int)
    case exportingClip
    case merging
    case processingChunk(current: Int, total: Int)
    case combiningChunks
    case finalizing
    case cancelling
    case completed

    var title: String {
        switch self {
        case .locatingAssets(let total):
            return total == 1
                ? L10n.text("1本の動画を確認中")
                : L10n.text("%d本の動画を確認中", total)
        case .preparing:
            return L10n.text("書き出しを準備中")
        case .resolvingStamps(let current, let total):
            return L10n.text("スタンプを確認中（%d/%d）", current, total)
        case .exportingClip:
            return L10n.text("動画を書き出し中")
        case .merging:
            return L10n.text("動画を結合・書き出し中")
        case .processingChunk(let current, let total):
            return L10n.text("分割動画を作成中（%d/%d）", current, total)
        case .combiningChunks:
            return L10n.text("分割した動画を結合中")
        case .finalizing:
            return L10n.text("最終動画を書き出し中")
        case .cancelling:
            return L10n.text("中断しています")
        case .completed:
            return L10n.text("書き出し完了")
        }
    }

    var detail: String {
        switch self {
        case .locatingAssets:
            return L10n.text("写真ライブラリから結合対象をまとめて読み込んでいます。")
        case .preparing:
            return L10n.text("動画とスタンプ設定を確認しています。")
        case .resolvingStamps:
            return L10n.text("必要な地名と、動画ごとの表示設定を確認しています。")
        case .exportingClip:
            return L10n.text("タイムスタンプを反映して仕上げています。")
        case .merging:
            return L10n.text("古い動画から順番に、1本の動画へまとめています。")
        case .processingChunk(let current, let total):
            return L10n.text("安定して処理するため、%d本ずつまとめています。現在 %d/%d 分割目です。", DayVideoExportPolicy.chunkSize, current, total)
        case .combiningChunks:
            return L10n.text("作成した分割動画を、古い順のまま1本へまとめています。")
        case .finalizing:
            return L10n.text("共有できる動画ファイルを仕上げています。")
        case .cancelling:
            return L10n.text("安全に処理を止めています。")
        case .completed:
            return L10n.text("共有画面を開きます。")
        }
    }
}

/// 利用者に見せる3つの段階。内部の細かい段階（分割処理など）はここにまとめて、作る側の言葉は出さない。
enum DayVideoExportStage: Int, CaseIterable, Sendable {
    case preparing
    case joining
    case finishing

    var title: String {
        switch self {
        case .preparing: return L10n.text("準備")
        case .joining: return L10n.text("つなぐ")
        case .finishing: return L10n.text("仕上げ")
        }
    }
}

extension DayVideoExportPhase {
    var stage: DayVideoExportStage {
        switch self {
        case .locatingAssets, .preparing, .resolvingStamps:
            return .preparing
        case .exportingClip, .merging, .processingChunk, .combiningChunks:
            return .joining
        case .finalizing, .completed:
            return .finishing
        case .cancelling:
            return .joining
        }
    }
}

struct DayVideoExportProgress: Equatable, Sendable {
    let fraction: Double
    let phase: DayVideoExportPhase

    init(fraction: Double, phase: DayVideoExportPhase) {
        self.fraction = min(max(fraction, 0), 1)
        self.phase = phase
    }

    var percentage: Int {
        Int((fraction * 100).rounded())
    }
}

enum DayVideoExporterError: LocalizedError {
    case noAssets
    case assetCountMismatch(expected: Int, actual: Int)
    case missingVideoTrack
    case exportFailed(String)
    case photoKitUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAssets:
            return L10n.text("結合する動画がありません。")
        case .assetCountMismatch(let expected, let actual):
            return L10n.text("結合対象の動画が不足しています（予定%d本／取得%d本）。", expected, actual)
        case .missingVideoTrack:
            return L10n.text("動画トラックを読み込めませんでした。")
        case .exportFailed(let message):
            return message.isEmpty ? L10n.text("動画の書き出しに失敗しました。") : message
        case .photoKitUnavailable:
            return L10n.text("フォトライブラリから動画を読み込めませんでした。")
        case .cancelled:
            return L10n.text("動画の結合を中断しました。")
        }
    }
}

final class DayVideoExporter {
    private let temporaryFileStore: TemporaryFileStore
    private let mediaExporter: MediaExporter
    private let compositionBuilder = DayVideoCompositionBuilder()

    init(
        temporaryFileStore: TemporaryFileStore = TemporaryFileStore(),
        mediaExporter: MediaExporter? = nil
    ) {
        self.temporaryFileStore = temporaryFileStore
        self.mediaExporter = mediaExporter ?? MediaExporter(temporaryFileStore: temporaryFileStore)
    }

    func exportMergedVideo(
        for assets: [PHAsset],
        captureDates: [Date]? = nil,
        stampContexts: [VideoPostProcessContext?] = [],
        textOverlaysByClip: [[VlogResolvedTextOverlay]] = [],
        dayKey: String,
        storageMode: VideoStorageMode,
        addsEndMark: Bool = false,
        progress: @escaping @Sendable (DayVideoExportProgress) -> Void = { _ in }
    ) async throws -> URL {
        guard !assets.isEmpty else {
            throw DayVideoExporterError.noAssets
        }

        let orderingDates: [Date?] = if let captureDates,
                                         captureDates.count == assets.count {
            captureDates.map(Optional.some)
        } else {
            assets.map(\.creationDate)
        }
        let order = DayVideoExportPolicy.orderedIndices(
            creationDates: orderingDates,
            identifiers: assets.map(\.localIdentifier)
        )
        let sortedAssets = order.map { assets[$0] }
        let normalizedStampContexts = stampContexts.count == assets.count
            ? stampContexts
            : Array(repeating: nil, count: assets.count)
        let sortedStampContexts = order.map { normalizedStampContexts[$0] }
        let normalizedTextOverlays = textOverlaysByClip.count == assets.count
            ? textOverlaysByClip
            : Array(repeating: [], count: assets.count)
        let sortedTextOverlays = order.map { normalizedTextOverlays[$0] }
        // 途中で容量が尽きて失敗するより、始める前に止める。
        try ensureFreeSpace(
            required: DayVideoExportPolicy.estimatedRequiredBytes(
                totalDuration: sortedAssets.reduce(0.0) { $0 + $1.duration },
                clipCount: sortedAssets.count,
                storageMode: storageMode
            )
        )
        let progressReporter = DayVideoExportProgressReporter(callback: progress)
        progressReporter.report(0, phase: .preparing)
        AppLog.export.info("day_export.begin day=\(dayKey, privacy: .private) clips=\(sortedAssets.count, privacy: .public) compact=\(storageMode == .compact, privacy: .public)")
        do {
            let destinationURL: URL
            if sortedAssets.count >= DayVideoExportPolicy.heavyClipCount {
                destinationURL = try await exportInChunks(
                    sortedAssets,
                    stampContexts: sortedStampContexts,
                    textOverlaysByClip: sortedTextOverlays,
                    dayKey: dayKey,
                    storageMode: storageMode,
                    addsEndMark: addsEndMark,
                    progress: { value, phase in
                        progressReporter.report(value, phase: phase)
                    }
                )
            } else {
                let phase: DayVideoExportPhase = sortedAssets.count == 1
                    ? .exportingClip
                    : .merging
                destinationURL = try await exportAssets(
                    sortedAssets,
                    stampContexts: sortedStampContexts,
                    textOverlaysByClip: sortedTextOverlays,
                    outputPrefix: "export-\(dayKey)",
                    storageMode: storageMode,
                    addsEndMark: addsEndMark,
                    progress: { progressReporter.report($0, phase: phase) }
                )
            }
            progressReporter.report(1, phase: .completed)
            AppLog.export.info("day_export.success day=\(dayKey, privacy: .private) url=\(destinationURL.lastPathComponent, privacy: .private(mask: .hash))")
            return destinationURL
        } catch is CancellationError {
            AppLog.export.notice("day_export.cancelled day=\(dayKey, privacy: .private)")
            throw DayVideoExporterError.cancelled
        } catch {
            let message = error.localizedDescription
            AppLog.export.error("day_export.fail day=\(dayKey, privacy: .private) reason=\(message, privacy: .private)")
            // 容量不足、PhotoKit、出力非対応などを上位で正しく分類できるよう、
            // 元のエラー型を失わずに返す。
            throw error
        }
    }

    private func exportInChunks(
        _ assets: [PHAsset],
        stampContexts: [VideoPostProcessContext?],
        textOverlaysByClip: [[VlogResolvedTextOverlay]],
        dayKey: String,
        storageMode: VideoStorageMode,
        addsEndMark: Bool,
        progress: @escaping @Sendable (Double, DayVideoExportPhase) -> Void
    ) async throws -> URL {
        let chunkRanges = DayVideoExportPolicy.chunkRanges(for: assets.count)
        var intermediateURLs: [URL] = []
        defer {
            intermediateURLs.forEach(temporaryFileStore.removeIfExists)
        }

        AppLog.export.info(
            "day_export.chunked chunks=\(chunkRanges.count, privacy: .public) size=\(DayVideoExportPolicy.chunkSize, privacy: .public)"
        )
        for (index, range) in chunkRanges.enumerated() {
            try Task.checkCancellation()
            let url = try await exportAssets(
                Array(assets[range]),
                stampContexts: Array(stampContexts[range]),
                textOverlaysByClip: Array(textOverlaysByClip[range]),
                outputPrefix: "export-\(dayKey)-part-\(index + 1)",
                storageMode: storageMode,
                // ロゴは動画全体の最後に出すので、最後の分割にだけ入れる。
                addsEndMark: addsEndMark && index == chunkRanges.count - 1,
                progress: { chunkProgress in
                    let completed = Double(index) + chunkProgress
                    progress(
                        (completed / Double(chunkRanges.count)) * 0.8,
                        .processingChunk(current: index + 1, total: chunkRanges.count)
                    )
                }
            )
            intermediateURLs.append(url)
        }

        // 分割ファイルの形が揃っていれば、再エンコードせずにつなぐ（速く、画質も落ちない）。
        progress(0.8, .combiningChunks)
        if let joined = try await joinWithoutReencoding(
            intermediateURLs,
            outputPrefix: "export-\(dayKey)",
            progress: { progress(0.8 + ($0 * 0.2), .finalizing) }
        ) {
            return joined
        }

        let built = try await compositionBuilder.build(
            sourceCount: intermediateURLs.count,
            storageMode: storageMode,
            progress: { progress(0.8 + ($0 * 0.05), .combiningChunks) }
        ) { index in
            AVURLAsset(url: intermediateURLs[index])
        }
        let encodingPolicy = VideoEncodingPolicy(storageMode: storageMode)
        return try await mediaExporter.export(
            asset: built.composition,
            videoComposition: built.videoComposition,
            encodingPolicy: encodingPolicy,
            outputPrefix: "export-\(dayKey)",
            backgroundTaskName: "DayVideoExportFinal",
            requiresAudioTrack: built.containsAudio,
            progress: { progress(0.85 + ($0 * 0.15), .finalizing) }
        )
    }

    private func exportAssets(
        _ assets: [PHAsset],
        stampContexts: [VideoPostProcessContext?],
        textOverlaysByClip: [[VlogResolvedTextOverlay]],
        outputPrefix: String,
        storageMode: VideoStorageMode,
        addsEndMark: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let built = try await compositionBuilder.build(
            sourceCount: assets.count,
            storageMode: storageMode,
            stampContexts: stampContexts,
            textOverlaysByClip: textOverlaysByClip,
            addsEndMark: addsEndMark,
            progress: { progress($0 * 0.35) }
        ) { [self] index in
            try await requestAVAsset(
                for: assets[index],
                progress: { assetProgress in
                    let completedSources = Double(index) + assetProgress
                    progress(
                        (completedSources / Double(max(assets.count, 1))) * 0.35
                    )
                }
            )
        }
        return try await mediaExporter.export(
            asset: built.composition,
            videoComposition: built.videoComposition,
            encodingPolicy: VideoEncodingPolicy(storageMode: storageMode),
            outputPrefix: outputPrefix,
            backgroundTaskName: "DayVideoExport",
            requiresAudioTrack: built.containsAudio,
            progress: { progress(0.35 + ($0 * 0.65)) }
        )
    }

    /// 分割ファイルが全部同じ大きさ・向きなら、そのままつないで書き出す。
    /// 揃っていない時や失敗した時は nil を返し、呼び出し側が従来どおり書き出し直す。
    private func joinWithoutReencoding(
        _ urls: [URL],
        outputPrefix: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL? {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var expectedSize: CGSize?
        var cursor: CMTime = .zero
        var containsAudio = false

        for url in urls {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            let assetDuration = try await asset.load(.duration)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            let (naturalSize, transform, trackRange) = try await sourceVideo.load(
                .naturalSize,
                .preferredTransform,
                .timeRange
            )
            guard transform.isIdentity,
                  expectedSize == nil || expectedSize == naturalSize,
                  let videoRange = MediaTrackTiming.usableVideoRange(
                    assetDuration: assetDuration,
                    trackRange: trackRange
                  ) else {
                return nil
            }
            expectedSize = naturalSize
            try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: cursor)

            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
               let audioTrack,
               let insertion = MediaTrackTiming.audioInsertion(
                audioRange: try await sourceAudio.load(.timeRange),
                videoRange: videoRange,
                destinationCursor: cursor
               ) {
                try audioTrack.insertTimeRange(
                    insertion.sourceRange,
                    of: sourceAudio,
                    at: insertion.destinationStart
                )
                containsAudio = true
            }
            cursor = CMTimeAdd(cursor, videoRange.duration)
        }
        if !containsAudio, let audioTrack {
            composition.removeTrack(audioTrack)
        }

        do {
            let url = try await mediaExporter.export(
                asset: composition,
                videoComposition: nil,
                encodingPolicy: VideoEncodingPolicy(storageMode: .standard, purpose: .passthrough),
                outputPrefix: outputPrefix,
                backgroundTaskName: "DayVideoExportJoin",
                requiresAudioTrack: containsAudio,
                progress: progress
            )
            AppLog.export.info("day_export.joined_without_reencode parts=\(urls.count, privacy: .public)")
            return url
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.export.warning(
                "day_export.join_passthrough.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    private func ensureFreeSpace(required: Int64) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let available = (try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ))?.volumeAvailableCapacityForImportantUsage else {
            return
        }
        guard available >= required else {
            AppLog.export.error(
                "day_export.insufficient_space required_mb=\(required / 1_000_000, privacy: .public) available_mb=\(available / 1_000_000, privacy: .public)"
            )
            // 既存の「容量が足りません」の案内に乗せる。
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        }
    }

    private func requestAVAsset(
        for asset: PHAsset,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AVAsset {
        try Task.checkCancellation()
        let request = PhotoKitVideoAssetRequest(asset: asset, progress: progress)
        return try await withTaskCancellationHandler {
            try await request.value()
        } onCancel: {
            request.cancel()
        }
    }

    func discardExport(at url: URL) {
        temporaryFileStore.removeIfExists(at: url)
    }

}

private final class DayVideoExportProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let callback: @Sendable (DayVideoExportProgress) -> Void
    private var latest = 0.0

    init(callback: @escaping @Sendable (DayVideoExportProgress) -> Void) {
        self.callback = callback
    }

    func report(_ value: Double, phase: DayVideoExportPhase) {
        let normalized = min(max(value, 0), 1)
        let next = lock.withLock { () -> Double in
            latest = max(latest, normalized)
            return latest
        }
        callback(DayVideoExportProgress(fraction: next, phase: phase))
    }
}

private final class PhotoKitVideoAssetRequest: @unchecked Sendable {
    private let asset: PHAsset
    private let manager = PHImageManager.default()
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var continuation: CheckedContinuation<AVAsset, Error>?
    private var isFinished = false

    init(
        asset: PHAsset,
        progress: @escaping @Sendable (Double) -> Void
    ) {
        self.asset = asset
        self.progress = progress
    }

    func value() async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isFinished {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()

            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .original
            options.progressHandler = { [progress] value, _, _, _ in
                progress(value)
            }
            let requestID = manager.requestAVAsset(
                forVideo: asset,
                options: options
            ) { [weak self] avAsset, _, info in
                guard let self else { return }
                if let error = info?[PHImageErrorKey] as? Error {
                    self.finish(.failure(error))
                } else if let avAsset {
                    self.finish(.success(avAsset))
                } else {
                    self.finish(.failure(DayVideoExporterError.photoKitUnavailable))
                }
            }

            lock.lock()
            self.requestID = requestID
            let shouldCancel = isFinished
            lock.unlock()
            if shouldCancel {
                manager.cancelImageRequest(requestID)
            }
        }
    }

    func cancel() {
        let state: (CheckedContinuation<AVAsset, Error>?, PHImageRequestID?)
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        state = (continuation, requestID)
        continuation = nil
        lock.unlock()

        if let requestID = state.1 {
            manager.cancelImageRequest(requestID)
        }
        state.0?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<AVAsset, Error>) {
        let continuation: CheckedContinuation<AVAsset, Error>?
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
