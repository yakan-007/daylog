import SwiftUI
import Photos

struct LibraryCalendarView: View {
    @ObservedObject var photoViewModel: PhotoSheetViewModel
    let onTapDay: ([PHAsset]) -> Void
    let onShareDay: ([PHAsset]) -> Void
    let onDeleteDay: ([PHAsset]) -> Void
    let onPlayMonth: ([PHAsset]) -> Void
    let onShareMonth: ([PHAsset]) -> Void
    let onDeleteMonth: ([PHAsset]) -> Void

    var body: some View {
        MonthGridView(
            months: photoViewModel.buildMonthSections(),
            viewModel: photoViewModel,
            onTapDay: onTapDay,
            onShareDay: onShareDay,
            onDeleteDay: onDeleteDay,
            onPlayMonth: onPlayMonth,
            onShareMonth: onShareMonth,
            onDeleteMonth: onDeleteMonth
        )
        .refreshable { photoViewModel.fetchAllVideos() }
    }
}
