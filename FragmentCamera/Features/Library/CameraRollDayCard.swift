import SwiftUI

/// フィード最上段。いちばん新しい日を大きく、時間軸つきで見せる。
struct CameraRollHeroDay: View {
    let item: CameraRollDayItem
    /// 日付をまたいでも正しく出せるよう、呼び出し側が「今日か」を決める。
    let isToday: Bool
    let thumbnailProvider: LibraryThumbnailProviding
    let onOpen: () -> Void
    let onClipTap: (String) -> Void
    let onPlay: () -> Void
    let onExport: () -> Void
    let onCancelExport: () -> Void

    /// 半分の高さのシートに今日の分が収まる大きさ。
    private let frameSize = CGSize(width: 60, height: 106)
    @ScaledMetric(relativeTo: .caption2) private var timeLabelHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, RollTheme.pagePadding)

            if let text = item.exportAssessment.indicatorText {
                Label(text, systemImage: "exclamationmark.triangle")
                    .rollText(11, .medium)
                    .foregroundStyle(item.exportAssessment.load == .heavy ? VlogishModernTheme.danger : RollTheme.secondary)
                    .padding(.horizontal, RollTheme.pagePadding)
                    .accessibilityLabel(L10n.text("結合時に注意が必要です。%@", text))
            }

            strip

            Button(action: onOpen) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    CameraRollTimeRuler(
                        fractions: item.clips.map(\.dayFraction),
                        nowFraction: Calendar.current.isDate(item.date, inSameDayAs: context.date)
                            ? CameraRollTimeAxis.fraction(of: context.date)
                            : nil,
                        showsLabels: true
                    )
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .padding(.horizontal, RollTheme.pagePadding)

            actions
                .padding(.horizontal, RollTheme.pagePadding)
        }
        .padding(.top, 4)
        .padding(.bottom, 22)
    }

    /// 日付の行全体が「この日を開く」ボタン。右端の矢印で行き先を示す。
    private var header: some View {
        Button(action: onOpen) {
            HStack(alignment: .bottom, spacing: 10) {
                Text(item.stampDateText)
                    .rollMono(40, .medium, maxScale: 1.25)
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.stampWeekdayText)
                        .rollMono(11, .semibold)
                        .tracking(0.9)
                    Text(isToday ? L10n.text("今日") : item.dateText)
                        .rollText(12)
                        .foregroundStyle(RollTheme.secondary)
                }
                .padding(.bottom, 4)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: CameraRollStampFormat.clips(item.clipCount))
                    Text(item.durationText)
                }
                .rollMono(12)
                .foregroundStyle(RollTheme.secondary)
                .padding(.bottom, 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RollTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(RollTheme.fill, in: Circle())
                    .padding(.bottom, 2)
            }
            .foregroundStyle(RollTheme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(L10n.text("%@、%@、%@", item.dateText, item.summaryText, item.durationText))
        .accessibilityHint(L10n.text("この日の動画一覧を開きます"))
        .accessibilityIdentifier("library.day.details")
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 4) {
                ForEach(item.clips) { clip in
                    Button {
                        onClipTap(clip.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CameraRollFrame(
                                assetIdentifier: clip.id,
                                size: frameSize,
                                cornerRadius: 8,
                                thumbnailProvider: thumbnailProvider
                            )
                            Text(clip.timeText)
                                .rollMono(10)
                                .foregroundStyle(RollTheme.secondary)
                        }
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(L10n.text("%@の動画を再生", clip.timeText))
                    .accessibilityIdentifier("library.clip.preview")
                }
            }
            .padding(.horizontal, RollTheme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .frame(height: frameSize.height + 6 + timeLabelHeight)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isToday ? L10n.text("今日を通して見る") : L10n.text("通して見る"))
                        .rollText(14, .semibold)
                }
                .foregroundStyle(RollTheme.ground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(RollTheme.ink, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityLabel(L10n.text("%@を続けて再生", item.dateText))
            .accessibilityIdentifier("library.day.play")

            CameraRollExportButton(
                isExporting: item.isExporting,
                progress: item.exportProgress,
                isEnabled: item.canExport,
                onExport: onExport,
                onCancel: onCancelExport
            )
        }
    }
}

/// フィード2段目以降。日付・小さなコマ・時間軸を1行で。
struct CameraRollDayRow: View {
    let item: CameraRollDayItem
    let thumbnailProvider: LibraryThumbnailProviding
    let onOpen: () -> Void

    private let frameSize = CGSize(width: 30, height: 53)
    private let maxFrames = 7

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.stampDateText)
                        .rollMono(18, .medium)
                        .tracking(-0.4)
                        .foregroundStyle(RollTheme.ink)
                    Text("\(item.stampWeekdayText) · \(item.durationText)")
                        .rollMono(10)
                        .foregroundStyle(RollTheme.secondary)
                        .lineLimit(1)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(item.clips.prefix(maxFrames)) { clip in
                            CameraRollFrame(
                                assetIdentifier: clip.id,
                                size: frameSize,
                                cornerRadius: 4,
                                thumbnailProvider: thumbnailProvider
                            )
                        }
                        if item.clips.count > maxFrames {
                            Text("+\(item.clips.count - maxFrames)")
                                .rollMono(10, .medium)
                                .foregroundStyle(RollTheme.secondary)
                                .frame(height: frameSize.height)
                                .padding(.leading, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                    CameraRollTimeRuler(
                        fractions: item.clips.map(\.dayFraction),
                        nowFraction: nil,
                        tickHeight: 7,
                        tickWidth: 1
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RollTheme.secondary)
                    .frame(width: 12, height: frameSize.height)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RollTheme.rowLine).frame(height: 1)
        }
        .accessibilityLabel(L10n.text("%@、%@、%@", item.dateText, item.summaryText, item.durationText))
        .accessibilityHint(L10n.text("この日の動画一覧を開きます"))
        .accessibilityIdentifier("library.day.details")
    }
}

/// 記録が無かった日の行。空白も一日の一部として隠さない。
struct CameraRollNoRecordRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .rollMono(12)
                .foregroundStyle(RollTheme.secondary)
                .lineLimit(1)
                .fixedSize()
            CameraRollDashedLine()
            Text("記録なし")
                .rollText(11)
                .foregroundStyle(RollTheme.secondary)
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RollTheme.rowLine).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 今日まだ撮っていない時の最上段。空の時間軸と「いま」を見せて、撮影へ戻す。
struct CameraRollTodayEmptyHero: View {
    let today: Date
    let onCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 10) {
                Text(CameraRollStampFormat.date.string(from: today))
                    .rollMono(40, .medium, maxScale: 1.25)
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(CameraRollStampFormat.weekday.string(from: today).uppercased())
                        .rollMono(11, .semibold)
                        .tracking(0.9)
                    Text(L10n.text("今日"))
                        .rollText(12)
                        .foregroundStyle(RollTheme.secondary)
                }
                .padding(.bottom, 4)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: CameraRollStampFormat.clips(0))
                    Text(VlogishFormatters.durationLabel(0))
                }
                .rollMono(12)
                .foregroundStyle(RollTheme.secondary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            }
            .foregroundStyle(RollTheme.ink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("今日、まだ動画はありません"))

            // クリップが並ぶ場所に、1本目の枠を置く。撮ったらここに並ぶことを場所で伝える。
            HStack(alignment: .center, spacing: 14) {
                Button(action: onCapture) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                        Text(verbatim: "1ST")
                            .rollMono(9, .semibold, maxScale: 1.2)
                            .tracking(0.6)
                    }
                    .foregroundStyle(RollTheme.secondary)
                    .frame(width: 60, height: 106)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(RollTheme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel(L10n.text("カメラに戻って撮る"))

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("今日の1本目は、まだ。"))
                        .rollText(15, .bold)
                        .foregroundStyle(RollTheme.ink)
                    Text(L10n.text("撮った動画は、ここに時刻順で並びます。"))
                        .rollText(12)
                        .foregroundStyle(RollTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                CameraRollTimeRuler(
                    fractions: [],
                    nowFraction: CameraRollTimeAxis.fraction(of: context.date),
                    showsLabels: true
                )
            }

            Button(action: onCapture) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("カメラに戻って撮る"))
                        .rollText(14, .semibold)
                }
                .foregroundStyle(RollTheme.ground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(RollTheme.ink, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityIdentifier("library.empty.capture")
            .padding(.top, 2)
        }
        .padding(.horizontal, RollTheme.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }
}
