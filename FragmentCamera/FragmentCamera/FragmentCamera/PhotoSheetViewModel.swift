import SwiftUI
import Photos
import CoreLocation

// A struct to hold videos grouped by a specific day
struct DayVideoGroup: Identifiable, Hashable {
    let id: Date
    let date: Date
    let assets: [PHAsset]
}

class PhotoSheetViewModel: ObservableObject {
    @Published var groupedVideos: [DayVideoGroup] = []

    func fetchAllVideos() {
        // 1. Find the "daylog" album
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", "daylog")
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        guard let album = collections.firstObject else {
            print("Album 'daylog' not found.")
            DispatchQueue.main.async {
                self.groupedVideos = []
            }
            return
        }

        // 2. Fetch all videos from that album, sorted by creation date
        let assetsFetchOptions = PHFetchOptions()
        assetsFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assetsFetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(in: album, options: assetsFetchOptions)

        // 3. Group assets by day
        var assetsByDay: [Date: [PHAsset]] = [:]
        fetchResult.enumerateObjects { (asset, _, _) in
            let day = Calendar.current.startOfDay(for: asset.creationDate ?? Date())
            if assetsByDay[day] == nil {
                assetsByDay[day] = []
            }
            assetsByDay[day]?.append(asset)
        }

        // 4. Convert the dictionary to a sorted array of DayVideoGroup structs
        let sortedGroups = assetsByDay.map { (date, assets) in
            DayVideoGroup(id: date, date: date, assets: assets)
        }.sorted { $0.date > $1.date } // Sort so the most recent day is first

        DispatchQueue.main.async {
            self.groupedVideos = sortedGroups
            print("Fetched and grouped videos for \(sortedGroups.count) days.")
        }
    }

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact

        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            completion(image)
        }
    }

    func getPlacemark(for location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("Reverse geocoding failed: \(error.localizedDescription)")
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
                    print("Failed to delete asset: \(error.localizedDescription)")
                }
                completion(success)
            }
        }
    }
}
