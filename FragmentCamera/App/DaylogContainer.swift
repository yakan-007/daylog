import Combine
import Foundation

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
    private let dayVideoExporter: DayVideoExporter
    private let libraryVideoExportService: LibraryVideoExportService
    private let mediaExporter: MediaExporter
    private let settingsStore: DaylogSettingsStore
    private let temporaryFileStore: TemporaryFileStore
    private let stampRecipeStore: VideoStampRecipeStore
    private let placeNameResolver: PlaceNameResolver
    private let stampContextService: VideoStampContextService
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.settingsStore = Self.makeSettingsStore()
        self.temporaryFileStore = TemporaryFileStore()
        self.stampRecipeStore = VideoStampRecipeStore()
        self.placeNameResolver = PlaceNameResolver()
        self.stampContextService = VideoStampContextService(
            recipeStore: stampRecipeStore,
            placeNameResolver: placeNameResolver
        )
        self.mediaExporter = MediaExporter(temporaryFileStore: temporaryFileStore)
        self.store = ClipMetadataStore()
        self.repository = DaylogPhotoLibraryRepository(albumName: AppIdentity.photoAlbumName)
        self.thumbnailService = ThumbnailService(repository: repository)
        self.libraryUseCase = DaylogLibraryUseCase(store: store, repository: repository)
        self.dayVideoExporter = DayVideoExporter(
            temporaryFileStore: temporaryFileStore,
            mediaExporter: mediaExporter
        )
        self.libraryVideoExportService = LibraryVideoExportService(
            exporter: dayVideoExporter,
            stampContextService: stampContextService,
            settingsStore: settingsStore
        )

        let permissionService = CameraPermissionService()
        let locationService = CaptureLocationService()
        let assetWriter = AssetLibraryWriter(
            albumName: AppIdentity.photoAlbumName,
            temporaryFileStore: temporaryFileStore
        )
        let postProcessPipeline = VideoPostProcessPipeline(
            temporaryFileStore: temporaryFileStore,
            mediaExporter: mediaExporter
        )
        let stampEditingService = VideoStampEditingService(
            postProcessPipeline: postProcessPipeline,
            temporaryFileStore: temporaryFileStore,
            stampRecipeStore: stampRecipeStore,
            placeNameResolver: placeNameResolver,
            settingsStore: settingsStore
        )
        self.cameraService = CameraService(
            permissionService: permissionService,
            postProcessPipeline: postProcessPipeline,
            assetLibraryWriter: assetWriter,
            settingsStore: settingsStore,
            temporaryFileStore: temporaryFileStore,
            locationService: locationService,
            stampRecipeStore: stampRecipeStore,
            placeNameResolver: placeNameResolver
        )

        self.captureViewModel = CaptureFeatureViewModel(
            cameraService: cameraService,
            settingsStore: settingsStore
        )
        self.libraryViewModel = LibraryFeatureViewModel(
            useCase: libraryUseCase,
            repository: repository,
            thumbnailService: thumbnailService,
            exportService: libraryVideoExportService,
            stampEditingService: stampEditingService
        )
        self.settingsViewModel = SettingsViewModel(settingsStore: settingsStore)
        bindFeatures()
    }

    /// UIテスト中は実利用の設定を変更しないよう、専用のUserDefaultsへ分離する。
    private static func makeSettingsStore() -> DaylogSettingsStore {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing") {
            let suiteName = "com.leo.vlogish.ui-testing"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("UIテスト用UserDefaultsを作成できませんでした。")
            }
            if arguments.contains("-ui-testing-reset-settings") {
                defaults.removePersistentDomain(forName: suiteName)
            }
            let store = DaylogSettingsStore(defaults: defaults)
            store.hasSeenCaptureIntroCard = true
            if arguments.contains("-ui-testing-disable-stamp-fade") {
                store.stampFadesOut = false
            }
            return store
        }
#endif
        return DaylogSettingsStore()
    }

    func makeLibraryClipBrowser(context: LibraryClipPlaybackContext) -> LibraryClipBrowserViewModel {
        LibraryClipBrowserViewModel(
            context: context,
            repository: repository,
            stampContextService: stampContextService,
            settingsStore: settingsStore
        )
    }

    private func bindFeatures() {
        captureViewModel.$state
            .compactMap { $0.engine.lastSavedAssetLocalIdentifier }
            .removeDuplicates()
            .sink { [weak self] identifier in
                guard let self else { return }
                Task {
                    await self.libraryViewModel.handleCaptureSaved(preferredAssetIdentifier: identifier)
                    self.captureViewModel.acknowledgeIndexedSave()
                }
            }
            .store(in: &cancellables)
    }
}
