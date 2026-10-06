import SwiftUI

/// 月のカレンダー。各日のマスに 0時→24時 の縦帯を置き、撮った時刻に線を引く。
/// 数字の集計や凡例は置かず、帯だけで見せる。今日のマスには「いま」の点を出す。
struct CameraRollCalendarView: View {
    let days: [CameraRollCalendarDayItem]
    @Binding var displayedMonth: Date
    /// 以前のサムネイル表示との互換のために受け取る（現在の表示では使わない）。
    let thumbnailProvider: LibraryThumbnailProviding
    let onOpenDay: (String) -> Void

    private let calendar = Calendar.autoupdatingCurrent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    var body: some View {
        let month = calendarMonth
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                monthHeader

                VStack(spacing: 8) {
                    weekdayHeader
                    // 分単位で「今日」と「いま」の位置を更新する（日付をまたいでも正しく出す）。
                    TimelineView(.everyMinute) { context in
                        grid(for: month, now: context.date)
                    }
                }
                .accessibilityIdentifier("calendar.grid")
            }
            .padding(.horizontal, RollTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(RollTheme.ground)
        .contentShape(Rectangle())
        .simultaneousGesture(monthSwipeGesture)
    }

    private var monthHeader: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(CameraRollStampFormat.month.string(from: displayedMonth))
                .rollMono(56, .medium, maxScale: 1.2)
                .tracking(-2)
                .foregroundStyle(RollTheme.ink)
                .accessibilityLabel(VlogishFormatters.yearMonthTitleFormatter.string(from: displayedMonth))
                .accessibilityIdentifier("calendar.month")

            VStack(alignment: .leading, spacing: 2) {
                Text(CameraRollStampFormat.year.string(from: displayedMonth))
                    .rollMono(11)
                    .foregroundStyle(RollTheme.secondary)
                Text(CameraRollStampFormat.monthName.string(from: displayedMonth).uppercased())
                    .rollMono(11, .semibold)
                    .tracking(0.9)
                    .foregroundStyle(RollTheme.ink)
            }
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            monthButton(systemName: "chevron.left", label: "前の月", identifier: "calendar.previous", offset: -1)
            monthButton(systemName: "chevron.right", label: "次の月", identifier: "calendar.next", offset: 1)
        }
    }

    private func grid(for month: CameraRollCalendarMonth, now: Date) -> some View {
        let startOfToday = calendar.startOfDay(for: now)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(month.cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    let item = month.recordedDay(on: date, calendar: calendar)
                    let isToday = calendar.isDate(date, inSameDayAs: now)
                    CameraRollCalendarDayCell(
                        date: date,
                        item: item,
                        isToday: isToday,
                        isFuture: !isToday && date > startOfToday,
                        nowFraction: isToday ? CameraRollTimeAxis.fraction(of: now, calendar: calendar) : nil,
                        onTap: { item.map { onOpenDay($0.id) } }
                    )
                } else {
                    Color.clear.frame(height: CameraRollCalendarDayCell.height)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(VlogishFormatters.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .rollMono(10)
                    .foregroundStyle(RollTheme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func monthButton(
        systemName: String,
        label: String,
        identifier: String,
        offset: Int
    ) -> some View {
        Button {
            changeMonth(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RollTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(L10n.text(label))
        .accessibilityIdentifier(identifier)
    }

    private var calendarMonth: CameraRollCalendarMonth {
        CameraRollCalendarPresenter.makeMonth(
            containing: displayedMonth,
            days: days,
            calendar: calendar
        )
    }

    private func changeMonth(by offset: Int) {
        guard let start = CameraRollCalendarPresenter.month(
            offsetBy: offset,
            from: displayedMonth,
            calendar: calendar
        ) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            displayedMonth = start
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) > 56 else { return }
                changeMonth(by: value.translation.width < 0 ? 1 : -1)
            }
    }
}

private struct CameraRollCalendarDayCell: View {
    static let height: CGFloat = 76
    private static let barHeight: CGFloat = 52

    let date: Date
    let item: CameraRollCalendarDayItem?
    let isToday: Bool
    let isFuture: Bool
    /// 今日のマスだけ値が入る。0〜1。
    let nowFraction: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(Calendar.autoupdatingCurrent.component(.day, from: date)))
                    .rollMono(11, isEmphasized ? .semibold : .regular)
                    .foregroundStyle(numberColor)
                    .padding(.leading, 2)

                bar
            }
            .frame(minHeight: Self.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(item == nil)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item == nil ? "" : L10n.text("この日の動画を開きます"))
        .accessibilityIdentifier(item == nil ? "calendar.day.empty" : "calendar.day.recorded")
    }

    private var isEmphasized: Bool {
        item != nil || isToday
    }

    private var numberColor: Color {
        if isEmphasized { return RollTheme.ink }
        return isFuture ? RollTheme.dashed : RollTheme.secondary
    }

    /// 撮った日は帯と線、今日は枠と「いま」の点。撮っていない日は何も描かない。
    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Canvas { context, size in
            if let item {
                for fraction in item.clipFractions {
                    let y = min(max(size.height * CGFloat(fraction) - 1, 0), size.height - 2)
                    let rect = CGRect(x: 6, y: y, width: max(size.width - 12, 1), height: 2)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(RollTheme.ink))
                }
            }
            if let nowFraction {
                let y = min(max(size.height * CGFloat(nowFraction), 3.5), size.height - 3.5)
                let dot = CGRect(x: size.width / 2 - 3.5, y: y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: dot), with: .color(RollTheme.accent))
            }
        }
        .frame(height: Self.barHeight)
        .background(item == nil ? Color.clear : RollTheme.fill, in: shape)
        .overlay {
            if isToday { shape.strokeBorder(RollTheme.ink, lineWidth: 1.5) }
        }
    }

    private var accessibilityLabel: String {
        let day = Calendar.autoupdatingCurrent.component(.day, from: date)
        guard let item else { return L10n.text("%d日、動画なし", day) }
        return L10n.text("%d日、%d本、%@", day, item.clipCount, item.durationText)
    }
}
