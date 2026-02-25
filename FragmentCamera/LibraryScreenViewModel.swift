import Foundation
import Photos

final class LibraryScreenViewModel: ObservableObject {
    @Published var isSelecting: Bool = false
    @Published var selectedIds: Set<String> = []
    @Published var selectedTabRaw: String = PhotoSheetView.Tab.list.rawValue

    func beginSelection(with asset: PHAsset? = nil) {
        isSelecting = true
        if let asset {
            selectedIds.insert(asset.localIdentifier)
        }
    }

    func clearSelection() {
        isSelecting = false
        selectedIds.removeAll()
    }

    func toggleSelection(for asset: PHAsset) {
        if selectedIds.contains(asset.localIdentifier) {
            selectedIds.remove(asset.localIdentifier)
        } else {
            selectedIds.insert(asset.localIdentifier)
        }
    }

    func autoExitSelectionIfNeeded() {
        if isSelecting && selectedIds.isEmpty {
            isSelecting = false
        }
    }
}
