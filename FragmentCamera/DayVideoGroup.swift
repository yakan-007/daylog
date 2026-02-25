import Foundation
import Photos

struct DayVideoGroup: Identifiable, Hashable {
    let id: Date
    let date: Date
    let assets: [PHAsset]
}
