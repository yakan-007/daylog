import SwiftUI
import Photos
import CoreLocation
import OSLog

class PhotoSheetViewModel: ObservableObject {
    @Published var groupedVideos: [DayVideoGroup] = []
    @Published private(set) var visibleListGroups: [DayVideoGroup] = []
    @Published private(set) var isFetching: Bool = false
    @Published private(set) var isLoadingMoreList: Bool = false
    private let imageManager = PHCachingImageManager()
    private let calendar = Calendar.current
    private let repository = DaylogAssetRepository(albumName: "daylog")
    private var isFetchInProgress = false
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let listPageSize = 10
    private var loadedListCount = 0

    init() {
        repository.observeChanges { [weak self] in
            self?.fetchAllVideos()
        }
    }

    deinit {
        repository.stopObserving()
    }

    func fetchAllVideos() {
        guard !isFetchInProgress else { return }
        isFetchInProgress = true
        DispatchQueue.main.async {
            self.isFetching = true
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let groups = try await repository.fetchGroupedVideos()
                await MainActor.run {
                    self.groupedVideos = groups
                    self.resetListPagination()
                    self.isFetchInProgress = false
                    self.isFetching = false
                    AppLog.export.info("Fetched and grouped videos for \(groups.count) days.")
                }
            } catch {
                AppLog.export.error("Failed to fetch grouped videos: \(error.localizedDescription)")
                await MainActor.run {
                    self.isFetchInProgress = false
                    self.isFetching = false
                }
            }
        }
    }

    func resetListPagination() {
        loadedListCount = min(listPageSize, groupedVideos.count)
        visibleListGroups = Array(groupedVideos.prefix(loadedListCount))
        isLoadingMoreList = false
    }

    func loadMoreListIfNeeded(currentGroup: DayVideoGroup) {
        guard let idx = visibleListGroups.firstIndex(where: { $0.id == currentGroup.id }) else { return }
        let threshold = max(0, visibleListGroups.count - 3)
        guard idx >= threshold else { return }
        guard loadedListCount < groupedVideos.count else { return }
        guard !isLoadingMoreList else { return }

        isLoadingMoreList = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let nextCount = min(self.loadedListCount + self.listPageSize, self.groupedVideos.count)
            self.loadedListCount = nextCount
            self.visibleListGroups = Array(self.groupedVideos.prefix(nextCount))
            self.isLoadingMoreList = false
        }
    }

    @discardableResult
    func loadThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let cacheKey = thumbnailKey(for: asset, targetSize: targetSize)
        if let cached = thumbnailCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast

        return imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, _ in
            if let image {
                self?.thumbnailCache.setObject(image, forKey: cacheKey as NSString)
            }
            completion(image)
        }
    }

    func cancelThumbnailRequest(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        // Keep preheat bounded to avoid memory spikes during very fast scrolling.
        let preheat = Array(assets.prefix(24))
        imageManager.startCachingImages(for: preheat, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        let preheat = Array(assets.prefix(24))
        imageManager.stopCachingImages(for: preheat, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    private func thumbnailKey(for asset: PHAsset, targetSize: CGSize) -> String {
        "\(asset.localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))"
    }

    func getPlacemark(for location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                AppLog.location.error("Reverse geocoding failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            
            // Prefer locality (e.g., city), but fall back to name
            let locationName = placemark.locality ?? placemark.name
            completion(locationName)
        }
    }

    func delete(asset: PHAsset, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.fetchAllVideos()
                } else if let error = error {
                    AppLog.export.error("Failed to delete asset: \(error.localizedDescription)")
                }
                completion(success)
            }
        }
    }

    // Build month sections from grouped days
    func buildMonthSections() -> [MonthSection] {
        // Map monthId -> [Date: [PHAsset]]
        var months: [String: [Date: [PHAsset]]] = [:]
        for group in groupedVideos {
            let comps = calendar.dateComponents([.year, .month], from: group.date)
            guard let year = comps.year, let month = comps.month, calendar.date(from: DateComponents(year: year, month: month, day: 1)) != nil else { continue }
            let key = String(format: "%04d-%02d", year, month)
            var map = months[key] ?? [:]
            map[group.date] = group.assets
            months[key] = map
        }

        // Build MonthSection list
        var sections: [MonthSection] = []
        for (key, dayMap) in months {
            let parts = key.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { continue }
            guard let firstDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)), let range = calendar.range(of: .day, in: .month, for: firstDate) else { continue }
            let numberOfDays = range.count
            let weekday = calendar.component(.weekday, from: firstDate) // 1..7 (1 = Sunday)
            let firstWeekday = calendar.firstWeekday
            let leadingEmpty = (weekday - firstWeekday + 7) % 7

            // Convert dayMap keyed by startOfDay(Date) to [Int: [PHAsset]]
            var assetsByDay: [Int: [PHAsset]] = [:]
            for (date, assets) in dayMap {
                let comps = calendar.dateComponents([.day], from: date)
                if let day = comps.day { assetsByDay[day] = assets }
            }

            let section = MonthSection(
                id: key,
                year: year,
                month: month,
                firstDate: firstDate,
                numberOfDays: numberOfDays,
                leadingEmpty: leadingEmpty,
                assetsByDay: assetsByDay
            )
            sections.append(section)
        }
        // Sort by firstDate desc (newest month first)
        sections.sort { $0.firstDate > $1.firstDate }
        return sections
    }
}
