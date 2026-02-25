import SwiftUI
import UIKit
import Photos
import AVFoundation
import MobileCoreServices

struct ShareDayView: View {
    let assets: [PHAsset]
    @State private var exportURL: URL? = nil
    @State private var progress: Double = 0.0
    @State private var exportStatusText: String = "準備中..."
    @AppStorage("dateStampFormat") private var dateStampFormat: String = DateStampFormatter.compactDateTime
    @AppStorage("dateStampZeroPadded") private var dateStampZeroPadded: Bool = false
    @AppStorage("dateStampSize") private var dateStampSize: String = DateStampStyle.medium

    var body: some View {
        Group {
            if let url = exportURL {
                ActivityViewController(activityItems: [url])
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 8)
                            .frame(width: 96, height: 96)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color(hex: 0xFFC857), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 96, height: 96)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(exportStatusText)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
            }
        }
        .onAppear {
            exportDayCompilation(
                assets: assets,
                format: dateStampFormat,
                zeroPadded: dateStampZeroPadded,
                sizeKey: dateStampSize,
                onProgress: { p in
                    DispatchQueue.main.async {
                        self.progress = max(0, min(1, p))
                        if p < 0.1 { self.exportStatusText = "素材を読み込み中..." }
                        else if p < 0.6 { self.exportStatusText = "動画を結合中..." }
                        else if p < 1.0 { self.exportStatusText = "書き出し中..." }
                        else { self.exportStatusText = "完了" }
                    }
                }
            ) { url in
                DispatchQueue.main.async {
                    self.exportURL = url
                    self.progress = (url == nil) ? 0 : 1
                    if url == nil { self.exportStatusText = "書き出しに失敗しました" }
                }
            }
        }
    }
}

private func exportDayCompilation(
    assets: [PHAsset],
    format: String,
    zeroPadded: Bool,
    sizeKey: String,
    onProgress: @escaping (Double) -> Void,
    completion: @escaping (URL?) -> Void
) {
    onProgress(0.02)
    // Fetch AVAssets for all PHAssets
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    let manager = PHImageManager.default()
    let collectQueue = DispatchQueue(label: "ShareDayView.AssetCollect")
    var orderedAssets: [AVAsset?] = Array(repeating: nil, count: assets.count)
    let group = DispatchGroup()
    let totalCount = max(1, assets.count)
    for (index, asset) in assets.enumerated() {
        group.enter()
        manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            if let avAsset = avAsset {
                collectQueue.sync {
                    orderedAssets[index] = avAsset
                }
            }
            onProgress(0.05 + (Double(index + 1) / Double(totalCount)) * 0.15)
            group.leave()
        }
    }
    group.notify(queue: .global(qos: .userInitiated)) {
        let avAssets = collectQueue.sync { orderedAssets.compactMap { $0 } }
        guard !avAssets.isEmpty else { completion(nil); return }
        onProgress(0.25)
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { completion(nil); return }
        let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var renderSize = CGSize(width: 1080, height: 1920)

        Task {
            do {
                    // Pre-read first asset orientation to decide renderSize
                    if let first = avAssets.first, let firstTrack = try await first.loadTracks(withMediaType: .video).first {
                        let firstSize = try await firstTrack.load(.naturalSize)
                        let firstTF = try await firstTrack.load(.preferredTransform)
                        let firstRect = CGRect(origin: .zero, size: firstSize).applying(firstTF)
                        let rw = abs(firstRect.width), rh = abs(firstRect.height)
                        renderSize = CGSize(width: rw, height: rh)
                    }

                    // Build a single layerInstruction for the compTrack and set per-segment transforms
                    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)

                    for (i, asset) in avAssets.enumerated() {
                        if let vTrack = try await asset.loadTracks(withMediaType: .video).first {
                            let duration = try await asset.load(.duration)
                            try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vTrack, at: cursor)
                            // insert audio if available
                            if let aTrack = try await asset.loadTracks(withMediaType: .audio).first, let compA = compAudioTrack {
                                try? compA.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: aTrack, at: cursor)
                            }

                            let nat = try await vTrack.load(.naturalSize)
                            let pt = try await vTrack.load(.preferredTransform)
                            // Compute rotated rect
                            let rect = CGRect(origin: .zero, size: nat).applying(pt)
                            let rw = abs(rect.width), rh = abs(rect.height)
                            let scale = min(renderSize.width / rw, renderSize.height / rh)
                            // Build transform: rotate, translate to origin, scale, then center in render
                            var t = pt
                            t = t.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                            t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                            let tx = (renderSize.width - rw * scale) / 2
                            let ty = (renderSize.height - rh * scale) / 2
                            t = t.concatenating(CGAffineTransform(translationX: tx, y: ty))
                            layerInstruction.setTransform(t, at: cursor)

                            cursor = CMTimeAdd(cursor, duration)
                            onProgress(0.25 + (Double(i + 1) / Double(max(1, avAssets.count))) * 0.25)
                        }
                    }

                    let videoComposition = AVMutableVideoComposition()
                    videoComposition.renderSize = renderSize
                    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
                    let mainInstruction = AVMutableVideoCompositionInstruction()
                    mainInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
                    mainInstruction.layerInstructions = [layerInstruction]
                    videoComposition.instructions = [mainInstruction]

                    // Date overlay at start (top-right)
                    let videoLayer = CALayer(); videoLayer.frame = CGRect(origin: .zero, size: renderSize)
                    let overlayLayer = CALayer(); overlayLayer.frame = videoLayer.frame
                    let textLayer = CATextLayer()
                    // Use the day's date (earliest asset) for the overlay
                    let overlayDate: Date = (assets.compactMap { $0.creationDate }.sorted().first) ?? Date()
                    textLayer.string = DateStampFormatter.string(
                        from: overlayDate,
                        storedFormat: format,
                        zeroPadded: zeroPadded
                    )
                    textLayer.alignmentMode = .right
                    textLayer.font = "Menlo-Bold" as CFTypeRef
                    textLayer.fontSize = DateStampStyle.fontSize(for: renderSize, sizeKey: sizeKey)
                    textLayer.foregroundColor = UIColor.white.cgColor
                    textLayer.backgroundColor = UIColor.clear.cgColor
                    textLayer.shadowOpacity = 0.6
                    textLayer.shadowRadius = 2
                    textLayer.shadowOffset = CGSize(width: 0, height: 1)
                    let scale = await MainActor.run { UIScreen.main.scale }
                    textLayer.contentsScale = scale
                    let topMargin = DateStampStyle.topMargin(for: renderSize)
                    let rightMargin = DateStampStyle.rightMargin(for: renderSize)
                    textLayer.frame = CGRect(
                        x: 0,
                        y: topMargin,
                        width: renderSize.width - rightMargin,
                        height: DateStampStyle.textHeight(for: renderSize, sizeKey: sizeKey)
                    )
                    overlayLayer.addSublayer(textLayer)
                    let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: renderSize)
                    parentLayer.addSublayer(videoLayer)
                    parentLayer.addSublayer(overlayLayer)
                    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 1.0; fade.toValue = 0.0
                    fade.beginTime = AVCoreAnimationBeginTimeAtZero + 2.0
                    fade.duration = 0.5
                    fade.fillMode = .forwards
                    fade.isRemovedOnCompletion = false
                    textLayer.add(fade, forKey: "fade")

                    func runExport() async throws -> URL {
                        let outBase = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                            throw NSError(domain: "ShareDayView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create exporter"])
                        }
                        exporter.videoComposition = videoComposition
                        let fileType: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
                        let outURL = outBase.appendingPathExtension(fileType == .mp4 ? "mp4" : "mov")
                        let taskID = await MainActor.run {
                            UIApplication.shared.beginBackgroundTask(withName: "DayExport", expirationHandler: nil)
                        }
                        let progressTask = Task {
                            while !Task.isCancelled {
                                let p = 0.55 + Double(exporter.progress) * 0.42
                                onProgress(min(0.98, max(0.55, p)))
                                try? await Task.sleep(for: .milliseconds(150))
                            }
                        }
                        let timeoutTask = Task { try? await Task.sleep(for: .seconds(120)); exporter.cancelExport() }
                        defer {
                            progressTask.cancel()
                            timeoutTask.cancel()
                        }
                        try await exporter.export(to: outURL, as: fileType)
                        await MainActor.run { UIApplication.shared.endBackgroundTask(taskID) }
                        return outURL
                    }

                    do {
                        let url = try await runExport()
                        onProgress(1.0)
                        completion(url)
                    } catch {
                        AppLog.export.error("First export attempt failed: \(error.localizedDescription)")
                        do {
                            let url = try await runExport()
                            onProgress(1.0)
                            completion(url)
                        } catch {
                            AppLog.export.error("Retry export failed: \(error.localizedDescription)")
                            completion(nil)
                        }
                    }
                } catch {
                    completion(nil)
                }
            }
        }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
