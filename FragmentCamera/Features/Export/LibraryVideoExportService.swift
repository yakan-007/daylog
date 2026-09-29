import Foundation
import Photos

/// A single export target prevents day and clip exports from becoming active at
/// the same time, and gives retry/progress code one stable identity to compare.
enum LibraryExportTarget: Equatable, Sendable {
    case day(id: String, dayKey: String)
    case clip(id: String)

    var exportingDayKey: String? {
        guard case .day(_, let dayKey) = self else { return nil }
        return dayKey
    }

    var exportingClipID: String? {
        guard case .clip(let id) = self else { return nil }
        return id
    }
}

struct LibraryExportItem {
    let asset: PHAsset
    let capturedAt: Date
}

/// Stamp/place resolution owns the first part of the visible progress range.
/// Keeping the mapping here prevents each caller from inventing a different
/// progress scale for the same export pipeline.
enum LibraryExportProgressMapper {
    static let preparationWeight = 0.1

    static func resolvingStamps(
        completed: Int,
        total: Int
    ) -> DayVideoExportProgress {
        DayVideoExportProgress(
            fraction: preparationWeight
                * Double(completed)
                / Double(max(total, 1)),
            phase: .resolvingStamps(current: completed, total: total)
        )
    }

    static func exporting(
        _ progress: DayVideoExportProgress
    ) -> DayVideoExportProgress {
        DayVideoExportProgress(
            fraction: preparationWeight
                + (progress.fraction * (1 - preparationWeight)),
            phase: progress.phase
        )
    }
}

/// Shared preparation pipeline for both a whole day and an individual clip.
/// The caller is responsible only for choosing and ordering the source items;
/// settings, stamp recipes, place names, and rendering are resolved here once.
final class LibraryVideoExportService {
    private let exporter: DayVideoExporter
    private let stampContextService: VideoStampContextService
    private let clipEditStore: VlogClipEditStore
    private let settingsStore: DaylogSettingsStore

    init(
        exporter: DayVideoExporter,
        stampContextService: VideoStampContextService,
        clipEditStore: VlogClipEditStore,
        settingsStore: DaylogSettingsStore
    ) {
        self.exporter = exporter
        self.stampContextService = stampContextService
        self.clipEditStore = clipEditStore
        self.settingsStore = settingsStore
    }

    func export(
        items: [LibraryExportItem],
        outputKey: String,
        progress: @escaping @Sendable (DayVideoExportProgress) -> Void
    ) async throws -> URL {
        guard !items.isEmpty else {
            throw DayVideoExporterError.noAssets
        }

        progress(DayVideoExportProgress(fraction: 0, phase: .preparing))
        let storageMode = settingsStore.videoStorageMode
        let stampSettings = settingsStore.dateStampSettings
        let recipes = await stampContextService.recipes(
            for: items.map { $0.asset.localIdentifier }
        )
        let sources = items.map {
            VideoStampSource(
                assetLocalIdentifier: $0.asset.localIdentifier,
                capturedAt: $0.capturedAt,
                location: $0.asset.location
            )
        }
        let stampContexts = await stampContextService.resolvedDisplayContexts(
            sources: sources,
            recipes: recipes,
            settings: stampSettings,
            storageMode: storageMode,
            progress: { completed, total in
                progress(LibraryExportProgressMapper.resolvingStamps(
                    completed: completed,
                    total: total
                ))
            }
        )
        let edits = try await clipEditStore.edits(
            for: items.map { $0.asset.localIdentifier }
        )
        let textOverlaysByClip: [[VlogResolvedTextOverlay]] = items.enumerated().map { index, item in
            guard let edit = edits[index] else { return [] }
            let stampContext = stampContexts[index]
            return VlogTextOverlayResolver.resolve(
                edit: edit,
                metadata: VlogClipSourceMetadata(
                    capturedAt: item.capturedAt,
                    capturedPlaceName: stampContext?.placeName,
                    timeZoneIdentifier: stampContext?.timeZoneIdentifier
                        ?? TimeZone.current.identifier
                ),
                clipDuration: item.asset.duration
            )
        }

        try Task.checkCancellation()
        return try await exporter.exportMergedVideo(
            for: items.map(\.asset),
            captureDates: items.map(\.capturedAt),
            stampContexts: stampContexts,
            textOverlaysByClip: textOverlaysByClip,
            dayKey: outputKey,
            storageMode: storageMode,
            progress: {
                progress(LibraryExportProgressMapper.exporting($0))
            }
        )
    }

    func discardExport(at url: URL) {
        exporter.discardExport(at: url)
    }
}
