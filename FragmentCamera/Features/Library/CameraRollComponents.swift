import SwiftUI
import UIKit

struct CameraRollLoadingView: View {
    var body: some View {
        ProgressView()
            .tint(DaylogModernTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 72)
            .accessibilityLabel("読み込み中")
    }
}

struct CameraRollExportProgressPanel: View {
    let progress: DayVideoExportProgress
    let onCancel: () -> Void

    private var isCancelling: Bool {
        progress.phase == .cancelling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(DaylogModernTheme.accent)

                Text(progress.phase.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DaylogModernTheme.foreground)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(progress.percentage)%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DaylogModernTheme.accent)
                    .contentTransition(.numericText())
            }

            ProgressView(value: progress.fraction, total: 1)
                .tint(DaylogModernTheme.accent)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(progress.phase.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DaylogModernTheme.secondary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(isCancelling ? L10n.text("中断中") : L10n.text("中止"), action: onCancel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCancelling ? DaylogModernTheme.secondary : DaylogModernTheme.danger)
                    .disabled(isCancelling)
            }
        }
        .padding(16)
        .background(DaylogModernTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DaylogModernTheme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("%@、%dパーセント。%@", progress.phase.title, progress.percentage, progress.phase.detail))
    }
}

struct CameraRollEmptyView: View {
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(DaylogModernTheme.tertiary)

            Text("まだ動画はありません")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DaylogModernTheme.foreground)

            Button(action: onCapture) {
                Label("撮る", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(DaylogModernTheme.accent, in: Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityIdentifier("library.empty.capture")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

struct CameraRollDayRail: View {
    let days: [CameraRollDayItem]
    let selectedDayID: String?
    let thumbnailProvider: LibraryThumbnailProviding
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(Array(days.prefix(14))) { day in
                    Button {
                        onSelect(day.id)
                    } label: {
                        VStack(spacing: 6) {
                            CameraRollCircularThumbnail(
                                assetIdentifier: day.clips.first?.id,
                                isSelected: selectedDayID == day.id,
                                thumbnailProvider: thumbnailProvider
                            )
                            .id(day.clips.first?.id)

                            Text(day.dateText)
                                .font(.system(size: 10, weight: selectedDayID == day.id ? .semibold : .medium, design: .monospaced))
                                .foregroundStyle(selectedDayID == day.id ? DaylogModernTheme.foreground : DaylogModernTheme.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(L10n.text("%@、%@", day.dateText, day.summaryText))
                    .accessibilityHint("この日まで移動")
                    .accessibilityIdentifier("library.day.rail")
                }
            }
            .padding(.horizontal, DaylogModernTheme.pagePadding)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 92)
    }
}

private struct CameraRollCircularThumbnail: View {
    let assetIdentifier: String?
    let isSelected: Bool
    let thumbnailProvider: LibraryThumbnailProviding

    var body: some View {
        LibraryThumbnailView(
            assetIdentifier: assetIdentifier,
            thumbnailProvider: thumbnailProvider,
            targetSize: CGSize(width: 72, height: 72)
        ) {
            DaylogModernTheme.mediaPlaceholder
                .overlay {
                    Image(systemName: "video")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DaylogModernTheme.tertiary)
                }
        }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(isSelected ? DaylogModernTheme.accent : DaylogModernTheme.divider, lineWidth: isSelected ? 2.5 : 1)
                    .padding(-3)
            }
            .padding(3)
    }
}

