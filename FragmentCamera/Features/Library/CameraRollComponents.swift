import SwiftUI
import UIKit

struct CameraRollLoadingView: View {
    var body: some View {
        ProgressView()
            .tint(RollTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 72)
            .accessibilityLabel("読み込み中")
    }
}

/// 書き出し（1本に結合）の進み具合。その日のクリップを帯に並べ、つないだ所まで黒い線が進む。
/// 段階は「準備・つなぐ・仕上げ」の3つだけ見せる。
struct CameraRollExportProgressPanel: View {
    let progress: DayVideoExportProgress
    let subject: CameraRollExportSubject?
    let thumbnailProvider: LibraryThumbnailProviding
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCancelling: Bool {
        progress.phase == .cancelling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    if let subject {
                        Text(verbatim: "\(subject.title) · \(CameraRollStampFormat.clips(subject.clipCount))")
                            .rollMono(10, .semibold)
                            .tracking(1.2)
                            .foregroundStyle(RollTheme.secondary)
                            .lineLimit(1)
                    }
                    Text(isCancelling ? L10n.text("やめています") : L10n.text("1本にしています"))
                        .rollText(16, .bold)
                        .foregroundStyle(RollTheme.ink)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: "\(progress.percentage)")
                        .rollMono(30, .medium, maxScale: 1.3)
                        .contentTransition(.numericText())
                    Text(verbatim: "%")
                        .rollMono(14, maxScale: 1.3)
                        .foregroundStyle(RollTheme.secondary)
                }
                .foregroundStyle(RollTheme.ink)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress.percentage)
            }

            if let subject, !subject.previewClipIDs.isEmpty {
                ExportClipStrip(
                    clipIDs: subject.previewClipIDs,
                    fraction: progress.fraction,
                    thumbnailProvider: thumbnailProvider
                )
                .frame(height: 54)
            } else {
                ProgressView(value: progress.fraction, total: 1)
                    .tint(RollTheme.ink)
            }

            HStack(spacing: 14) {
                ForEach(DayVideoExportStage.allCases, id: \.self) { stage in
                    stageLabel(stage)
                }
                Spacer(minLength: 8)
                Button(isCancelling ? L10n.text("中断中") : L10n.text("やめる"), action: onCancel)
                    .rollText(13)
                    .underline(!isCancelling)
                    .foregroundStyle(RollTheme.secondary)
                    .disabled(isCancelling)
                    .accessibilityIdentifier("library.export.cancel")
            }

            Text(L10n.text("アプリを開いたままにしてください。本数が多い日は少し時間がかかります。"))
                .rollText(11)
                .foregroundStyle(RollTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RollTheme.rowLine, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("%@、%dパーセント。%@", progress.phase.title, progress.percentage, progress.phase.stage.title))
        .accessibilityIdentifier("library.export.progress")
    }

    private func stageLabel(_ stage: DayVideoExportStage) -> some View {
        let current = progress.phase.stage
        let isDone = stage.rawValue < current.rawValue
        let isNow = stage == current
        return HStack(spacing: 6) {
            Circle()
                .fill(isDone || isNow ? RollTheme.ink : Color.clear)
                .overlay { Circle().strokeBorder(isDone || isNow ? Color.clear : RollTheme.dashed, lineWidth: 1) }
                .frame(width: 7, height: 7)
                .padding(isNow ? 3 : 0)
                .background { if isNow { Circle().fill(RollTheme.fill) } }
            Text(stage.title)
                .rollText(12, isNow ? .bold : .regular)
                .foregroundStyle(isDone || isNow ? RollTheme.ink : RollTheme.dashed)
        }
        .accessibilityHidden(true)
    }
}

/// 書き出し中のクリップの帯。つないだ所まで黒い線が進み、その先は薄く見せる。
private struct ExportClipStrip: View {
    let clipIDs: [String]
    let fraction: Double
    let thumbnailProvider: LibraryThumbnailProviding

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let count = CGFloat(max(clipIDs.count, 1))
            let width = max((proxy.size.width - gap * (count - 1)) / count, 1)
            let progressX = proxy.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(Array(clipIDs.enumerated()), id: \.offset) { _, id in
                        CameraRollFrame(
                            assetIdentifier: id,
                            size: CGSize(width: width, height: proxy.size.height),
                            cornerRadius: 5,
                            thumbnailProvider: thumbnailProvider
                        )
                    }
                }
                // まだつないでいない部分は薄くする。
                RollTheme.ground
                    .opacity(0.72)
                    .frame(width: max(proxy.size.width - progressX, 0))
                    .offset(x: progressX)
                Capsule()
                    .fill(RollTheme.ink)
                    .frame(width: 2, height: proxy.size.height + 8)
                    .offset(x: progressX - 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// 書き出しが終わった時のカード。「できた」を見せてから、共有・保存へ進む。
struct CameraRollExportCompletionCard: View {
    let completion: CameraRollExportCompletion
    let thumbnailProvider: LibraryThumbnailProviding
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let firstID = completion.subject.previewClipIDs.first {
                        CameraRollFrame(
                            assetIdentifier: firstID,
                            size: CGSize(width: 64, height: 112),
                            cornerRadius: 10,
                            thumbnailProvider: thumbnailProvider
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(RollTheme.placeholder)
                            .frame(width: 64, height: 112)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "DONE")
                        .rollMono(10, .semibold)
                        .tracking(1.2)
                        .foregroundStyle(RollTheme.secondary)
                    Text(L10n.text("%@ が1本になりました", completion.subject.title))
                        .rollText(17, .bold)
                        .foregroundStyle(RollTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(CameraRollStampFormat.clips(completion.subject.clipCount)) · \(completion.subject.durationText)")
                        .rollMono(12)
                        .foregroundStyle(RollTheme.secondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onShare) {
                    Label(L10n.text("共有・保存"), systemImage: "square.and.arrow.up")
                        .rollText(14, .bold)
                        .foregroundStyle(RollTheme.ground)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RollTheme.ink, in: Capsule())
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityIdentifier("library.export.share")

                Button(action: onDismiss) {
                    Text(L10n.text("閉じる"))
                        .rollText(14)
                        .foregroundStyle(RollTheme.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .overlay { Capsule().strokeBorder(RollTheme.hairline, lineWidth: 1) }
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityIdentifier("library.export.dismiss")
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RollTheme.rowLine, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .sensoryFeedback(.success, trigger: completion.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.export.completion")
    }
}

struct CameraRollEmptyView: View {
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            CameraRollTimeRuler(fractions: [], nowFraction: nil, showsLabels: true)
                .frame(width: 220)

            Text("まだ動画はありません")
                .rollText(17, .semibold)
                .foregroundStyle(RollTheme.ink)

            Button(action: onCapture) {
                Label("撮る", systemImage: "plus")
                    .rollText(14, .semibold)
                    .foregroundStyle(RollTheme.ground)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(RollTheme.ink, in: Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityIdentifier("library.empty.capture")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

// MARK: - Time axis parts

/// 0時→24時の一本線。撮った時刻に印、今日なら「いま」の点を置く。
struct CameraRollTimeRuler: View {
    let fractions: [Double]
    let nowFraction: Double?
    var tickHeight: CGFloat = 12
    var tickWidth: CGFloat = 2
    var showsLabels: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(height: tickHeight)

            if showsLabels {
                HStack(spacing: 0) {
                    ForEach(["0", "6", "12", "18", "24"], id: \.self) { label in
                        Text(label)
                        if label != "24" { Spacer(minLength: 0) }
                    }
                }
                .rollMono(9)
                .foregroundStyle(RollTheme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let midY = size.height / 2
        let width = size.width
        let solidEnd = width * CGFloat(nowFraction ?? 1)

        // 過ぎた時間は実線、これからの時間は点線。
        var solid = Path()
        solid.move(to: CGPoint(x: 0, y: midY))
        solid.addLine(to: CGPoint(x: solidEnd, y: midY))
        context.stroke(solid, with: .color(nowFraction == nil ? RollTheme.hairline : RollTheme.ink), lineWidth: 1)

        if nowFraction != nil, solidEnd < width {
            var rest = Path()
            rest.move(to: CGPoint(x: solidEnd, y: midY))
            rest.addLine(to: CGPoint(x: width, y: midY))
            context.stroke(rest, with: .color(RollTheme.dashed), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        for fraction in fractions {
            let x = min(max(width * CGFloat(fraction), tickWidth / 2), width - tickWidth / 2)
            let rect = CGRect(x: x - tickWidth / 2, y: 0, width: tickWidth, height: size.height)
            context.fill(Path(rect), with: .color(RollTheme.ink))
        }

        if let nowFraction {
            let diameter = min(9, size.height)
            let x = width * CGFloat(nowFraction)
            let dot = CGRect(x: x - diameter / 2, y: midY - diameter / 2, width: diameter, height: diameter)
            context.fill(Path(ellipseIn: dot), with: .color(RollTheme.accent))
        }
    }

    private var accessibilityText: String {
        fractions.isEmpty
            ? L10n.text("記録なし")
            : L10n.text("%d回撮影", fractions.count)
    }
}

/// 横向きの点線。
struct CameraRollDashedLine: View {
    var color: Color = RollTheme.dashed
    var vertical: Bool = false

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                if vertical {
                    path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
        .accessibilityHidden(true)
    }
}

/// 縦長のコマ。サムネイルが読めない間は無地。
struct CameraRollFrame: View {
    let assetIdentifier: String
    let size: CGSize
    var cornerRadius: CGFloat = 8
    let thumbnailProvider: LibraryThumbnailProviding

    var body: some View {
        LibraryThumbnailView(
            assetIdentifier: assetIdentifier,
            thumbnailProvider: thumbnailProvider,
            targetSize: size
        ) {
            RollTheme.placeholder
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .id(assetIdentifier)
    }
}

/// 黒い丸ボタン（共有・書き出し）。書き出し中は進捗リングとキャンセル。
struct CameraRollExportButton: View {
    let isExporting: Bool
    let progress: Double?
    let isEnabled: Bool
    let onExport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Button(action: isExporting ? onCancel : onExport) {
            ZStack {
                Circle().stroke(RollTheme.hairline, lineWidth: 1)
                if isExporting {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(progress ?? 0, 0), 1)))
                        .stroke(RollTheme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .offset(y: -1)
                }
            }
            .foregroundStyle(RollTheme.ink)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(!isEnabled && !isExporting)
        .opacity((isEnabled || isExporting) ? 1 : 0.3)
        .accessibilityLabel(isExporting ? L10n.text("結合をキャンセル") : L10n.text("1本に結合して共有"))
        .accessibilityIdentifier("library.day.export")
    }
}
