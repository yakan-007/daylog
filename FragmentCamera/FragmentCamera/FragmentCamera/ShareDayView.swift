import SwiftUI
import UIKit
import Photos
import AVFoundation
import MobileCoreServices

struct ShareDayView: View {
    let assets: [PHAsset]
    @State private var exportURL: URL? = nil
    @State private var exporting = true
    @State private var progress: Double = 0.0
    @AppStorage("dateStampFormat") private var dateStampFormat: String = "yy.MM.dd"

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
                    Text("書き出し中...")
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
            }
        }
        .onAppear { exportDayCompilation(assets: assets, format: dateStampFormat) { url in
            self.exportURL = url
            self.exporting = false
        } }
    }
}

private func exportDayCompilation(assets: [PHAsset], format: String, completion: @escaping (URL?) -> Void) {
    // Fetch AVAssets for all PHAssets
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    let manager = PHImageManager.default()
    var avAssets: [AVAsset] = []
    let group = DispatchGroup()
    for asset in assets {
        group.enter()
        manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            if let avAsset = avAsset { avAssets.append(avAsset) }
            group.leave()
        }
    }
    group.notify(queue: .global(qos: .userInitiated)) {
        guard !avAssets.isEmpty else { completion(nil); return }
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

                    for asset in avAssets {
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
                    let df = DateFormatter(); df.dateFormat = format
                    textLayer.string = df.string(from: overlayDate)
                    textLayer.alignmentMode = .right
                    textLayer.font = "Menlo-Bold" as CFTypeRef
                    textLayer.fontSize = renderSize.height * 0.055
                    textLayer.foregroundColor = UIColor.white.cgColor
                    textLayer.backgroundColor = UIColor.clear.cgColor
                    textLayer.shadowOpacity = 0.6
                    textLayer.shadowRadius = 2
                    textLayer.shadowOffset = CGSize(width: 0, height: 1)
                    let scale = await MainActor.run { UIScreen.main.scale }
                    textLayer.contentsScale = scale
                    let topMargin = renderSize.height * 0.04
                    let rightMargin = renderSize.width * 0.05
                    textLayer.frame = CGRect(x: 0, y: topMargin, width: renderSize.width - rightMargin, height: renderSize.height * 0.1)
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

                    let outBase = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { completion(nil); return }
                    exporter.videoComposition = videoComposition
                    let fileType: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
                    let outURL = outBase.appendingPathExtension(fileType == .mp4 ? "mp4" : "mov")
                    // Background task to avoid suspension during export
                    let taskID = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "DayExport", expirationHandler: nil) }
                    try await exporter.export(to: outURL, as: fileType)
                    await MainActor.run { UIApplication.shared.endBackgroundTask(taskID) }
                    completion(outURL)
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
