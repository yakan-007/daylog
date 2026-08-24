import SwiftUI

struct CameraRollCalendarView: View {
    let days: [CameraRollCalendarDayItem]
    @Binding var displayedMonth: Date
    let thumbnailProvider: LibraryThumbnailProviding
    let onOpenDay: (String) -> Void

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 5),
        count: 7
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                monthNavigation
                weekdayHeader

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(calendarMonth.cells.enumerated()), id: \.offset) { _, date in
                        if let date {
                            let item = calendarMonth.recordedDay(on: date, calendar: calendar)
                            CameraRollCalendarDayCell(
                                date: date,
                                item: item,
                                isToday: calendar.isDateInToday(date),
                                thumbnailProvider: thumbnailProvider,
                                onTap: { item.map { onOpenDay($0.id) } }
                            )
                            .id(date)
                        } else {
                            Color.clear
                                .aspectRatio(0.78, contentMode: .fit)
                        }
                    }
                }
                .padding(.horizontal, 12)

                monthSummary
                    .padding(.top, 22)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(DaylogModernTheme.background)
        .contentShape(Rectangle())
        .gesture(monthSwipeGesture)
        .accessibilityIdentifier("calendar.grid")
    }

    private var monthNavigation: some View {
        ZStack {
            Text(DaylogFormatters.yearMonthTitleFormatter.string(from: displayedMonth))
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.65)
                .foregroundStyle(DaylogModernTheme.foreground)
                .accessibilityIdentifier("calendar.month")

            HStack {
                monthButton(
                    systemName: "chevron.left",
                    label: "前の月",
                    identifier: "calendar.previous",
                    offset: -1
                )

                Spacer()

                monthButton(
                    systemName: "chevron.right",
                    label: "次の月",
                    identifier: "calendar.next",
                    offset: 1
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(DaylogFormatters.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DaylogModernTheme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private var monthSummary: some View {
        return HStack(spacing: 14) {
            Label(
                calendarMonth.recordedDayCount == 1
                    ? L10n.text("1日")
                    : L10n.text("%d日", calendarMonth.recordedDayCount),
                systemImage: "calendar"
            )
            Label(
                calendarMonth.clipCount == 1
                    ? L10n.text("1本")
                    : L10n.text("%d本", calendarMonth.clipCount),
                systemImage: "video"
            )
            if calendarMonth.totalDuration > 0 {
                Label(
                    DaylogFormatters.durationLabel(calendarMonth.totalDuration),
                    systemImage: "clock"
                )
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(DaylogModernTheme.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("calendar.summary")
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DaylogModernTheme.foreground)
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
        withAnimation(.snappy(duration: 0.28)) {
            displayedMonth = start
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 48 else { return }
                changeMonth(by: value.translation.width < 0 ? 1 : -1)
            }
    }

}

private struct CameraRollCalendarDayCell: View {
    let date: Date
    let item: CameraRollCalendarDayItem?
    let isToday: Bool
    let thumbnailProvider: LibraryThumbnailProviding
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(item == nil ? Color.clear : DaylogModernTheme.mediaPlaceholder)
                    .overlay {
                        if let item {
                            LibraryThumbnailView(
                                assetIdentifier: item.previewAssetIdentifier,
                                thumbnailProvider: thumbnailProvider,
                                targetSize: CGSize(width: 92, height: 118)
                            ) {
                                Color.clear
                            }
                        }
                    }
                    .overlay {
                        if item != nil {
                            LinearGradient(
                                colors: [.black.opacity(0.42), .clear, .black.opacity(0.56)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(String(Calendar.autoupdatingCurrent.component(.day, from: date)))
                    .font(.system(size: 12, weight: item == nil ? .medium : .bold, design: .rounded))
                    .foregroundStyle((item != nil || isToday) ? .white : DaylogModernTheme.foreground)
                    .frame(width: 25, height: 25)
                    .background {
                        if isToday {
                            Circle().fill(DaylogModernTheme.accent)
                        }
                    }
                    .padding(3)

                if let item {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(item.clipCount)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(5)
                        }
                    }
                }
            }
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(item == nil)
        .aspectRatio(0.78, contentMode: .fit)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item == nil ? "" : L10n.text("この日の動画を開きます"))
        .accessibilityIdentifier(item == nil ? "calendar.day.empty" : "calendar.day.recorded")
    }

    private var accessibilityLabel: String {
        let day = Calendar.autoupdatingCurrent.component(.day, from: date)
        guard let item else { return L10n.text("%d日、動画なし", day) }
        return L10n.text("%d日、%d本、%@", day, item.clipCount, item.durationText)
    }
}
