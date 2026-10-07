import CoreLocation
import Foundation
import OSLog

/// 撮影中の位置情報と設定値をまとめるUI側の窓口。
/// CameraServiceと同じMainActorに閉じ込め、保存中の中断操作と競合させない。
@MainActor
final class CaptureSaveCoordinator {
    private let pipeline: CaptureSavePipeline
    private let settingsStore: VlogishSettingsStore
    private let locationService: CaptureLocationService
    private let placeNameResolver: any PlaceNameResolving

    init(
        pipeline: CaptureSavePipeline,
        settingsStore: VlogishSettingsStore,
        locationService: CaptureLocationService,
        placeNameResolver: any PlaceNameResolving = PlaceNameResolver()
    ) {
        self.pipeline = pipeline
        self.settingsStore = settingsStore
        self.locationService = locationService
        self.placeNameResolver = placeNameResolver
    }

    func prepareForRecording() {
        locationService.startIfEnabled(settingsStore.locationCaptureEnabled)
    }

    func cancelRecording() {
        locationService.stop()
    }

    func saveRecording(
        at outputURL: URL,
        capturedAt: Date = Date()
    ) async throws -> SavedRecordingResult {
        let stampSettings = settingsStore.dateStampSettings
        let storageMode = settingsStore.videoStorageMode
        let location = settingsStore.locationCaptureEnabled
            ? locationService.bestRecentLocation()
            : nil
        let placeName: String? = if stampSettings.isEnabled,
                                    stampSettings.elements.contains(.place),
                                    let location {
            await placeNameResolver.placeName(for: location)
        } else {
            nil
        }
        let context = stampSettings.recordingContext(
            capturedAt: capturedAt,
            placeName: placeName,
            timeZoneIdentifier: TimeZone.current.identifier,
            storageMode: storageMode
        )

        AppLog.save.info("save.begin stamp_enabled=\(stampSettings.isEnabled, privacy: .public) compact=\(storageMode == .compact, privacy: .public)")
        return try await pipeline.processAndSaveRecording(
            outputURL: outputURL,
            location: location,
            context: context,
            renderingMode: settingsStore.stampRenderingMode
        )
    }

}
