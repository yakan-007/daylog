import Photos
import SwiftUI

@MainActor
final class LibraryFeatureViewModel: ObservableObject {
    @Published var sections: [DaySection] = []
    @Published var isRefreshing = false
    @Published var isPresentingLibrary = false
    @Published var latestThumbnail: UIImage?
    @Published var playbackRoute: PlaybackRoute?

    private let useCase: DaylogLibraryUseCase
    private let repository: DaylogPhotoLibraryRepository
    private let thumbnailService: ThumbnailService
    private var observationTask: Task<Void, Never>?
    private var hasLoaded = false
    private var refreshInFlight = false
    private var isLoadingMore = false
    private var lastLoadedCursor: String?

    init(
        useCase: DaylogLibraryUseCase,
        repository: DaylogPhotoLibraryRepository,
        thumbnailService: ThumbnailService
    ) {
        self.useCase = useCase
        self.repository = repository
        self.thumbnailService = thumbnailService
    }

    deinit {
        observationTask?.cancel()
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        Task {
            let cached = await useCase.loadInitialSections()
            replaceSections(with: cached)
            refreshLatestThumbnail(preferredAssetIdentifier: cached.first?.clips.first?.assetLocalIdentifier)
            await refresh()
            observeChanges()
        }
    }

    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
        let refreshed = await useCase.refresh()
        replaceSections(with: refreshed)
        refreshLatestThumbnail(preferredAssetIdentifier: refreshed.first?.clips.first?.assetLocalIdentifier)
        isRefreshing = false
        refreshInFlight = false
    }

    func loadMoreIfNeeded(currentSection: DaySection) {
        guard sections.last?.id == currentSection.id else { return }
        guard !refreshInFlight, !isLoadingMore else { return }
        guard let cursor = sections.last?.dayKey, cursor != lastLoadedCursor else { return }

        isLoadingMore = true
        lastLoadedCursor = cursor

        Task {
            let moreSections = await useCase.loadMoreSections(after: cursor)
            appendSections(moreSections)
            isLoadingMore = false
        }
    }

    func handleCaptureSaved(preferredAssetIdentifier: String?) async {
        guard !refreshInFlight else {
            refreshLatestThumbnail(preferredAssetIdentifier: preferredAssetIdentifier)
            return
        }
        await refresh()
        refreshLatestThumbnail(preferredAssetIdentifier: preferredAssetIdentifier ?? sections.first?.clips.first?.assetLocalIdentifier)
    }

    func openLibrary() {
        isPresentingLibrary = true
    }

    func clipCountTodayLabel() -> String {
        let count = sections.first(where: { Calendar.current.isDateInToday($0.date) })?.clipCount ?? 0
        return count == 0 ? "まだありません" : "\(count)本"
    }

    func asset(for clip: ClipSummary) -> PHAsset? {
        repository.asset(localIdentifier: clip.assetLocalIdentifier)
    }

    func assets(for section: DaySection) -> [PHAsset] {
        repository.assets(localIdentifiers: section.clips.map(\.assetLocalIdentifier))
    }

    @discardableResult
    func requestThumbnail(
        for assetLocalIdentifier: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        thumbnailService.requestThumbnail(
            assetLocalIdentifier: assetLocalIdentifier,
            targetSize: targetSize,
            completion: completion
        )
    }

    func cancelThumbnailRequest(_ requestID: PHImageRequestID) {
        thumbnailService.cancel(requestID)
    }

    func play(asset clip: ClipSummary) {
        guard let asset = asset(for: clip) else { return }
        playbackRoute = .single(IdentifiableAsset(asset: asset))
        isPresentingLibrary = false
    }

    func play(section: DaySection) {
        playbackRoute = .day(IdentifiableAssets(assets: assets(for: section)))
        isPresentingLibrary = false
    }

    func clearPlaybackRoute() {
        playbackRoute = nil
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
        self.sections = sections.sorted(by: { $0.date > $1.date })
        lastLoadedCursor = nil
    }

    private func appendSections(_ sections: [DaySection]) {
        guard !sections.isEmpty else { return }
        let merged = Dictionary(uniqueKeysWithValues: (self.sections + sections).map { ($0.id, $0) })
        self.sections = merged.values.sorted(by: { $0.date > $1.date })
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
            DispatchQueue.main.async {
                self?.latestThumbnail = image
            }
        }
    }
}
