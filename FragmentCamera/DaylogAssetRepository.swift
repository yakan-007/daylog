import Foundation
import Photos

final class DaylogAssetRepository: NSObject, PHPhotoLibraryChangeObserver {
    private let albumName: String
    private let queue = DispatchQueue(label: "DaylogAssetRepository.FetchQueue", qos: .userInitiated)
    private var onChange: (() -> Void)?

    init(albumName: String = "daylog") {
        self.albumName = albumName
        super.init()
    }

    func observeChanges(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
        PHPhotoLibrary.shared().register(self)
    }

    func stopObserving() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        onChange = nil
    }

    func fetchGroupedVideos() async throws -> [DayVideoGroup] {
        let albumName = self.albumName
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
                let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

                guard let album = collections.firstObject else {
                    continuation.resume(returning: [])
                    return
                }

                let assetsFetchOptions = PHFetchOptions()
                assetsFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                assetsFetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                let fetchResult = PHAsset.fetchAssets(in: album, options: assetsFetchOptions)

                var assetsByDay: [Date: [PHAsset]] = [:]
                let calendar = Calendar.current
                fetchResult.enumerateObjects { (asset, _, _) in
                    let day = calendar.startOfDay(for: asset.creationDate ?? Date())
                    assetsByDay[day, default: []].append(asset)
                }

                let sortedGroups = assetsByDay
                    .map { (date, assets) in DayVideoGroup(id: date, date: date, assets: assets) }
                    .sorted { $0.date > $1.date }

                continuation.resume(returning: sortedGroups)
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}
