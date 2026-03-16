import Combine
import Photos
import SwiftUI

@MainActor
final class DaylogContainer: ObservableObject {
    let cameraService: CameraService
    let captureViewModel: CaptureFeatureViewModel
    let libraryViewModel: LibraryFeatureViewModel
    let settingsViewModel: SettingsViewModel

    private let repository: DaylogPhotoLibraryRepository
    private let store: ClipMetadataStore
    private let thumbnailService: ThumbnailService
    private let libraryUseCase: DaylogLibraryUseCase
    private let playbackFactory: PlaybackFeatureFactory
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.store = ClipMetadataStore()
        self.repository = DaylogPhotoLibraryRepository(albumName: "daylog")
        self.thumbnailService = ThumbnailService(repository: repository)
        self.libraryUseCase = DaylogLibraryUseCase(store: store, repository: repository)

        let permissionService = CameraPermissionService()
        let assetWriter = AssetLibraryWriter(albumName: "daylog")
        let postProcessService = DefaultVideoPostProcessingService()
        self.cameraService = CameraService(
            permissionService: permissionService,
            postProcessService: postProcessService,
            assetLibraryWriter: assetWriter
        )

        let captureUseCase = DefaultCaptureUseCase(cameraService: cameraService)
        self.captureViewModel = CaptureFeatureViewModel(useCase: captureUseCase)
        self.libraryViewModel = LibraryFeatureViewModel(
            useCase: libraryUseCase,
            repository: repository,
            thumbnailService: thumbnailService
        )
        self.settingsViewModel = SettingsViewModel()
        self.playbackFactory = PlaybackFeatureFactory()
        bindFeatures()
    }

    func makePlaybackSingle(asset: PHAsset) -> PlaybackFeatureViewModel {
        playbackFactory.makeSingle(asset: asset)
    }

    func makePlaybackDay(assets: [PHAsset]) -> PlaybackFeatureViewModel {
        playbackFactory.makeDay(assets: assets)
    }

    private func bindFeatures() {
        captureViewModel.$latestSavedAssetIdentifier
            .compactMap { $0 }
            .sink { [weak self] identifier in
                guard let self else { return }
                Task {
                    await self.libraryViewModel.handleCaptureSaved(preferredAssetIdentifier: identifier)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.captureViewModel.acknowledgeIndexedSave()
                }
            }
            .store(in: &cancellables)
    }
}
