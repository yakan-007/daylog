import Combine
import Photos
import PhotosUI
import UIKit

@MainActor
final class LibraryFeatureViewModel: ObservableObject {
    @Published var isPresentingLibrary = false
    @Published private var sections: [DaySection] = []
    @Published private var calendarSummaries: [DayCalendarSummary] = []
    @Published private var isRefreshing = false
    @Published var latestThumbnail: UIImage?
    @Published var playbackRoute: PlaybackRoute?
    @Published private var activeExportTarget: LibraryExportTarget?
    @Published private var exportProgress: DayVideoExportProgress?
    @Published var exportShareItem: ExportShareItem?
    /// 書き出しが終わり、完成カードで共有を待っている動画。
    @Published private(set) var exportCompletion: CameraRollExportCompletion?
    @Published var exportFailure: VlogishFailure?
    @Published private(set) var exportFailureDetail: String?
    @Published var exportConfirmation: DayVideoExportConfirmation?
    @Published var libraryFailure: VlogishFailure?
    @Published var isLimitedLibraryNoticePresented = false
    @Published var stampEditorRoute: VideoStampEditorRoute?
    /// 動画を外す・削除するのに失敗した時のアラート。
    @Published var clipRemovalFailure: ClipRemovalFailure?

    private let useCase: VlogishLibraryUseCase
    private let repository: VlogishPhotoLibraryRepository
    private let thumbnailService: ThumbnailService
    private let exportService: LibraryVideoExportService
    private let stampEditingService: VideoStampEditingService
    private var observationTask: Task<Void, Never>?
    private var hasLoaded = false
    private var refreshInFlight = false
    /// 更新中に届いた更新要求。捨てずに、今の更新が終わったらもう一度だけ走らせる。
    private var pendingRefresh: (requestAuthorization: Bool, reportsFailure: Bool)?
    private var isLoadingMore = false
    private var lastLoadedCursor: String?
    /// 一覧を作り直すたびに増える。追加読み込みの結果が、作り直した後の一覧に混ざらないようにする。
    private var libraryGeneration = 0
    private var failedExportTarget: LibraryExportTarget?
    private var exportTask: Task<Void, Never>?
    private var userRequestedExportCancellation = false
    private var hasShownLimitedLibraryNotice = false

    init(
        useCase: VlogishLibraryUseCase,
        repository: VlogishPhotoLibraryRepository,
        thumbnailService: ThumbnailService,
        exportService: LibraryVideoExportService,
        stampEditingService: VideoStampEditingService
    ) {
        self.useCase = useCase
        self.repository = repository
        self.thumbnailService = thumbnailService
        self.exportService = exportService
        self.stampEditingService = stampEditingService
    }

    deinit {
        observationTask?.cancel()
        exportTask?.cancel()
    }

    var screenState: CameraRollScreenState {
        var state = CameraRollPresenter.makeState(
            sections: sections,
            calendarSummaries: calendarSummaries,
            isRefreshing: isRefreshing,
            exportingDayKey: activeExportTarget?.exportingDayKey,
            exportingClipID: activeExportTarget?.exportingClipID,
            exportProgress: exportProgress
        )
        state.exportSubject = activeExportTarget.flatMap(exportSubject(for:))
        state.exportCompletion = exportCompletion
        return state
    }

    var thumbnailProvider: LibraryThumbnailProviding {
        thumbnailService
    }

    var hasActiveExport: Bool {
        activeExportTarget != nil
    }

    func openLibrary() {
        guard !isPresentingLibrary else { return }
        isPresentingLibrary = true
        Task {
            await refreshLibrary(
                requestAuthorizationIfNeeded: true,
                reportsFailure: true
            )
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        Task {
            let cached = await useCase.loadInitialSections()
            replaceSections(with: cached)
            await reloadCalendarSummaries()
            refreshLatestThumbnail(preferredAssetIdentifier: cached.first?.clips.first?.assetLocalIdentifier)
            await refreshLibrary(
                requestAuthorizationIfNeeded: false,
                reportsFailure: false
            )
            observeChanges()
        }
    }

    func refresh() async {
        await refreshLibrary(
            requestAuthorizationIfNeeded: true,
            reportsFailure: true
        )
    }

    private func refreshLibrary(
        requestAuthorizationIfNeeded: Bool,
        reportsFailure: Bool
    ) async {
        guard !refreshInFlight else {
            // 削除の通知と削除後の手動更新が重なっても、最新の状態を必ず読み直す。
            pendingRefresh = (
                requestAuthorization: (pendingRefresh?.requestAuthorization ?? false)
                    || requestAuthorizationIfNeeded,
                reportsFailure: (pendingRefresh?.reportsFailure ?? false) || reportsFailure
            )
            await waitForRefreshToFinish()
            return
        }
        refreshInFlight = true
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshInFlight = false
        }

        var request = (
            requestAuthorization: requestAuthorizationIfNeeded,
            reportsFailure: reportsFailure
        )
        while true {
            await performRefresh(
                requestAuthorizationIfNeeded: request.requestAuthorization,
                reportsFailure: request.reportsFailure
            )
            guard let next = pendingRefresh else { break }
            pendingRefresh = nil
            request = next
        }
    }

    private func performRefresh(
        requestAuthorizationIfNeeded: Bool,
        reportsFailure: Bool
    ) async {
        do {
            let refreshed = try await useCase.refresh(
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
            replaceSections(with: refreshed)
            await reloadCalendarSummaries()
            refreshLatestThumbnail(preferredAssetIdentifier: refreshed.first?.clips.first?.assetLocalIdentifier)
            libraryFailure = nil
            presentLimitedLibraryNoticeIfNeeded()
        } catch {
            AppLog.permission.warning(
                "library.refresh.fail reason=\(error.localizedDescription, privacy: .private)"
            )
            if reportsFailure || shouldReportSilentRefreshFailure(error) {
                libraryFailure = VlogishFailureMapper.libraryFailure(from: error)
            }
        }
    }

    func loadMoreIfNeeded(dayID: String) {
        guard sections.last?.id == dayID else { return }
        guard !refreshInFlight, !isLoadingMore else { return }
        guard let cursor = sections.last?.dayKey, cursor != lastLoadedCursor else { return }

        isLoadingMore = true
        lastLoadedCursor = cursor
        let generation = libraryGeneration

        Task { @MainActor in
            let moreSections = await useCase.loadMoreSections(after: cursor)
            isLoadingMore = false
            // 読み込み中に更新で一覧が作り直されていたら、古い結果は捨てる
            // （写真アプリで消した動画や古い集計が戻ってこないように）。
            guard generation == libraryGeneration else { return }
            appendSections(moreSections)
        }
    }

    func handleCaptureSaved(preferredAssetIdentifier: String?) async {
        if preferredAssetIdentifier != nil {
            await waitForRefreshToFinish()
        }
        if let preferredAssetIdentifier,
           let updated = await useCase.registerSavedClip(
            localIdentifier: preferredAssetIdentifier
           ) {
            replaceSections(with: updated)
            await reloadCalendarSummaries()
            refreshLatestThumbnail(
                preferredAssetIdentifier: preferredAssetIdentifier
            )
            return
        }

        await refreshLibrary(
            requestAuthorizationIfNeeded: false,
            reportsFailure: true
        )
        refreshLatestThumbnail(
            preferredAssetIdentifier: sections.first?.clips.first?.assetLocalIdentifier
        )
    }

    private func waitForRefreshToFinish() async {
        while refreshInFlight {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// 撮影画面のミニ時間軸用。最新の日の撮影時刻を渡し、「今日」かどうかは描画側で判定する
    /// （日付をまたいだ直後に、前日の記録を今日として描かないため）。
    var todayTimeline: CaptureTodayTimeline {
        guard let latest = sections.max(by: { $0.date < $1.date }) else {
            return CaptureTodayTimeline()
        }
        return CaptureTodayTimeline(clipDates: latest.clips.map(\.capturedAt))
    }

    func playClip(id: String) {
        guard !hasActiveExport else { return }
        guard let context = makeLibraryClipPlaybackContext(selectedClipId: id) else { return }
        // 記録シートは閉じない。再生はその上に重なり、閉じると同じ場所へ戻る。
        playbackRoute = PlaybackRoute(context: context)
    }

    /// 動画を Vlogish から外す、または写真からも削除する。
    /// どちらも編集内容とスタンプ設定は片付ける（写真アプリでアルバムに戻した時は、編集なしで戻る）。
    func removeClip(id: String, _ removal: ClipRemoval) {
        guard !hasActiveExport else { return }
        Task { @MainActor in
            do {
                switch removal {
                case .removeFromVlogish:
                    try await repository.removeFromAlbum(localIdentifier: id)
                case .deleteFromPhotos:
                    try await repository.deleteAsset(localIdentifier: id)
                }
                await stampEditingService.forgetClip(assetLocalIdentifier: id)
                await refreshLibrary(requestAuthorizationIfNeeded: false, reportsFailure: false)
            } catch let error as PHPhotosError where error.code == .userCancelled {
                // iOS の確認でキャンセルした。何もしない。
            } catch {
                AppLog.storage.error(
                    "clip.remove.fail removal=\(String(describing: removal), privacy: .public) reason=\(error.localizedDescription, privacy: .private)"
                )
                clipRemovalFailure = ClipRemovalFailure(
                    title: removal == .removeFromVlogish
                        ? L10n.text("Vlogishから外せませんでした")
                        : L10n.text("動画を削除できませんでした"),
                    message: error.localizedDescription
                )
            }
        }
    }

    func editStamp(id: String) {
        guard !hasActiveExport else { return }
        stampEditorRoute = VideoStampEditorRoute(assetLocalIdentifier: id)
    }

    func makeStampEditorViewModel(
        route: VideoStampEditorRoute
    ) -> VideoStampEditorViewModel {
        VideoStampEditorViewModel(
            assetLocalIdentifier: route.assetLocalIdentifier,
            service: stampEditingService
        )
    }

    func handleStampEditSaved() {
        stampEditorRoute = nil
        Task { await refresh() }
    }

    func playDay(id: String) {
        guard !hasActiveExport else { return }
        guard let section = section(id: id) else { return }
        let day = makePlaybackDay(from: section)
        guard !day.items.isEmpty else { return }
        playbackRoute = PlaybackRoute(context: LibraryClipPlaybackContext(
            days: [day],
            initialDayIndex: 0,
            initialClipIndex: 0,
            mode: .continuousDay
        ))
    }

    /// カレンダーから開いた日を読み込む。読めた（または既にある）時は true。
    @discardableResult
    func loadDayIfNeeded(id: String) async -> Bool {
        if section(id: id) != nil { return true }
        let generation = libraryGeneration
        guard let loaded = await useCase.loadDaySection(dayKey: id) else {
            return section(id: id) != nil
        }
        // 読み込み中に一覧が作り直されていたら、古い結果は混ぜない（作り直した側に任せる）。
        guard generation == libraryGeneration else { return section(id: id) != nil }
        appendSections([loaded])
        return true
    }

    func clearPlaybackRoute() {
        playbackRoute = nil
    }

    func exportDay(id: String) {
        guard let section = section(id: id) else { return }
        guard !hasActiveExport else { return }
        let assessment = DayVideoExportPolicy.assess(
            clipCount: section.clipCount,
            totalDuration: section.totalDuration
        )
        guard !assessment.requiresConfirmation else {
            exportConfirmation = DayVideoExportConfirmation(
                dayID: id,
                assessment: assessment
            )
            return
        }
        startExport(section)
    }

    func confirmExport(_ confirmation: DayVideoExportConfirmation) {
        guard confirmation.assessment.canExport,
              let section = section(id: confirmation.dayID) else {
            exportConfirmation = nil
            return
        }
        exportConfirmation = nil
        startExport(section)
    }

    func cancelExportConfirmation() {
        exportConfirmation = nil
    }

    private func startExport(_ section: DaySection) {
        let target = LibraryExportTarget.day(
            id: section.id,
            dayKey: section.dayKey
        )
        beginExport(
            target,
            initialPhase: .locatingAssets(total: section.clips.count)
        )

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 先に開始状態を描画してからPhotoKitへ問い合わせる。
                await Task.yield()
                try Task.checkCancellation()
                AppLog.export.info(
                    "day_export.resolve.begin clips=\(section.clips.count, privacy: .public)"
                )
                let resolved = resolvedAssets(for: section)
                AppLog.export.info(
                    "day_export.resolve.end expected=\(section.clips.count, privacy: .public) actual=\(resolved.count, privacy: .public)"
                )
                guard DayVideoExportPolicy.hasCompleteAssetSet(
                    expected: section.clips.count,
                    actual: resolved.count
                ) else {
                    if resolved.isEmpty {
                        throw DayVideoExporterError.noAssets
                    }
                    throw DayVideoExporterError.assetCountMismatch(
                        expected: section.clips.count,
                        actual: resolved.count
                    )
                }

                let items = resolved.map {
                    LibraryExportItem(asset: $0.asset, capturedAt: $0.capturedAt)
                }
                let url = try await exportService.export(
                    items: items,
                    outputKey: section.dayKey,
                    progress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self,
                                  self.activeExportTarget == target else { return }
                            self.exportProgress = progress
                        }
                    }
                )
                guard !Task.isCancelled else {
                    exportService.discardExport(at: url)
                    throw CancellationError()
                }
                completeExport(at: url, target: target)
            } catch {
                recordExportFailure(error, target: target)
                if shouldRefreshLibraryAfterExportFailure(error) {
                    await refreshLibrary(
                        requestAuthorizationIfNeeded: true,
                        reportsFailure: false
                    )
                }
            }
            exportTask = nil
        }
    }

    func exportClip(id: String) {
        guard !hasActiveExport else { return }
        guard let clip = clipSummary(id: id),
              let asset = repository.assets(localIdentifiers: [id]).first else {
            exportFailure = .libraryAssetUnavailable
            exportFailureDetail = VlogishFailure.libraryAssetUnavailable.message
            failedExportTarget = .clip(id: id)
            return
        }

        let target = LibraryExportTarget.clip(id: id)
        beginExport(target, initialPhase: .preparing)

        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await exportService.export(
                    items: [LibraryExportItem(asset: asset, capturedAt: clip.capturedAt)],
                    outputKey: "clip-\(clip.dayKey)",
                    progress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self,
                                  self.activeExportTarget == target else { return }
                            self.exportProgress = progress
                        }
                    }
                )
                guard !Task.isCancelled else {
                    exportService.discardExport(at: url)
                    throw CancellationError()
                }
                completeExport(at: url, target: target)
            } catch {
                recordExportFailure(error, target: target)
            }
            exportTask = nil
        }
    }

    func cancelExport() {
        guard hasActiveExport else { return }
        userRequestedExportCancellation = true
        if let current = exportProgress {
            exportProgress = DayVideoExportProgress(
                fraction: current.fraction,
                phase: .cancelling
            )
        }
        exportTask?.cancel()
    }

    /// 完成カードの「共有・保存」。カードを閉じて共有画面を出す（ファイルは共有画面を閉じた時に片付ける）。
    func shareCompletedExport() {
        guard let completion = exportCompletion else { return }
        exportCompletion = nil
        exportShareItem = ExportShareItem(url: completion.url)
    }

    /// 完成カードの「閉じる」。共有しないので、書き出したファイルを片付ける。
    func dismissCompletedExport() {
        guard let completion = exportCompletion else { return }
        exportCompletion = nil
        exportService.discardExport(at: completion.url)
    }

    func clearExportShareItem() {
        if let url = exportShareItem?.url {
            exportService.discardExport(at: url)
        }
        exportShareItem = nil
    }

    func clearExportFailure() {
        exportFailure = nil
        exportFailureDetail = nil
    }

    func retryExport() {
        guard !hasActiveExport else {
            exportFailure = nil
            exportFailureDetail = nil
            return
        }
        exportFailure = nil
        exportFailureDetail = nil
        switch failedExportTarget {
        case .day(let id, _):
            guard let section = section(id: id) else { return }
            startExport(section)
        case .clip(let id):
            exportClip(id: id)
        case nil:
            return
        }
    }

    func retryLibraryLoad() {
        libraryFailure = nil
        Task { await refresh() }
    }

    func clearLibraryFailure() {
        libraryFailure = nil
    }

    private func beginExport(
        _ target: LibraryExportTarget,
        initialPhase: DayVideoExportPhase
    ) {
        // 前の完成カードが残っていたら片付けてから始める。
        dismissCompletedExport()
        activeExportTarget = target
        exportProgress = DayVideoExportProgress(
            fraction: 0,
            phase: initialPhase
        )
        exportFailure = nil
        exportFailureDetail = nil
        failedExportTarget = nil
        userRequestedExportCancellation = false
    }

    private func completeExport(
        at url: URL,
        target: LibraryExportTarget
    ) {
        guard activeExportTarget == target else {
            exportService.discardExport(at: url)
            return
        }
        if let subject = exportSubject(for: target) {
            exportCompletion = CameraRollExportCompletion(url: url, subject: subject)
        } else {
            // 対象が一覧から消えていた時は、カードを出さずにそのまま共有へ。
            exportShareItem = ExportShareItem(url: url)
        }
        activeExportTarget = nil
        exportProgress = nil
        failedExportTarget = nil
        userRequestedExportCancellation = false
    }

    private func recordExportFailure(
        _ error: Error,
        target: LibraryExportTarget
    ) {
        guard activeExportTarget == target else { return }
        let failure = VlogishFailureMapper.exportFailure(from: error)
        let suppressFailure = userRequestedExportCancellation
            && failure == .exportCancelled
        exportFailure = suppressFailure ? nil : failure
        exportFailureDetail = suppressFailure
            ? nil
            : exportFailureDetail(for: error, failure: failure)
        activeExportTarget = nil
        exportProgress = nil
        failedExportTarget = exportFailure == nil ? nil : target
        userRequestedExportCancellation = false
    }

    private func shouldRefreshLibraryAfterExportFailure(_ error: Error) -> Bool {
        guard let exporterError = error as? DayVideoExporterError else {
            return false
        }
        switch exporterError {
        case .noAssets, .assetCountMismatch:
            return true
        default:
            return false
        }
    }

    private func exportFailureDetail(
        for error: Error,
        failure: VlogishFailure
    ) -> String {
        let detail = VlogishFailureMapper.exportFailureDetail(from: error)
        guard failure == .storageUnavailable,
              let availableCapacity = availableStorageCapacity else {
            return detail
        }
        let formatted = ByteCountFormatter.string(
            fromByteCount: availableCapacity,
            countStyle: .file
        )
        return L10n.text("%@\n現在の空き容量: 約%@", detail, formatted)
    }

    private var availableStorageCapacity: Int64? {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let values = try? homeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ),
        let capacity = values.volumeAvailableCapacityForImportantUsage,
        capacity >= 0 else {
            return nil
        }
        return capacity
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func manageLimitedLibraryAccess() {
        isLimitedLibraryNoticePresented = false
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited,
              let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootViewController = windowScene.windows
                .first(where: \.isKeyWindow)?
                .rootViewController else {
            openSystemSettings()
            return
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(
            from: topViewController(from: rootViewController)
        )
    }

    private func observeChanges() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in useCase.observeLibraryChanges() {
                await refresh()
            }
        }
    }

    private func replaceSections(with sections: [DaySection]) {
        libraryGeneration += 1
        self.sections = sections.sorted(by: { $0.date > $1.date })
        lastLoadedCursor = nil
    }

    private func appendSections(_ sections: [DaySection]) {
        guard !sections.isEmpty else { return }
        // 既に読み込み済みの日が再度届いても落ちないよう、新しい方で上書きする。
        let merged = Dictionary((self.sections + sections).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        self.sections = merged.values.sorted(by: { $0.date > $1.date })
    }

    private func reloadCalendarSummaries() async {
        calendarSummaries = await useCase.loadCalendarSummaries()
    }

    private func refreshLatestThumbnail(preferredAssetIdentifier: String?) {
        guard let preferredAssetIdentifier else {
            latestThumbnail = nil
            return
        }
        thumbnailService.requestThumbnail(
            assetLocalIdentifier: preferredAssetIdentifier,
            targetSize: CGSize(width: 180, height: 180)
        ) { [weak self] image in
            self?.latestThumbnail = image
        }
    }

    private func makeLibraryClipPlaybackContext(selectedClipId: String) -> LibraryClipPlaybackContext? {
        for section in sections {
            let day = makePlaybackDay(from: section)
            if let clipIndex = day.items.firstIndex(where: { $0.assetLocalIdentifier == selectedClipId }) {
                return LibraryClipPlaybackContext(
                    days: [day],
                    initialDayIndex: 0,
                    initialClipIndex: clipIndex
                )
            }
        }

        return nil
    }

    private func makePlaybackDay(from section: DaySection) -> LibraryClipPlaybackDay {
        return LibraryClipPlaybackDay(
            dayKey: section.dayKey,
            displayDateText: VlogishFormatters.dayTitleFormatter.string(from: section.date),
            weekdayText: VlogishFormatters.weekdayFormatter.string(from: section.date),
            totalDuration: section.totalDuration,
            clipCount: section.clipCount,
            items: section.chronologicalClips.map(PlaybackClipItem.init(clip:))
        )
    }

    private func section(id: String) -> DaySection? {
        sections.first(where: { $0.id == id })
    }

    private func clipSummary(id: String) -> ClipSummary? {
        sections.lazy.flatMap(\.clips).first { $0.assetLocalIdentifier == id }
    }

    private func exportSubject(for target: LibraryExportTarget) -> CameraRollExportSubject? {
        switch target {
        case .day(let id, _):
            guard let section = section(id: id) else { return nil }
            return CameraRollExportSubject(
                origin: .day(id: id),
                title: Self.stampTitle(for: section.date),
                clipCount: section.clipCount,
                durationText: VlogishFormatters.durationLabel(section.totalDuration),
                clipIDs: section.chronologicalClips.map(\.assetLocalIdentifier)
            )
        case .clip(let id):
            guard let clip = clipSummary(id: id) else { return nil }
            return CameraRollExportSubject(
                origin: .clip(id: id),
                title: "\(Self.stampTitle(for: clip.capturedAt)) \(CameraRollStampFormat.hourMinute.string(from: clip.capturedAt))",
                clipCount: 1,
                durationText: VlogishFormatters.durationLabel(clip.duration),
                clipIDs: [id]
            )
        }
    }

    private static func stampTitle(for date: Date) -> String {
        "\(CameraRollStampFormat.date.string(from: date)) \(CameraRollStampFormat.weekday.string(from: date).uppercased())"
    }

    private func resolvedAssets(
        for section: DaySection
    ) -> [(asset: PHAsset, capturedAt: Date)] {
        let fetched = repository.assets(
            localIdentifiers: section.clips.map(\.assetLocalIdentifier)
        )
        let assetsByIdentifier = Dictionary(
            fetched.map { ($0.localIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return section.chronologicalClips
            .compactMap { clip in
                assetsByIdentifier[clip.assetLocalIdentifier].map {
                    (asset: $0, capturedAt: clip.capturedAt)
                }
            }
    }

    private func presentLimitedLibraryNoticeIfNeeded() {
        guard !hasShownLimitedLibraryNotice,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return }
        hasShownLimitedLibraryNotice = true
        isLimitedLibraryNoticePresented = true
    }

    private func shouldReportSilentRefreshFailure(_ error: Error) -> Bool {
        guard let repositoryError = error as? PhotoLibraryRepositoryError else {
            return true
        }
        if case .authorizationNotDetermined = repositoryError {
            return false
        }
        return true
    }

    private func topViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = root as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return root
    }
}

struct ClipRemovalFailure: Equatable {
    let title: String
    let message: String
}
