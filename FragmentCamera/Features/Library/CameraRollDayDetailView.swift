import SwiftUI

/// 1日の詳細。クリップを時刻の背骨に沿って並べ、撮っていない時間も「空白」として見せる。
struct CameraRollDayDetailView: View {
    let item: CameraRollDayItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onPlayDay: () -> Void
    let onClipTap: (String) -> Void
    let onEditStamp: (String) -> Void
    let onExportClip: (String) -> Void
    let onCancelExport: () -> Void
    var onRemoveClip: (String, ClipRemoval) -> Void = { _, _ in }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isToday = Calendar.current.isDate(item.date, inSameDayAs: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    overview(now: isToday ? context.date : nil)

                    Rectangle()
                        .fill(RollTheme.hairline)
                        .frame(height: 1)

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(CameraRollTimelinePresenter.rows(
                            for: item.clips,
                            now: isToday ? context.date : nil
                        )) { row in
                            rowView(row)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, RollTheme.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
        .background(RollTheme.ground)
    }

    private func overview(now: Date?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CameraRollTimeRuler(
                fractions: item.clips.map(\.dayFraction),
                nowFraction: now.map { CameraRollTimeAxis.fraction(of: $0) },
                showsLabels: true
            )

            Button(action: onPlayDay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("この日を通して見る"))
                        .rollText(14, .semibold)
                    Spacer(minLength: 8)
                    Text(item.durationText)
                        .rollMono(12)
                        .opacity(0.7)
                }
                .foregroundStyle(RollTheme.ground)
                .padding(.horizontal, 20)
                .frame(minHeight: 48)
                .background(RollTheme.ink, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityLabel(L10n.text("この日を続けて再生"))
            .accessibilityIdentifier("library.day.play")
        }
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func rowView(_ row: CameraRollTimelineRow) -> some View {
        switch row {
        case .clip(let clip, let hourLabel):
            CameraRollTimelineClipRow(
                clip: clip,
                hourLabel: hourLabel,
                thumbnailProvider: thumbnailProvider,
                onTap: { onClipTap(clip.id) },
                onEditStamp: { onEditStamp(clip.id) },
                onExport: { onExportClip(clip.id) },
                onCancelExport: onCancelExport,
                onRemove: { onRemoveClip(clip.id, $0) }
            )
        case .gap(_, let hourLabel, let text):
            HStack(spacing: 0) {
                hourColumn(hourLabel, emphasized: false)
                Color.clear.frame(width: 1)
                Text(text)
                    .rollMono(10)
                    .tracking(0.4)
                    .foregroundStyle(RollTheme.secondary)
                    .padding(.leading, 14)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30)
            .background(alignment: .leading) {
                CameraRollDashedLine(vertical: true)
                    .padding(.leading, 30)
            }
            .accessibilityElement(children: .combine)
        case .now(_, let hourLabel, let timeText):
            HStack(spacing: 0) {
                hourColumn(hourLabel, emphasized: true)
                Circle()
                    .fill(RollTheme.accent)
                    .frame(width: 9, height: 9)
                    .offset(x: -4)
                Text(L10n.text("いま %@", timeText))
                    .rollText(12)
                    .foregroundStyle(RollTheme.ink)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 34)
            .accessibilityElement(children: .combine)
        }
    }

    private func hourColumn(_ label: String, emphasized: Bool) -> some View {
        Text(label)
            .rollMono(11, emphasized ? .semibold : .regular)
            .foregroundStyle(emphasized ? RollTheme.ink : RollTheme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 30, alignment: .leading)
    }
}

private struct CameraRollTimelineClipRow: View {
    let clip: CameraRollClipItem
    let hourLabel: String?
    let thumbnailProvider: LibraryThumbnailProviding
    let onTap: () -> Void
    let onEditStamp: () -> Void
    let onExport: () -> Void
    let onCancelExport: () -> Void
    let onRemove: (ClipRemoval) -> Void

    @State private var isChoosingRemoval = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(hourLabel ?? "")
                .rollMono(11)
                .foregroundStyle(RollTheme.secondary)
                .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 30, alignment: .leading)
                .padding(.top, 12)
                .accessibilityHidden(true)

            Color.clear.frame(width: 1)

            HStack(spacing: 4) {
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        CameraRollFrame(
                            assetIdentifier: clip.id,
                            size: CGSize(width: 32, height: 56),
                            cornerRadius: 5,
                            thumbnailProvider: thumbnailProvider
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(clip.timeText)
                                .rollMono(14, .medium)
                                .foregroundStyle(RollTheme.ink)
                            Text(clip.durationText)
                                .rollMono(11)
                                .foregroundStyle(RollTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("%@、%@の動画", clip.timeText, clip.durationText))
                .accessibilityIdentifier("library.clip")

                clipMenu
            }
            .padding(.leading, 10)
            .padding(.vertical, 4)
        }
        .frame(minHeight: 64)
        .background(alignment: .leading) {
            // 背骨の線。行の高さが文字サイズで伸びても途切れないよう背景で描く。
            Rectangle()
                .fill(RollTheme.ink)
                .frame(width: 1)
                .padding(.leading, 30)
        }
    }

    private var clipMenu: some View {
        Menu {
            Button(action: onEditStamp) {
                Label("動画を編集", systemImage: "pencil")
            }
            .accessibilityIdentifier("library.clip.stamp")

            Button(action: clip.isExporting ? onCancelExport : onExport) {
                Label(
                    clip.isExporting
                        ? L10n.text("書き出しをキャンセル")
                        : L10n.text("日付入りで共有"),
                    systemImage: clip.isExporting ? "xmark" : "square.and.arrow.up"
                )
            }
            .disabled(!clip.canExport && !clip.isExporting)
            .accessibilityIdentifier("library.clip.export")

            Divider()

            // 押したら「Vlogishから外す / 写真からも削除」を選ばせる（写真アプリのアルバムと同じ形）。
            Button(role: .destructive) {
                isChoosingRemoval = true
            } label: {
                Label(L10n.text("削除"), systemImage: "trash")
            }
            .disabled(clip.isExporting)
            .accessibilityIdentifier("library.clip.delete")
        } label: {
            ZStack {
                if clip.isExporting {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(clip.exportProgress ?? 0, 0), 1)))
                        .stroke(RollTheme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RollTheme.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("動画の操作")
        .accessibilityIdentifier("library.clip.menu")
        .confirmationDialog(
            L10n.text("Vlogishから外しても、動画は写真に残ります。"),
            isPresented: $isChoosingRemoval,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Vlogishから外す")) {
                onRemove(.removeFromVlogish)
            }
            .accessibilityIdentifier("library.clip.removeFromVlogish")
            Button(L10n.text("写真からも削除"), role: .destructive) {
                onRemove(.deleteFromPhotos)
            }
            .accessibilityIdentifier("library.clip.deleteFromPhotos")
        }
    }
}
