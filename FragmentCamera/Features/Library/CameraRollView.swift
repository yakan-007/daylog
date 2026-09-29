import SwiftUI

struct CameraRollView: View {
    let state: CameraRollScreenState
    let thumbnailProvider: LibraryThumbnailProviding
    let onClipTap: (String) -> Void
    let onEditStamp: (String) -> Void
    let onExportClip: (String) -> Void
    let onPlayDay: (String) -> Void
    let onExportDay: (String) -> Void
    let onLoadDay: (String) async -> Void
    let onCancelExport: () -> Void
    let onLoadMore: (String) -> Void
    let onRefresh: () async -> Void
    let onClose: () -> Void

    @State private var surface: Surface = .feed
    @State private var selectedFeedDayID: String?
    @State private var displayedCalendarMonth = CameraRollCalendarPresenter
        .monthStart(containing: .now)
    @State private var hasAlignedCalendarMonth = false

    private enum DayOrigin: Equatable {
        case feed
        case calendar
        case archive
    }

    private enum Surface: Equatable {
        case feed
        case calendar
        case archive
        case day(id: String, origin: DayOrigin)
    }

    var body: some View {
        ZStack {
            DaylogModernBackground()

            switch surface {
            case .feed:
                feed.transition(.opacity)
            case .calendar:
                calendar.transition(.opacity)
            case .archive:
                archive.transition(.opacity)
            case .day(let id, let origin):
                day(id: id, origin: origin)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let progress = state.exportProgress {
                CameraRollExportProgressPanel(
                    progress: progress,
                    onCancel: onCancelExport
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.exportProgress != nil)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: state.days.first?.id) { _, firstID in
            if selectedFeedDayID == nil {
                selectedFeedDayID = firstID
            }
        }
        .onChange(of: state.calendarDays.first?.id, initial: true) { _, firstID in
            guard !hasAlignedCalendarMonth, firstID != nil else { return }
            hasAlignedCalendarMonth = true

            if !CameraRollCalendarPresenter.containsRecordings(
                in: displayedCalendarMonth,
                days: state.calendarDays
            ), let latestDate = state.calendarDays.first?.date {
                displayedCalendarMonth = CameraRollCalendarPresenter
                    .monthStart(containing: latestDate)
            }
        }
    }

    private var feed: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                feedHeader

                if state.days.count > 1 {
                    CameraRollDayRail(
                        days: state.days,
                        selectedDayID: selectedFeedDayID ?? state.days.first?.id,
                        thumbnailProvider: thumbnailProvider
                    ) { id in
                        selectedFeedDayID = id
                        withAnimation(.snappy(duration: 0.32)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }

                    divider
                }

                ScrollView {
                    LazyVStack(spacing: 18) {
                        if state.showsInitialLoading {
                            CameraRollLoadingView()
                        } else if state.showsEmptyState {
                            CameraRollEmptyView(onCapture: onClose)
                        } else {
                            ForEach(state.days) { day in
                                CameraRollDayCard(
                                    item: day,
                                    thumbnailProvider: thumbnailProvider,
                                    onOpen: { openDay(day.id, origin: .feed) },
                                    onClipTap: onClipTap,
                                    onPlay: { onPlayDay(day.id) },
                                    onExport: { onExportDay(day.id) },
                                    onCancelExport: onCancelExport
                                )
                                .id(day.id)
                                .onAppear {
                                    onLoadMore(day.id)
                                }
                            }
                        }
                    }
                    .padding(.top, state.days.isEmpty ? 0 : 12)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await onRefresh()
                }
            }
        }
        .background(DaylogModernTheme.background)
    }

    private var feedHeader: some View {
        surfaceHeader(
            title: AppIdentity.brandName,
            leadingSystemName: "xmark",
            leadingLabel: "閉じる",
            leadingIdentifier: "library.close",
            leadingAction: onClose,
            trailingSystemName: "calendar",
            trailingLabel: "カレンダーを開く",
            trailingIdentifier: "navigation.calendar",
            trailingAction: { surface = .calendar }
        )
    }

    private var calendar: some View {
        VStack(spacing: 0) {
            surfaceHeader(
                title: L10n.text("カレンダー"),
                leadingSystemName: "chevron.left",
                leadingLabel: "記録へ戻る",
                leadingIdentifier: "calendar.back",
                leadingAction: { surface = .feed },
                trailingSystemName: "square.grid.3x3",
                trailingLabel: "すべての動画",
                trailingIdentifier: "navigation.archive",
                trailingAction: { surface = .archive }
            )
            divider
            CameraRollCalendarView(
                days: state.calendarDays,
                displayedMonth: $displayedCalendarMonth,
                thumbnailProvider: thumbnailProvider,
                onOpenDay: { id in
                    openDay(id, origin: .calendar)
                    Task { await onLoadDay(id) }
                }
            )
        }
    }

    private var archive: some View {
        VStack(spacing: 0) {
            surfaceHeader(
                title: L10n.text("すべて"),
                leadingSystemName: "chevron.left",
                leadingLabel: "記録へ戻る",
                leadingIdentifier: "archive.back",
                leadingAction: { surface = .feed },
                trailingSystemName: "calendar",
                trailingLabel: "カレンダーを開く",
                trailingIdentifier: "navigation.calendar",
                trailingAction: { surface = .calendar }
            )
            divider
            CameraRollArchiveView(
                days: state.days,
                thumbnailProvider: thumbnailProvider,
                onClipTap: onClipTap,
                onOpenDay: { openDay($0, origin: .archive) },
                onLoadMore: onLoadMore,
                onRefresh: onRefresh,
                onCapture: onClose
            )
        }
    }

    private func surfaceHeader(
        title: String,
        leadingSystemName: String,
        leadingLabel: String,
        leadingIdentifier: String,
        leadingAction: @escaping () -> Void,
        trailingSystemName: String,
        trailingLabel: String,
        trailingIdentifier: String,
        trailingAction: @escaping () -> Void
    ) -> some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.35)
                .foregroundStyle(DaylogModernTheme.foreground)

            HStack(spacing: 0) {
                Button(action: leadingAction) {
                    Image(systemName: leadingSystemName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DaylogModernTheme.foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel(L10n.text(leadingLabel))
                .accessibilityIdentifier(leadingIdentifier)

                Spacer()

                Button(action: trailingAction) {
                    Image(systemName: trailingSystemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DaylogModernTheme.foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel(L10n.text(trailingLabel))
                .accessibilityIdentifier(trailingIdentifier)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(DaylogModernTheme.background)
    }

    @ViewBuilder
    private func day(id: String, origin: DayOrigin) -> some View {
        if let item = dayItem(id: id) {
            VStack(spacing: 0) {
                dayHeader(item: item, origin: origin)
                divider
                CameraRollDayDetailView(
                    item: item,
                    thumbnailProvider: thumbnailProvider,
                    onPlayDay: { onPlayDay(item.id) },
                    onClipTap: onClipTap,
                    onEditStamp: onEditStamp,
                    onExportClip: onExportClip,
                    onCancelExport: onCancelExport
                )
            }
            .background(DaylogModernTheme.background)
        } else {
            VStack(spacing: 0) {
                dayLoadingHeader(origin: origin)
                divider
                CameraRollLoadingView()
                Spacer()
            }
            .background(DaylogModernTheme.background)
        }
    }

    private func dayHeader(item: CameraRollDayItem, origin: DayOrigin) -> some View {
        ZStack {
            VStack(spacing: 2) {
                Text(item.dateText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DaylogModernTheme.foreground)
                Text("\(item.summaryText) · \(item.durationText)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DaylogModernTheme.secondary)
            }

            HStack(spacing: 0) {
                dayBackButton(origin: origin)

                Spacer()

                Button {
                    if item.isExporting {
                        onCancelExport()
                    } else {
                        onExportDay(item.id)
                    }
                } label: {
                    Image(systemName: item.isExporting ? "xmark" : "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DaylogModernTheme.foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(!item.canExport && !item.isExporting)
                .opacity((item.canExport || item.isExporting) ? 1 : 0.28)
                .accessibilityLabel(item.isExporting ? L10n.text("結合をキャンセル") : L10n.text("1本に結合して共有"))
                .accessibilityIdentifier("library.day.export")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }

    private func dayLoadingHeader(origin: DayOrigin) -> some View {
        HStack {
            dayBackButton(origin: origin)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }

    private func dayBackButton(origin: DayOrigin) -> some View {
        Button {
            switch origin {
            case .feed:
                surface = .feed
            case .calendar:
                surface = .calendar
            case .archive:
                surface = .archive
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DaylogModernTheme.foreground)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(backLabel(for: origin))
        .accessibilityIdentifier(backIdentifier(for: origin))
    }

    private var divider: some View {
        Rectangle()
            .fill(DaylogModernTheme.divider)
            .frame(height: 1)
    }

    private func openDay(_ id: String, origin: DayOrigin) {
        surface = .day(id: id, origin: origin)
    }

    private func backLabel(for origin: DayOrigin) -> String {
        switch origin {
        case .feed:
            return L10n.text("記録へ戻る")
        case .calendar:
            return L10n.text("カレンダーへ戻る")
        case .archive:
            return L10n.text("一覧へ戻る")
        }
    }

    private func backIdentifier(for origin: DayOrigin) -> String {
        switch origin {
        case .feed:
            return "library.day.back"
        case .calendar:
            return "calendar.day.back"
        case .archive:
            return "archive.day.back"
        }
    }

    private func dayItem(id: String) -> CameraRollDayItem? {
        state.days.first(where: { $0.id == id })
    }
}
