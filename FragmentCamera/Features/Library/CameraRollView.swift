import Combine
import SwiftUI

struct CameraRollView: View {
    let state: CameraRollScreenState
    let thumbnailProvider: LibraryThumbnailProviding
    let onClipTap: (String) -> Void
    let onEditStamp: (String) -> Void
    let onExportClip: (String) -> Void
    let onPlayDay: (String) -> Void
    let onExportDay: (String) -> Void
    /// その日を読み込む。読めなかった（削除済み・iCloud未取得・限定アクセスなど）時は false。
    let onLoadDay: (String) async -> Bool
    let onCancelExport: () -> Void
    let onLoadMore: (String) -> Void
    let onRefresh: () async -> Void
    let onClose: () -> Void
    /// 半分の高さで開いているシートを全画面に広げてもらう（詳細やカレンダーへ進むとき）。
    var onExpand: () -> Void = {}
    /// 完成カードの「共有・保存」と「閉じる」。
    var onShareExport: () -> Void = {}
    var onDismissExport: () -> Void = {}
    /// 動画を削除する（1日の詳細のメニューから）。
    var onDeleteClip: (String) -> Void = { _ in }

    @State private var surface: Surface = .feed
    /// カレンダーから開いたが読み込めなかった日。スピナーのまま止まらないよう、失敗を表示して再試行できるようにする。
    @State private var failedDayIDs: Set<String> = []
    @State private var displayedCalendarMonth = CameraRollCalendarPresenter
        .monthStart(containing: .now)
    @State private var hasAlignedCalendarMonth = false
    /// 日付が変わった時に「今日」の扱いを更新するための基準日。
    @State private var today = Date()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum DayOrigin: Equatable {
        case feed
        case calendar
    }

    private enum Surface: Equatable {
        case feed
        case calendar
        case day(id: String, origin: DayOrigin)
    }

    var body: some View {
        ZStack {
            RollTheme.ground.ignoresSafeArea()

            switch surface {
            case .feed:
                feed.transition(.opacity)
            case .calendar:
                calendar.transition(.opacity)
            case .day(let id, let origin):
                day(id: id, origin: origin)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: surface)
        .onChange(of: surface) { _, newValue in
            // 一覧以外へ進んだら、半分の高さでは狭いので全画面にする。
            if newValue != .feed {
                onExpand()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let progress = state.exportProgress {
                CameraRollExportProgressPanel(
                    progress: progress,
                    subject: state.exportSubject,
                    thumbnailProvider: thumbnailProvider,
                    onCancel: onCancelExport
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let completion = state.exportCompletion {
                CameraRollExportCompletionCard(
                    completion: completion,
                    thumbnailProvider: thumbnailProvider,
                    onShare: onShareExport,
                    onDismiss: onDismissExport
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.exportProgress != nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.exportCompletion?.id)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSCalendarDayChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            today = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = Date()
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
        .onChange(of: state.days.map(\.id)) { oldIDs, ids in
            // 開いていた日がライブラリから消えたら（最後の1本を削除した時など）、元の画面へ戻す。
            // カレンダーから開いてまだ読み込み中の日は、消えたのではないので戻さない。
            if case .day(let id, let origin) = surface, oldIDs.contains(id), !ids.contains(id) {
                surface = origin == .feed ? .feed : .calendar
            }
        }
    }

    private var feed: some View {
        VStack(spacing: 0) {
            feedHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if state.showsInitialLoading {
                        CameraRollLoadingView()
                    } else {
                        let calendar = Calendar.current
                        let todayItem = state.days.first.flatMap {
                            calendar.isDate($0.date, inSameDayAs: today) ? $0 : nil
                        }

                        if let hero = todayItem {
                            CameraRollHeroDay(
                                item: hero,
                                isToday: true,
                                thumbnailProvider: thumbnailProvider,
                                onOpen: { openDay(hero.id, origin: .feed) },
                                onClipTap: onClipTap,
                                onPlay: { onPlayDay(hero.id) },
                                onExport: { onExportDay(hero.id) },
                                onCancelExport: onCancelExport
                            )
                            .id(hero.id)
                            .onAppear { onLoadMore(hero.id) }
                        } else {
                            // 今日まだ撮っていない（またはまだ1本もない）。空白の今日を一番上に置く。
                            CameraRollTodayEmptyHero(today: today, onCapture: onClose)
                                .id("today-empty")
                        }

                        let rest: [CameraRollFeedEntry] = todayItem == nil
                            ? CameraRollFeedPresenter.entries(for: state.days, leadingFrom: today, calendar: calendar)
                            : Array(CameraRollFeedPresenter.entries(for: state.days, calendar: calendar).dropFirst())

                        if !rest.isEmpty {
                            divider
                                .padding(.horizontal, RollTheme.pagePadding)

                            Text("EARLIER")
                                .rollMono(10, .semibold)
                                .tracking(1.2)
                                .foregroundStyle(RollTheme.secondary)
                                .padding(.horizontal, RollTheme.pagePadding)
                                .padding(.top, 16)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(rest) { entry in
                                feedRow(entry)
                                    .padding(.horizontal, RollTheme.pagePadding)
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
        }
        .background(RollTheme.ground)
    }

    @ViewBuilder
    private func feedRow(_ entry: CameraRollFeedEntry) -> some View {
        switch entry {
        case .day(let day):
            CameraRollDayRow(
                item: day,
                thumbnailProvider: thumbnailProvider,
                onOpen: { openDay(day.id, origin: .feed) }
            )
            .id(day.id)
            .onAppear { onLoadMore(day.id) }
        case .noRecord(_, let label):
            CameraRollNoRecordRow(label: label)
        }
    }

    /// シートは取っ手と下へのスワイプで閉じるので、閉じるボタンは置かない。
    /// 中央上はシステムの取っ手が重なるため、ロゴは左に寄せる。
    private var feedHeader: some View {
        HStack(spacing: 0) {
            Text(AppIdentity.brandName.uppercased())
                .rollMono(13, .semibold)
                .tracking(1.0)
                .foregroundStyle(RollTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            headerButton(
                systemName: "calendar",
                label: "カレンダーを開く",
                identifier: "navigation.calendar",
                action: { surface = .calendar }
            )
        }
        .padding(.leading, RollTheme.pagePadding)
        .padding(.trailing, 8)
        .frame(height: 44)
        .padding(.top, 8)
        .background(RollTheme.ground)
        // VoiceOverの「戻る」ジェスチャー（2本指のZ）でも撮影へ戻れるようにする。
        .accessibilityAction(.escape, onClose)
    }

    private var calendar: some View {
        VStack(spacing: 0) {
            calendarHeader
            divider
            CameraRollCalendarView(
                days: state.calendarDays,
                displayedMonth: $displayedCalendarMonth,
                thumbnailProvider: thumbnailProvider,
                onOpenDay: { id in
                    openDay(id, origin: .calendar)
                    loadDay(id)
                }
            )
        }
    }

    private var calendarHeader: some View {
        ZStack {
            Text(L10n.text("カレンダー"))
                .rollText(15, .bold)
                .foregroundStyle(RollTheme.ink)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                headerButton(
                    systemName: "chevron.left",
                    label: "記録へ戻る",
                    identifier: "calendar.back",
                    action: { surface = .feed }
                )
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(RollTheme.ground)
    }

    private func headerButton(
        systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(RollTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(L10n.text(label))
        .accessibilityIdentifier(identifier)
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
                    onCancelExport: onCancelExport,
                    onDeleteClip: onDeleteClip
                )
            }
            .background(RollTheme.ground)
        } else if failedDayIDs.contains(id) {
            VStack(spacing: 0) {
                dayLoadingHeader(origin: origin)
                divider
                dayLoadFailure(id: id)
                Spacer()
            }
            .background(RollTheme.ground)
        } else {
            VStack(spacing: 0) {
                dayLoadingHeader(origin: origin)
                divider
                CameraRollLoadingView()
                Spacer()
            }
            .background(RollTheme.ground)
        }
    }

    private func dayLoadFailure(id: String) -> some View {
        VStack(spacing: 14) {
            Text(L10n.text("この日の動画を読み込めませんでした"))
                .rollText(15, .bold)
                .foregroundStyle(RollTheme.ink)
            Text(L10n.text("動画が削除されたか、iCloudから取得できていない可能性があります。"))
                .rollText(12)
                .foregroundStyle(RollTheme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                loadDay(id)
            } label: {
                Label(L10n.text("もう一度"), systemImage: "arrow.clockwise")
                    .rollText(14, .semibold)
                    .foregroundStyle(RollTheme.ground)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(RollTheme.ink, in: Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
            .accessibilityIdentifier("library.day.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, RollTheme.pagePadding)
        .padding(.vertical, 56)
    }

    private func loadDay(_ id: String) {
        failedDayIDs.remove(id)
        Task { @MainActor in
            let loaded = await onLoadDay(id)
            if !loaded {
                failedDayIDs.insert(id)
            }
        }
    }

    private func dayHeader(item: CameraRollDayItem, origin: DayOrigin) -> some View {
        ZStack {
            VStack(spacing: 2) {
                Text("\(item.stampDateText) \(item.stampWeekdayText)")
                    .rollMono(15, .semibold)
                    .foregroundStyle(RollTheme.ink)
                Text(verbatim: "\(CameraRollStampFormat.clips(item.clipCount)) · \(item.durationText)")
                    .rollMono(10)
                    .foregroundStyle(RollTheme.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("%@、%@、%@", item.dateText, item.summaryText, item.durationText))
            .accessibilityAddTraits(.isHeader)

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
                        .foregroundStyle(RollTheme.ink)
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
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RollTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(backLabel(for: origin))
        .accessibilityIdentifier(backIdentifier(for: origin))
    }

    private var divider: some View {
        Rectangle()
            .fill(RollTheme.hairline)
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
        }
    }

    private func backIdentifier(for origin: DayOrigin) -> String {
        switch origin {
        case .feed:
            return "library.day.back"
        case .calendar:
            return "calendar.day.back"
        }
    }

    private func dayItem(id: String) -> CameraRollDayItem? {
        state.days.first(where: { $0.id == id })
    }
}
