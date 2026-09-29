import SwiftUI

struct CameraRollDayDetailView: View {
    let item: CameraRollDayItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onPlayDay: () -> Void
    let onClipTap: (String) -> Void
    let onEditStamp: (String) -> Void
    let onExportClip: (String) -> Void
    let onCancelExport: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3
    )

    var body: some View {
        VStack(spacing: 0) {
            dayOverview

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(item.clips) { clip in
                        CameraRollGridClipTile(
                            item: clip,
                            thumbnailProvider: thumbnailProvider,
                            onTap: { onClipTap(clip.id) },
                            onEditStamp: { onEditStamp(clip.id) },
                            onExport: { onExportClip(clip.id) },
                            onCancelExport: onCancelExport
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(DaylogModernTheme.background)
    }

    private var dayOverview: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.summaryText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DaylogModernTheme.foreground)

                Text(item.durationText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DaylogModernTheme.secondary)
            }

            Spacer()

            Button(action: onPlayDay) {
                Label(L10n.text("一日を再生"), systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .frame(height: 40)
                    .background(DaylogModernTheme.accent, in: Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityLabel(L10n.text("この日を続けて再生"))
            .accessibilityIdentifier("library.day.play")
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(DaylogModernTheme.elevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DaylogModernTheme.divider)
                .frame(height: 1)
        }
    }
}

private struct CameraRollGridClipTile: View {
    let item: CameraRollClipItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onTap: () -> Void
    let onEditStamp: () -> Void
    let onExport: () -> Void
    let onCancelExport: () -> Void

    var body: some View {
        ZStack {
            Button(action: onTap) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(DaylogModernTheme.mediaPlaceholder)
                    .overlay {
                        LibraryThumbnailView(
                            assetIdentifier: item.id,
                            thumbnailProvider: thumbnailProvider,
                            targetSize: CGSize(width: 180, height: 180)
                        ) {
                            ProgressView()
                                .tint(DaylogModernTheme.accent)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.62)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 46)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(item.timeText)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(7)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(item.durationText)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(7)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.clip")

            VStack {
                HStack {
                    Spacer()
                    clipMenu
                }
                Spacer()
            }
            .padding(1)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(L10n.text("%@、%@の動画", item.timeText, item.durationText))
    }

    private var clipMenu: some View {
        Menu {
            Button(action: onEditStamp) {
                Label("動画を編集", systemImage: "pencil")
            }
            .accessibilityIdentifier("library.clip.stamp")

            Button(action: item.isExporting ? onCancelExport : onExport) {
                Label(
                    item.isExporting
                        ? L10n.text("書き出しをキャンセル")
                        : L10n.text("日付入りで共有"),
                    systemImage: item.isExporting ? "xmark" : "square.and.arrow.up"
                )
            }
            .disabled(!item.canExport && !item.isExporting)
            .accessibilityIdentifier("library.clip.export")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.46), in: Circle())
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("動画の操作")
        .accessibilityIdentifier("library.clip.menu")
    }

}
