import SwiftUI

struct CameraRollArchiveView: View {
    let days: [CameraRollDayItem]
    let thumbnailProvider: LibraryThumbnailProviding
    let onClipTap: (String) -> Void
    let onOpenDay: (String) -> Void
    let onLoadMore: (String) -> Void
    let onRefresh: () async -> Void
    let onCapture: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if days.isEmpty {
                    CameraRollEmptyView(onCapture: onCapture)
                } else {
                    ForEach(monthGroups) { group in
                        VStack(spacing: 0) {
                            monthHeader(group)

                            ForEach(group.days) { day in
                                dayHeader(day)

                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(day.clips) { clip in
                                        CameraRollArchiveClipTile(
                                            item: clip,
                                            thumbnailProvider: thumbnailProvider,
                                            onTap: { onClipTap(clip.id) }
                                        )
                                    }
                                }
                                .onAppear {
                                    onLoadMore(day.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await onRefresh()
        }
        .background(DaylogModernTheme.background)
        .accessibilityIdentifier("archive.grid")
    }

    private func monthHeader(_ group: ArchiveMonthGroup) -> some View {
        HStack(alignment: .bottom) {
            Text(DaylogFormatters.yearMonthTitleFormatter.string(from: group.month))
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.9)
                .foregroundStyle(DaylogModernTheme.foreground)
                .accessibilityIdentifier("archive.month")

            Spacer()

            HStack(spacing: 10) {
                Label("\(group.days.count)", systemImage: "calendar")
                Label("\(group.clipCount)", systemImage: "video")
                Label(DaylogFormatters.durationLabel(group.totalDuration), systemImage: "clock")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(DaylogModernTheme.secondary)
        }
        .padding(.horizontal, DaylogModernTheme.pagePadding)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func dayHeader(_ day: CameraRollDayItem) -> some View {
        Button {
            onOpenDay(day.id)
        } label: {
            HStack {
                Text("\(day.dateText) \(day.weekdayText)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DaylogModernTheme.foreground)

                Text(day.summaryText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DaylogModernTheme.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DaylogModernTheme.tertiary)
            }
            .padding(.horizontal, DaylogModernTheme.pagePadding)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("%@、%@", day.dateText, day.summaryText))
        .accessibilityIdentifier("archive.day.details")
    }

    private var monthGroups: [ArchiveMonthGroup] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: days) { day in
            calendar.dateInterval(of: .month, for: day.date)?.start
                ?? calendar.startOfDay(for: day.date)
        }
        return grouped
            .map { ArchiveMonthGroup(month: $0.key, days: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.month > $1.month }
    }
}

private struct ArchiveMonthGroup: Identifiable {
    let month: Date
    let days: [CameraRollDayItem]

    var id: Date { month }
    var clipCount: Int { days.reduce(0) { $0 + $1.clips.count } }
    var totalDuration: TimeInterval { days.reduce(0) { $0 + $1.totalDuration } }
}

private struct CameraRollArchiveClipTile: View {
    let item: CameraRollClipItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            LibraryThumbnailView(
                assetIdentifier: item.id,
                thumbnailProvider: thumbnailProvider,
                targetSize: CGSize(width: 180, height: 180)
            ) {
                DaylogModernTheme.mediaPlaceholder
                    .overlay {
                        ProgressView().tint(DaylogModernTheme.accent)
                    }
            }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.58)],
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
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityLabel(L10n.text("%@、%@の動画", item.timeText, item.durationText))
        .accessibilityIdentifier("archive.clip")
    }
}
