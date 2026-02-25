import SwiftUI
import Photos

struct LibraryListView: View {
    let groups: [DayVideoGroup]
    @ObservedObject var photoViewModel: PhotoSheetViewModel
    @ObservedObject var libraryViewModel: LibraryScreenViewModel
    let onPlayAll: ([PHAsset]) -> Void
    let onShareAll: ([PHAsset]) -> Void
    let onTapAsset: (PHAsset, [PHAsset]) -> Void
    let onDeleteAsset: (PHAsset) -> Void
    let onGroupAppear: (DayVideoGroup) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    DaySectionView(
                        group: group,
                        viewModel: photoViewModel,
                        onPlayAll: onPlayAll,
                        onShareAll: onShareAll,
                        onTapAsset: { asset in onTapAsset(asset, group.assets) },
                        onDeleteAsset: onDeleteAsset,
                        isSelecting: $libraryViewModel.isSelecting,
                        selectedIds: $libraryViewModel.selectedIds
                    )
                    .onAppear { onGroupAppear(group) }
                }
                if photoViewModel.isLoadingMoreList {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("読み込み中...")
                            .font(AppTheme.bodyFont)
                            .foregroundColor(AppTheme.onGlass.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .padding(.bottom, PhotoSheetStyle.contentBottomInset)
        }
        .refreshable { photoViewModel.fetchAllVideos() }
    }
}
