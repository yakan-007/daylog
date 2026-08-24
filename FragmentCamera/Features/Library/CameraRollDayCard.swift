import SwiftUI

struct CameraRollDayCard: View {
    let item: CameraRollDayItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onOpen: () -> Void
    let onClipTap: (String) -> Void
    let onPlay: () -> Void
    let onExport: () -> Void
    let onCancelExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let text = item.exportAssessment.indicatorText {
                exportLoadIndicator(text)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            CameraRollDayHero(
                item: item,
                thumbnailProvider: thumbnailProvider,
                onPlay: onPlay
            )

            if item.clips.count > 1 {
                clipStrip
            }
        }
        .background(DaylogModernTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DaylogModernTheme.mediaRadius, style: .continuous)
                .stroke(DaylogModernTheme.divider, lineWidth: 1)
        }
        .padding(.horizontal, 10)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(item.dateText)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.weekdayText)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DaylogModernTheme.secondary)
                    }

                    Text("\(item.summaryText) · \(item.durationText)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DaylogModernTheme.secondary)
                }
                .foregroundStyle(DaylogModernTheme.foreground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("%@、%@、%@", item.dateText, item.summaryText, item.durationText))
            .accessibilityHint("この日の動画一覧を開きます")
            .accessibilityIdentifier("library.day.details")

            Spacer()

            if item.isExporting {
                Button(action: onCancelExport) {
                    ZStack {
                        Circle().stroke(DaylogModernTheme.divider, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: item.exportProgress ?? 0)
                            .stroke(DaylogModernTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(width: 27, height: 27)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel("結合をキャンセル")
                .accessibilityIdentifier("library.day.export")
            } else {
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DaylogModernTheme.foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(!item.canExport)
                .opacity(item.canExport ? 1 : 0.28)
                .accessibilityLabel("1本に結合して共有")
                .accessibilityIdentifier("library.day.export")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var clipStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 9) {
                ForEach(Array(item.clips.prefix(3))) { clip in
                    Button {
                        onClipTap(clip.id)
                    } label: {
                        VStack(spacing: 5) {
                            CameraRollHeroThumbnail(
                                item: clip,
                                thumbnailProvider: thumbnailProvider,
                                targetSize: CGSize(width: 64, height: 64)
                            )
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                            Text(clip.timeText)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(DaylogModernTheme.secondary)
                        }
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(L10n.text("%@の動画を再生", clip.timeText))
                    .accessibilityIdentifier("library.clip.preview")
                }

                if remainingClipCount > 0 {
                    Button(action: onOpen) {
                        VStack(spacing: 5) {
                            Text("+\(remainingClipCount)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DaylogModernTheme.foreground)
                                .frame(width: 64, height: 64)
                                .background(DaylogModernTheme.mediaPlaceholder)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                            Text(L10n.text("すべて"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DaylogModernTheme.secondary)
                        }
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(L10n.text("残り%d本を表示", remainingClipCount))
                    .accessibilityIdentifier("library.day.more")
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .frame(height: 87)
        .padding(.top, 11)
        .padding(.bottom, 12)
    }

    private var remainingClipCount: Int {
        max(item.clips.count - 3, 0)
    }

    private func exportLoadIndicator(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(item.exportAssessment.load == .heavy
                             ? DaylogModernTheme.danger
                             : DaylogModernTheme.secondary)
            .accessibilityLabel(L10n.text("結合時に注意が必要です。%@", text))
    }
}

private struct CameraRollDayHero: View {
    let item: CameraRollDayItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            GeometryReader { proxy in
                if let first = item.clips.first {
                    CameraRollHeroThumbnail(
                        item: first,
                        thumbnailProvider: thumbnailProvider,
                        targetSize: proxy.size
                    )
                    .id(first.id)
                } else {
                    DaylogModernTheme.mediaPlaceholder
                }
            }
            .overlay {
                ZStack {
                    Circle().fill(.black.opacity(0.38))
                    Circle().stroke(.white.opacity(0.48), lineWidth: 1)
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
                .frame(width: 58, height: 58)
            }
            .overlay(alignment: .bottomTrailing) {
                if let first = item.clips.first {
                    Text(first.timeText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.38), in: Capsule())
                        .padding(12)
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .aspectRatio(1.22, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityLabel(L10n.text("%@を続けて再生", item.dateText))
        .accessibilityValue(L10n.text("%@、%@", item.summaryText, item.durationText))
        .accessibilityIdentifier("library.day.play")
    }
}

private struct CameraRollHeroThumbnail: View {
    let item: CameraRollClipItem
    let thumbnailProvider: LibraryThumbnailProviding
    let targetSize: CGSize

    var body: some View {
        LibraryThumbnailView(
            assetIdentifier: item.id,
            thumbnailProvider: thumbnailProvider,
            targetSize: CGSize(
                width: max(targetSize.width, 160),
                height: max(targetSize.height, 200)
            )
        ) {
            DaylogModernTheme.mediaPlaceholder
                .overlay {
                    ProgressView().tint(DaylogModernTheme.accent)
                }
        }
    }
}
