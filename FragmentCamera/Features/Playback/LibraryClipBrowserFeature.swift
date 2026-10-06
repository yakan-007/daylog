@preconcurrency import AVFoundation
import Combine
import OSLog
import Photos

@MainActor
final class LibraryClipBrowserViewModel: ObservableObject {
    private struct Selection {
        let dayIndex: Int
        let clipIndex: Int
    }

    @Published private var selection: Selection
    @Published private(set) var isLoading = false
    @Published private(set) var didFailToLoad = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var currentClipProgress: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var currentStampContext: VideoPostProcessContext?
    @Published private(set) var currentTextOverlays: [VlogResolvedTextOverlay] = []
    @Published private(set) var currentVideoAspectRatio: CGFloat = 9.0 / 16.0

    let days: [LibraryClipPlaybackDay]
    let player = AVQueuePlayer()

    private let repository: PlaybackAssetRepository
    private let mode: ClipPlaybackMode
    private let stampContextService: VideoStampContextService
    private let clipEditStore: VlogClipEditStore
    private let settingsStore: VlogishSettingsStore
    private var currentRequestID: PHImageRequestID?
    private var loadingAssetIdentifier: String?
    private var prefetchRequestIDs: [PHImageRequestID] = []
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackProgressObserver: Any?
    private var loadGeneration = 0
    private var isPlaybackActive = false
    private var pendingStampContext: VideoPostProcessContext?
    private var pendingTextOverlays: [VlogResolvedTextOverlay] = []
    private var isPlayerReadyForCurrentAsset = false
    private var navigationTask: Task<Void, Never>?
    private var volumeFadeTask: Task<Void, Never>?
    private var playerPreparationTask: Task<Void, Never>?
    private var queuedNextRequestID: PHImageRequestID?
    private var queuedNextAssetIdentifier: String?
    private var queuedNextPlayerItem: AVPlayerItem?
    private var queuedNextStampContext: VideoPostProcessContext?
    private var queuedNextTextOverlays: [VlogResolvedTextOverlay] = []
    private var queuedNextAspectRatio: CGFloat?

    private static let transitionFadeOutDuration: TimeInterval = 0.12
    private static let transitionFadeInDuration: TimeInterval = 0.16

    private enum LoadAttempt: Equatable {
        case fast
        case reliable

        var deliveryMode: PHVideoRequestOptionsDeliveryMode {
            switch self {
            case .fast: return .fastFormat
            case .reliable: return .automatic
            }
        }

        var timeout: TimeInterval {
            switch self {
            case .fast: return 4
            case .reliable: return 20
            }
        }
    }

    init(
        context: LibraryClipPlaybackContext,
        repository: PlaybackAssetRepository,
        stampContextService: VideoStampContextService = VideoStampContextService(),
        clipEditStore: VlogClipEditStore = VlogClipEditStore(),
        settingsStore: VlogishSettingsStore = VlogishSettingsStore()
    ) {
        precondition(
            !context.days.isEmpty && context.days.allSatisfy { !$0.items.isEmpty },
            "Clip browser requires at least one playable clip per day."
        )
        self.days = context.days
        self.repository = repository
        self.mode = context.mode
        self.stampContextService = stampContextService
        self.clipEditStore = clipEditStore
        self.settingsStore = settingsStore
        self.player.actionAtItemEnd = context.mode == .continuousDay ? .advance : .pause
        self.player.automaticallyWaitsToMinimizeStalling = true

        let resolvedDayIndex = ClipBrowserNavigator.resolvedIndex(
            context.initialDayIndex,
            count: context.days.count
        )
        let resolvedClipIndex = ClipBrowserNavigator.resolvedClipIndex(
            context.initialClipIndex,
            in: context.days[resolvedDayIndex]
        )

        self.selection = Selection(
            dayIndex: resolvedDayIndex,
            clipIndex: resolvedClipIndex
        )
    }

    /// 初回要求が画面遷移中に破棄されないよう、表示確定後に開始する。
    func startPlayback() {
        guard !isPlaybackActive else { return }
        isPlaybackActive = true
        observePlaybackProgress()
        loadCurrentItem()
    }

    func stopPlayback() {
        isPlaybackActive = false
        loadGeneration += 1
        navigationTask?.cancel()
        navigationTask = nil
        volumeFadeTask?.cancel()
        volumeFadeTask = nil
        playerPreparationTask?.cancel()
        playerPreparationTask = nil
        AssetPlaybackLoader.shared.cancel(currentRequestID)
        currentRequestID = nil
        cancelQueuedNext(removeFromPlayer: false)
        loadingAssetIdentifier = nil
        isLoading = false
        didFailToLoad = false
        currentStampContext = nil
        currentTextOverlays = []
        pendingStampContext = nil
        pendingTextOverlays = []
        isPlayerReadyForCurrentAsset = false
        isTransitioning = false
        currentClipProgress = 0
        isPaused = false
        player.pause()
        player.volume = 1
        player.removeAllItems()
        cancelPrefetchRequests()
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let playbackProgressObserver {
            player.removeTimeObserver(playbackProgressObserver)
            self.playbackProgressObserver = nil
        }
    }

    var screenState: ClipBrowserScreenState {
        ClipBrowserPresenter.makeState(
            day: currentDay,
            item: currentItem,
            clipIndex: currentClipIndex,
            canRetreatClip: canRetreatClip,
            canAdvanceClip: canAdvanceClip,
            canRetreatDay: canRetreatDay,
            canAdvanceDay: canAdvanceDay,
            isLoading: isLoading,
            didFailToLoad: didFailToLoad,
            isTransitioning: isTransitioning,
            currentClipProgress: currentClipProgress,
            isPaused: isPaused,
            stampContext: currentStampContext,
            textOverlays: currentTextOverlays,
            videoAspectRatio: currentVideoAspectRatio
        )
    }

    var currentDayIndex: Int { selection.dayIndex }
    var currentClipIndex: Int { selection.clipIndex }
    var currentDay: LibraryClipPlaybackDay { days[currentDayIndex] }
    var currentItem: PlaybackClipItem { currentDay.items[currentClipIndex] }

    var canAdvanceClip: Bool {
        currentClipIndex + 1 < currentDay.items.count
    }

    var canRetreatClip: Bool {
        currentClipIndex > 0
    }

    var canAdvanceDay: Bool {
        currentDayIndex + 1 < days.count
    }

    var canRetreatDay: Bool {
        currentDayIndex > 0
    }

    func advanceClip() {
        guard canAdvanceClip else { return }
        transition(to: Selection(
            dayIndex: currentDayIndex,
            clipIndex: currentClipIndex + 1
        ))
    }

    func retreatClip() {
        guard canRetreatClip else { return }
        transition(to: Selection(
            dayIndex: currentDayIndex,
            clipIndex: currentClipIndex - 1
        ))
    }

    func advanceDay() {
        guard canAdvanceDay else { return }
        let targetDayIndex = currentDayIndex + 1
        let targetClipIndex = ClipBrowserNavigator.closestClipIndex(
            to: currentItem.capturedAt,
            in: days[targetDayIndex]
        )
        transition(to: Selection(
            dayIndex: targetDayIndex,
            clipIndex: targetClipIndex
        ))
    }

    func retreatDay() {
        guard canRetreatDay else { return }
        let targetDayIndex = currentDayIndex - 1
        let targetClipIndex = ClipBrowserNavigator.closestClipIndex(
            to: currentItem.capturedAt,
            in: days[targetDayIndex]
        )
        transition(to: Selection(
            dayIndex: targetDayIndex,
            clipIndex: targetClipIndex
        ))
    }

    func retryPlayback() {
        guard isPlaybackActive else { return }
        loadCurrentItem()
    }

    func togglePlayback() {
        guard isPlaybackActive, !isLoading, !didFailToLoad else { return }
        if isPaused {
            if player.currentItem == nil {
                loadCurrentItem()
                return
            }
            if currentClipProgress >= 0.995 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                currentClipProgress = 0
            }
            player.playImmediately(atRate: 1)
            isPaused = false
        } else {
            player.pause()
            isPaused = true
        }
    }

    private func prefetchNeighbors() {
        cancelPrefetchRequests()
        prefetchRequestIDs = neighboringItems().compactMap { item in
            guard let asset = repository.asset(localIdentifier: item.assetLocalIdentifier) else {
                return nil
            }
            let requestID = AssetPlaybackLoader.shared.prefetchPlayerItem(for: asset, timeout: 15)
            return requestID == PHInvalidImageRequestID ? nil : requestID
        }
    }

    private func refreshCurrentPlayback() {
        loadCurrentItem()
    }

    private func transition(to target: Selection) {
        guard isPlaybackActive, !isLoading, !isTransitioning else { return }
        isTransitioning = true
        currentClipProgress = 0
        isPaused = false
        navigationTask?.cancel()
        volumeFadeTask?.cancel()
        volumeFadeTask = nil
        navigationTask = Task { [weak self] in
            guard let self else { return }
            await self.fadePlayerVolume(
                to: 0,
                duration: Self.transitionFadeOutDuration
            )
            guard !Task.isCancelled, self.isPlaybackActive else { return }
            self.selection = target
            self.refreshCurrentPlayback()
            self.navigationTask = nil
        }
    }

    private func fadePlayerVolume(to target: Float, duration: TimeInterval) async {
        let initial = player.volume
        let stepCount = 6
        let stepDuration = duration / Double(stepCount)
        for step in 1...stepCount {
            guard !Task.isCancelled else { return }
            let progress = Float(step) / Float(stepCount)
            player.volume = initial + ((target - initial) * progress)
            try? await Task.sleep(for: .seconds(stepDuration))
        }
        guard !Task.isCancelled else { return }
        player.volume = target
    }

    private func preparePlayerItem(
        _ playerItem: AVPlayerItem,
        generation: Int,
        assetIdentifier: String
    ) {
        let shouldFadeIn = isTransitioning
        player.volume = shouldFadeIn ? 0 : 1
        player.removeAllItems()
        player.insert(playerItem, after: nil)
        isPlayerReadyForCurrentAsset = true
        currentStampContext = pendingStampContext
        currentTextOverlays = pendingTextOverlays
        observePlaybackEnd(for: playerItem)

        playerPreparationTask?.cancel()
        playerPreparationTask = Task { [weak self, weak playerItem] in
            guard let self, let playerItem else { return }
            for _ in 0..<35 {
                guard !Task.isCancelled else { return }
                if self.player.status == .readyToPlay
                    || playerItem.status == .readyToPlay {
                    break
                }
                if playerItem.status == .failed {
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            self.finishPreparedPlayerItem(
                playerItem,
                generation: generation,
                assetIdentifier: assetIdentifier,
                shouldFadeIn: shouldFadeIn
            )
        }
    }

    private func finishPreparedPlayerItem(
        _ playerItem: AVPlayerItem,
        generation: Int,
        assetIdentifier: String,
        shouldFadeIn: Bool
    ) {
        guard isPlaybackActive,
              loadGeneration == generation,
              player.currentItem === playerItem,
              isLoading else { return }
        playerPreparationTask?.cancel()
        playerPreparationTask = nil
        player.playImmediately(atRate: 1)
        isPaused = false
        isLoading = false
        didFailToLoad = false
        isTransitioning = false
        if mode == .continuousDay {
            insertQueuedNextItemIfPossible()
            prepareContinuousNextItem()
        } else {
            prefetchNeighbors()
        }
        AppLog.player.info("player.load.success asset=\(assetIdentifier, privacy: .private(mask: .hash))")
        if shouldFadeIn {
            volumeFadeTask?.cancel()
            volumeFadeTask = Task { [weak self] in
                guard let self else { return }
                await self.fadePlayerVolume(
                    to: 1,
                    duration: Self.transitionFadeInDuration
                )
                self.volumeFadeTask = nil
            }
        }
    }

    private func finishTransitionAfterFailure() {
        isTransitioning = false
        currentClipProgress = 0
        isPaused = false
        player.volume = 1
    }

    private func cancelPrefetchRequests() {
        prefetchRequestIDs.forEach { AssetPlaybackLoader.shared.cancel($0) }
        prefetchRequestIDs.removeAll()
    }

    private func neighboringItems() -> [PlaybackClipItem] {
        var items: [PlaybackClipItem] = []

        if canRetreatClip {
            items.append(currentDay.items[currentClipIndex - 1])
        }
        if canAdvanceClip {
            items.append(currentDay.items[currentClipIndex + 1])
        }
        if canRetreatDay {
            let previousDay = days[currentDayIndex - 1]
            let index = ClipBrowserNavigator.closestClipIndex(to: currentItem.capturedAt, in: previousDay)
            items.append(previousDay.items[index])
        }
        if canAdvanceDay {
            let nextDay = days[currentDayIndex + 1]
            let index = ClipBrowserNavigator.closestClipIndex(to: currentItem.capturedAt, in: nextDay)
            items.append(nextDay.items[index])
        }

        return items
    }

    /// 一日再生では次の動画を AVQueuePlayer に先に積み、終了時の再読込をなくす。
    private func prepareContinuousNextItem() {
        guard isPlaybackActive,
              mode == .continuousDay,
              canAdvanceClip,
              queuedNextAssetIdentifier == nil,
              queuedNextPlayerItem == nil else { return }

        let nextClip = currentDay.items[currentClipIndex + 1]
        guard let asset = repository.asset(
            localIdentifier: nextClip.assetLocalIdentifier
        ) else { return }

        queuedNextAssetIdentifier = asset.localIdentifier
        if asset.pixelWidth > 0, asset.pixelHeight > 0 {
            queuedNextAspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        } else {
            queuedNextAspectRatio = currentVideoAspectRatio
        }
        prepareQueuedStampContext(for: asset, clip: nextClip)
        requestContinuousNextItem(
            for: asset,
            assetIdentifier: asset.localIdentifier,
            attempt: .fast
        )
    }

    private func requestContinuousNextItem(
        for asset: PHAsset,
        assetIdentifier: String,
        attempt: LoadAttempt
    ) {
        let requestID = AssetPlaybackLoader.shared.requestPlayerItem(
            for: asset,
            deliveryMode: attempt.deliveryMode,
            timeout: attempt.timeout
        ) { [weak self] result in
            guard let self,
                  self.isPlaybackActive,
                  self.mode == .continuousDay,
                  self.queuedNextAssetIdentifier == assetIdentifier,
                  self.canAdvanceClip,
                  self.currentDay.items[self.currentClipIndex + 1].assetLocalIdentifier == assetIdentifier else {
                return
            }

            self.queuedNextRequestID = nil
            switch result {
            case .success(let playerItem):
                playerItem.preferredForwardBufferDuration = 1
                self.queuedNextPlayerItem = playerItem
                self.insertQueuedNextItemIfPossible()
                AppLog.player.info("player.queue.ready asset=\(assetIdentifier, privacy: .private(mask: .hash))")
            case .failure(let error):
                if attempt == .fast {
                    self.requestContinuousNextItem(
                        for: asset,
                        assetIdentifier: assetIdentifier,
                        attempt: .reliable
                    )
                } else {
                    self.clearQueuedNextState()
                    AppLog.player.warning("player.queue.fail asset=\(assetIdentifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)")
                }
            }
        }

        if queuedNextAssetIdentifier == assetIdentifier,
           queuedNextPlayerItem == nil {
            queuedNextRequestID = requestID == PHInvalidImageRequestID ? nil : requestID
        }
    }

    private func insertQueuedNextItemIfPossible() {
        guard !isLoading,
              let queuedItem = queuedNextPlayerItem,
              player.currentItem != nil,
              !player.items().contains(where: { $0 === queuedItem }) else { return }
        let tail = player.items().last
        guard player.canInsert(queuedItem, after: tail) else {
            clearQueuedNextState()
            return
        }
        player.insert(queuedItem, after: tail)
    }

    private func adoptContinuousNextItem(after finishedItem: AVPlayerItem) {
        guard mode == .continuousDay, canAdvanceClip else { return }
        let nextClip = currentDay.items[currentClipIndex + 1]
        guard queuedNextAssetIdentifier == nextClip.assetLocalIdentifier,
              let queuedItem = queuedNextPlayerItem else {
            advanceClip()
            return
        }

        insertQueuedNextItemIfPossible()
        if player.currentItem === finishedItem {
            player.advanceToNextItem()
        }
        guard player.currentItem === queuedItem else {
            advanceClip()
            return
        }

        selection = Selection(
            dayIndex: currentDayIndex,
            clipIndex: currentClipIndex + 1
        )
        currentStampContext = queuedNextStampContext
        pendingStampContext = queuedNextStampContext
        currentTextOverlays = queuedNextTextOverlays
        pendingTextOverlays = queuedNextTextOverlays
        currentVideoAspectRatio = queuedNextAspectRatio ?? currentVideoAspectRatio
        isPlayerReadyForCurrentAsset = true
        isLoading = false
        didFailToLoad = false
        isTransitioning = false
        currentClipProgress = 0
        isPaused = false
        player.volume = 1
        player.play()

        queuedNextRequestID = nil
        queuedNextAssetIdentifier = nil
        queuedNextPlayerItem = nil
        queuedNextStampContext = nil
        queuedNextTextOverlays = []
        queuedNextAspectRatio = nil

        observePlaybackEnd(for: queuedItem)
        prepareContinuousNextItem()
    }

    private func prepareQueuedStampContext(
        for asset: PHAsset,
        clip: PlaybackClipItem
    ) {
        Task { [weak self] in
            guard let self else { return }
            let assetIdentifier = asset.localIdentifier
            let recipe = await stampContextService.recipe(for: assetIdentifier)
            guard isPlaybackActive,
                  queuedNextAssetIdentifier == assetIdentifier
                    || currentItem.assetLocalIdentifier == assetIdentifier else { return }

            let stampSettings = settingsStore.dateStampSettings
            let storageMode = settingsStore.videoStorageMode
            let source = VideoStampSource(
                assetLocalIdentifier: assetIdentifier,
                capturedAt: clip.capturedAt,
                location: asset.location
            )
            let initialContext = stampContextService.displayContext(
                source: source,
                recipe: recipe,
                settings: stampSettings,
                storageMode: storageMode
            )
            applyPreparedStampContext(initialContext, assetIdentifier: assetIdentifier)
            let initialTextOverlays = await resolvedTextOverlays(
                assetIdentifier: assetIdentifier,
                clip: clip,
                stampContext: initialContext
            )
            guard isPlaybackActive else { return }
            applyPreparedTextOverlays(initialTextOverlays, assetIdentifier: assetIdentifier)

            let resolvedContext = await stampContextService.resolvedDisplayContext(
                source: source,
                recipe: recipe,
                settings: stampSettings,
                storageMode: storageMode
            )
            guard isPlaybackActive else { return }
            applyPreparedStampContext(resolvedContext, assetIdentifier: assetIdentifier)
            if resolvedContext != initialContext {
                let resolvedOverlays = await resolvedTextOverlays(
                    assetIdentifier: assetIdentifier,
                    clip: clip,
                    stampContext: resolvedContext
                )
                guard isPlaybackActive else { return }
                applyPreparedTextOverlays(resolvedOverlays, assetIdentifier: assetIdentifier)
            }
        }
    }

    private func applyPreparedStampContext(
        _ context: VideoPostProcessContext?,
        assetIdentifier: String
    ) {
        if queuedNextAssetIdentifier == assetIdentifier {
            queuedNextStampContext = context
        } else if currentItem.assetLocalIdentifier == assetIdentifier {
            currentStampContext = context
            pendingStampContext = context
        }
    }

    private func applyPreparedTextOverlays(
        _ overlays: [VlogResolvedTextOverlay],
        assetIdentifier: String
    ) {
        if queuedNextAssetIdentifier == assetIdentifier {
            queuedNextTextOverlays = overlays
        } else if currentItem.assetLocalIdentifier == assetIdentifier {
            currentTextOverlays = overlays
            pendingTextOverlays = overlays
        }
    }

    private func resolvedTextOverlays(
        assetIdentifier: String,
        clip: PlaybackClipItem,
        stampContext: VideoPostProcessContext?
    ) async -> [VlogResolvedTextOverlay] {
        do {
            guard let edit = try await clipEditStore.edit(for: assetIdentifier) else {
                return []
            }
            let metadata = VlogClipSourceMetadata(
                capturedAt: clip.capturedAt,
                capturedPlaceName: stampContext?.placeName,
                timeZoneIdentifier: stampContext?.timeZoneIdentifier
                    ?? TimeZone.current.identifier
            )
            return VlogTextOverlayResolver.resolve(
                edit: edit,
                metadata: metadata,
                clipDuration: clip.duration
            )
        } catch {
            AppLog.player.error(
                "vlog_edit.playback.load.fail asset=\(assetIdentifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)"
            )
            return []
        }
    }

    private func cancelQueuedNext(removeFromPlayer: Bool) {
        AssetPlaybackLoader.shared.cancel(queuedNextRequestID)
        if removeFromPlayer {
            player.items().dropFirst().forEach { player.remove($0) }
        }
        clearQueuedNextState()
    }

    private func clearQueuedNextState() {
        queuedNextRequestID = nil
        queuedNextAssetIdentifier = nil
        queuedNextPlayerItem = nil
        queuedNextStampContext = nil
        queuedNextTextOverlays = []
        queuedNextAspectRatio = nil
    }

    private func observePlaybackEnd(for item: AVPlayerItem) {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.mode == .continuousDay, self.canAdvanceClip {
                    Task { @MainActor [weak self, weak item] in
                        await Task.yield()
                        guard let self, let item else { return }
                        self.adoptContinuousNextItem(after: item)
                    }
                } else {
                    self.currentClipProgress = 1
                    self.isPaused = true
                }
            }
        }
    }

    private func observePlaybackProgress() {
        guard playbackProgressObserver == nil else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        playbackProgressObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.updatePlaybackProgress(time)
            }
        }
    }

    private func updatePlaybackProgress(_ time: CMTime) {
        guard isPlaybackActive else { return }
        let playerDuration = player.currentItem?.duration.seconds ?? .nan
        let resolvedDuration = playerDuration.isFinite && playerDuration > 0
            ? playerDuration
            : currentItem.duration
        guard time.seconds.isFinite, resolvedDuration > 0 else {
            currentClipProgress = 0
            return
        }
        currentClipProgress = min(max(time.seconds / resolvedDuration, 0), 1)
    }

    private func loadCurrentItem() {
        guard isPlaybackActive else { return }
        currentClipProgress = 0
        isPaused = false
        loadGeneration += 1
        let generation = loadGeneration
        playerPreparationTask?.cancel()
        playerPreparationTask = nil
        AssetPlaybackLoader.shared.cancel(currentRequestID)
        currentRequestID = nil
        cancelQueuedNext(removeFromPlayer: true)
        cancelPrefetchRequests()
        currentStampContext = nil
        currentTextOverlays = []
        pendingStampContext = nil
        pendingTextOverlays = []
        isPlayerReadyForCurrentAsset = false

        guard let asset = repository.asset(
            localIdentifier: currentItem.assetLocalIdentifier
        ) else {
            loadingAssetIdentifier = nil
            isLoading = false
            didFailToLoad = true
            player.pause()
            player.removeAllItems()
            finishTransitionAfterFailure()
            return
        }

        let requestedAssetIdentifier = asset.localIdentifier
        if asset.pixelWidth > 0, asset.pixelHeight > 0 {
            currentVideoAspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        }
        loadingAssetIdentifier = requestedAssetIdentifier
        isLoading = true
        didFailToLoad = false
        player.pause()

        loadStampRecipe(
            asset: asset,
            generation: generation
        )
        if mode == .continuousDay {
            prepareContinuousNextItem()
        }

        AppLog.player.info("player.load.begin asset=\(requestedAssetIdentifier, privacy: .private(mask: .hash))")
        requestPlayerItem(
            for: asset,
            assetIdentifier: requestedAssetIdentifier,
            generation: generation,
            attempt: .fast
        )
    }

    private func requestPlayerItem(
        for asset: PHAsset,
        assetIdentifier: String,
        generation: Int,
        attempt: LoadAttempt
    ) {
        let requestID = AssetPlaybackLoader.shared.requestPlayerItem(
            for: asset,
            deliveryMode: attempt.deliveryMode,
            timeout: attempt.timeout
        ) { [weak self] result in
            guard let self,
                  self.isPlaybackActive,
                  self.loadGeneration == generation,
                  self.loadingAssetIdentifier == assetIdentifier else { return }

            self.currentRequestID = nil
            switch result {
            case .success(let playerItem):
                self.loadingAssetIdentifier = nil
                self.preparePlayerItem(
                    playerItem,
                    generation: generation,
                    assetIdentifier: assetIdentifier
                )
            case .failure(let error):
                if attempt == .fast {
                    AppLog.player.warning("player.load.retry asset=\(assetIdentifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)")
                    self.requestPlayerItem(
                        for: asset,
                        assetIdentifier: assetIdentifier,
                        generation: generation,
                        attempt: .reliable
                    )
                } else {
                    self.loadingAssetIdentifier = nil
                    self.cancelQueuedNext(removeFromPlayer: true)
                    self.player.removeAllItems()
                    self.isLoading = false
                    self.didFailToLoad = true
                    self.finishTransitionAfterFailure()
                    AppLog.player.error("player.load.fail asset=\(assetIdentifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)")
                }
            }
        }
        if loadGeneration == generation, isLoading {
            currentRequestID = requestID == PHInvalidImageRequestID ? nil : requestID
        }
    }

    private func loadStampRecipe(
        asset: PHAsset,
        generation: Int
    ) {
        Task { [weak self] in
            guard let self else { return }
            let assetIdentifier = asset.localIdentifier
            let recipe = await stampContextService.recipe(for: assetIdentifier)
            guard isPlaybackActive,
                  loadGeneration == generation,
                  currentItem.assetLocalIdentifier == assetIdentifier else { return }
            let stampSettings = settingsStore.dateStampSettings
            let storageMode = settingsStore.videoStorageMode
            let source = VideoStampSource(
                assetLocalIdentifier: assetIdentifier,
                capturedAt: currentItem.capturedAt,
                location: asset.location
            )
            let initialContext = stampContextService.displayContext(
                source: source,
                recipe: recipe,
                settings: stampSettings,
                storageMode: storageMode
            )
            pendingStampContext = initialContext
            pendingTextOverlays = await resolvedTextOverlays(
                assetIdentifier: assetIdentifier,
                clip: currentItem,
                stampContext: initialContext
            )
            guard isPlaybackActive,
                  loadGeneration == generation,
                  currentItem.assetLocalIdentifier == assetIdentifier else { return }
            if isPlayerReadyForCurrentAsset {
                currentStampContext = pendingStampContext
                currentTextOverlays = pendingTextOverlays
            }

            let resolvedContext = await stampContextService.resolvedDisplayContext(
                source: source,
                recipe: recipe,
                settings: stampSettings,
                storageMode: storageMode
            )
            guard isPlaybackActive,
               loadGeneration == generation,
               currentItem.assetLocalIdentifier == assetIdentifier else { return }
            guard resolvedContext != initialContext else { return }
            pendingStampContext = resolvedContext
            pendingTextOverlays = await resolvedTextOverlays(
                assetIdentifier: assetIdentifier,
                clip: currentItem,
                stampContext: resolvedContext
            )
            guard isPlaybackActive,
                  loadGeneration == generation,
                  currentItem.assetLocalIdentifier == assetIdentifier else { return }
            if isPlayerReadyForCurrentAsset {
                currentStampContext = pendingStampContext
                currentTextOverlays = pendingTextOverlays
            }
        }
    }
}
