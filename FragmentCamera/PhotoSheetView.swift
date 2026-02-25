import SwiftUI
import Photos
import OSLog
import CoreLocation

// A view for a single video thumbnail
struct VideoThumbnailView: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var thumbnail: UIImage? = nil
    @State private var isLoaded: Bool = false
    @State private var thumbnailRequestID: PHImageRequestID = PHInvalidImageRequestID
    let size: CGFloat?
    let showsDurationBadge: Bool
    
    init(asset: PHAsset, viewModel: PhotoSheetViewModel, size: CGFloat? = nil, showsDurationBadge: Bool = true) {
        self.asset = asset
        self.viewModel = viewModel
        self.size = size
        self.showsDurationBadge = showsDurationBadge
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Rectangle().fill(Color(uiColor: .secondarySystemBackground))
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(isLoaded ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isLoaded)
                }
            }
            if showsDurationBadge, let durLabel = durationLabel {
                badge(text: durLabel)
                    .padding(6)
            }
        }
        .frame(width: size ?? 100, height: size ?? 100)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PhotoSheetStyle.thumbnailStroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(PhotoSheetStyle.thumbnailShadowOpacity), radius: 4, x: 0, y: 2)
        .onAppear {
            if thumbnail != nil { return }
            // Keep request size moderate to avoid decode spikes during fast scroll.
            let side = (size ?? 100) * 1.4
            let target = CGSize(width: side, height: side)
            thumbnailRequestID = viewModel.loadThumbnail(for: asset, targetSize: target) { image in
                self.thumbnail = image
                withAnimation(.easeInOut(duration: 0.15)) { self.isLoaded = (image != nil) }
            }
        }
        .onDisappear {
            viewModel.cancelThumbnailRequest(thumbnailRequestID)
            thumbnailRequestID = PHInvalidImageRequestID
        }
    }

    private func badge(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private var durationLabel: String? {
        let d = Int(round(asset.duration))
        guard d > 0 else { return nil }
        let m = d / 60, s = d % 60
        return String(format: "%d:%02d", m, s)
    }

    // timeLabel はUI崩れ回避のため非表示にしました
}

// A view for the section header (date + actions)
struct DateHeaderView: View {
    let date: Date
    let assets: [PHAsset]
    var onPlayAll: (([PHAsset]) -> Void)? = nil
    var onShareAll: (([PHAsset]) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var hSize

    // Default init is sufficient

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekdayString(from: date))
                    .font(AppTheme.labelFont)
                    .foregroundColor(AppTheme.onGlass.opacity(0.88))
                Text(dayTitle(from: date))
                    .font(AppTheme.titleFont)
                    .foregroundColor(AppTheme.onGlass)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
            }
            Spacer(minLength: 12)
            // Keep header minimal; remove chips to avoid truncation
            if let onShareAll = onShareAll {
                Button(action: { onShareAll(assets) }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .photoSheetCard(radius: PhotoSheetStyle.headerCornerRadius)
        .padding(.horizontal, PhotoSheetStyle.sectionHorizontalPadding)
    }

    private func chip(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private func weekdayString(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "E"
        return df.string(from: date)
    }
    private func dayTitle(from date: Date) -> String {
        let df = DateFormatter(); df.locale = Locale.current; df.dateFormat = "M/d"
        return df.string(from: date)
    }
    private func totalDurationLabel() -> String? {
        let sec = Int(assets.reduce(0.0) { $0 + $1.duration }.rounded())
        if sec <= 0 { return nil }
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct PhotoSheetView: View {
    @StateObject private var viewModel = PhotoSheetViewModel()
    @StateObject private var libraryViewModel = LibraryScreenViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var assetToPlay: IdentifiableAsset? = nil
    @State private var playAllAssets: [PHAsset]? = nil
    @State private var shareAssets: [PHAsset]? = nil
    @State private var assetToDelete: IdentifiableAsset? = nil
    @State private var showDeleteDialog: Bool = false
    @State private var assetListToPlay: IdentifiableAssetsWithIndex? = nil
    enum Tab: String, CaseIterable { case list = "リスト"; case calendar = "カレンダー" }
    @AppStorage("photoTab") private var selectedTabRaw: String = Tab.list.rawValue
    private var selectedTab: Tab {
        get { Tab(rawValue: selectedTabRaw) ?? .list }
        set { selectedTabRaw = newValue.rawValue }
    }
    @Environment(\.horizontalSizeClass) private var hSize


    var body: some View {
        NavigationView {
            TabView(selection: Binding(get: { selectedTab }, set: { selectedTabRaw = $0.rawValue })) {
                LibraryListView(
                    groups: viewModel.visibleListGroups,
                    photoViewModel: viewModel,
                    libraryViewModel: libraryViewModel,
                    onPlayAll: { assets in self.playAllAssets = sortOldestFirst(assets) },
                    onShareAll: { assets in self.shareAssets = sortOldestFirst(assets) },
                    onTapAsset: { asset, groupAssets in
                        if let idx = groupAssets.firstIndex(of: asset) {
                            self.assetListToPlay = IdentifiableAssetsWithIndex(assets: groupAssets, index: idx)
                        } else {
                            self.assetToPlay = IdentifiableAsset(asset: asset)
                        }
                    },
                    onDeleteAsset: { asset in
                        self.assetToDelete = IdentifiableAsset(asset: asset)
                        self.showDeleteDialog = true
                    },
                    onGroupAppear: { group in
                        viewModel.loadMoreListIfNeeded(currentGroup: group)
                    }
                )
                .tabItem { Label("リスト", systemImage: "list.bullet") }
                .tag(Tab.list)

                LibraryCalendarView(
                    photoViewModel: viewModel,
                    onTapDay: { assets in self.playAllAssets = sortOldestFirst(assets) },
                    onShareDay: { assets in self.shareAssets = sortOldestFirst(assets) },
                    onDeleteDay: { assets in self.delete(assets: assets) },
                    onPlayMonth: { assets in self.playAllAssets = sortOldestFirst(assets) },
                    onShareMonth: { assets in self.shareAssets = sortOldestFirst(assets) },
                    onDeleteMonth: { assets in
                        self.bulkDeleteAssets = assets
                        self.showBulkDeleteDialog = true
                    }
                )
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(Tab.calendar)

            }
            .navigationTitle(libraryViewModel.isSelecting ? "選択中 (\(libraryViewModel.selectedIds.count))" : titleForTab(selectedTab))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                LibrarySelectionToolbar(
                    isSelecting: $libraryViewModel.isSelecting,
                    selectedTab: Binding(get: { selectedTab }, set: { selectedTabRaw = $0.rawValue }),
                    selectedCount: libraryViewModel.selectedIds.count,
                    onClose: { dismiss() },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            libraryViewModel.clearSelection()
                        }
                    },
                    onShare: {
                        let assets = libraryViewModel.selectedIds.compactMap { id in findAsset(by: id) }
                        if !assets.isEmpty { shareAssets = assets }
                    },
                    onDelete: {
                        let assets = libraryViewModel.selectedIds.compactMap { id in findAsset(by: id) }
                        self.bulkDeleteAssets = assets
                        self.showBulkDeleteDialog = true
                    },
                    onEnterSelection: {
                        withAnimation(.easeInOut(duration: 0.15)) { libraryViewModel.isSelecting = true }
                        FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                    }
                )
            }
            // Hidden watcher to auto-exit selection when empty
            .background(monitorSelectionAutoExit())
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Loading overlay when fetching from Photos
            .overlay {
                if viewModel.isFetching {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            if Tab(rawValue: selectedTabRaw) == nil {
                selectedTabRaw = Tab.list.rawValue
            }
            viewModel.fetchAllVideos()
        }
        .sheet(item: $assetToPlay) { identifiableAsset in
            PlayerView(asset: identifiableAsset.asset)
        }
        .sheet(item: Binding(get: {
            playAllAssets.map { IdentifiableAssets(assets: $0) }
        }, set: { newValue in
            playAllAssets = newValue?.assets
        })) { identifiable in
            DayPlayerView(assets: identifiable.assets)
        }
        .sheet(item: Binding(get: {
            shareAssets.map { IdentifiableAssets(assets: $0) }
        }, set: { newValue in
            shareAssets = newValue?.assets
        })) { identifiable in
            ShareDayView(assets: identifiable.assets)
        }
        .sheet(item: $assetListToPlay) { identifiable in
            PagedPlayerView(assets: identifiable.assets, index: identifiable.index)
        }
        .confirmationDialog("この動画を削除しますか？", isPresented: $showDeleteDialog) {
            Button("削除", role: .destructive) {
                if let item = assetToDelete {
                    viewModel.delete(asset: item.asset) { _ in }
                }
                assetToDelete = nil
            }
            Button("キャンセル", role: .cancel) { assetToDelete = nil }
        } message: { Text("この操作は取り消せません") }
        .confirmationDialog(bulkDeleteTitle(), isPresented: $showBulkDeleteDialog) {
            Button("削除", role: .destructive) {
                delete(assets: bulkDeleteAssets)
                bulkDeleteAssets = []
            }
            Button("キャンセル", role: .cancel) { bulkDeleteAssets = [] }
        } message: { Text(bulkDeleteMessage()) }
    }

    private func sortOldestFirst(_ assets: [PHAsset]) -> [PHAsset] {
        return assets.sorted { (a, b) in
            let ad = a.creationDate ?? .distantPast
            let bd = b.creationDate ?? .distantPast
            return ad < bd
        }
    }

    private func titleForTab(_ tab: Tab) -> String { tab == .list ? "動画" : "カレンダー" }

    private func findAsset(by id: String) -> PHAsset? {
        for group in viewModel.groupedVideos {
            if let asset = group.assets.first(where: { $0.localIdentifier == id }) {
                return asset
            }
        }
        return nil
    }

    private func delete(assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if !success, let error = error {
                    AppLog.export.error("Failed to delete assets: \(error.localizedDescription)")
                }
                self.libraryViewModel.clearSelection()
                self.viewModel.fetchAllVideos()
            }
        }
    }

    @State private var showBulkDeleteDialog: Bool = false
    @State private var bulkDeleteAssets: [PHAsset] = []

    private func bulkDeleteTitle() -> String { "選択した動画を削除しますか？" }
    private func bulkDeleteMessage() -> String {
        let count = bulkDeleteAssets.count
        let total = Int(bulkDeleteAssets.reduce(0.0) { $0 + $1.duration }.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let dur = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return "件数: \(count)  合計: \(dur)\nこの操作は取り消せません"
    }
}

// MARK: - Selection helpers (auto-exit)
extension PhotoSheetView {
    // Auto-exit selection when there are no selections left
    private func monitorSelectionAutoExit() -> some View {
        EmptyView()
            .onChange(of: libraryViewModel.selectedIds) { _, newValue in
                if libraryViewModel.isSelecting && newValue.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if libraryViewModel.selectedIds.isEmpty {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                libraryViewModel.isSelecting = false
                            }
                        }
                    }
                }
            }
    }
}

struct DaySectionView: View {
    let group: DayVideoGroup
    @ObservedObject var viewModel: PhotoSheetViewModel
    var onPlayAll: ([PHAsset]) -> Void
    var onShareAll: ([PHAsset]) -> Void
    var onTapAsset: (PHAsset) -> Void
    var onDeleteAsset: (PHAsset) -> Void
    @Binding var isSelecting: Bool
    @Binding var selectedIds: Set<String>

    var body: some View {
        Section(header: DateHeaderView(date: group.date, assets: group.assets, onPlayAll: onPlayAll, onShareAll: onShareAll)) {
            let columns: [GridItem] = [GridItem(.adaptive(minimum: 100))]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(group.assets, id: \.self) { asset in
                    Button(action: {
                        if isSelecting {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                if selectedIds.contains(asset.localIdentifier) {
                                    selectedIds.remove(asset.localIdentifier)
                                } else {
                                    selectedIds.insert(asset.localIdentifier)
                                }
                            }
                            FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                        } else {
                            onTapAsset(asset)
                        }
                    }) {
                        ZStack {
                            // Thumbnail
                            VideoThumbnailView(asset: asset, viewModel: viewModel)

                            // Selected overlay (border and tint)
                            if isSelecting && selectedIds.contains(asset.localIdentifier) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.accentColor, lineWidth: 3)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                            }

                            // Top-right indicator: play when not selecting, check/circle when selecting
                            VStack {
                                HStack {
                                    Spacer()
                                    ZStack {
                                        if isSelecting {
                                            let selected = selectedIds.contains(asset.localIdentifier)
                                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(selected ? .accentColor : .white)
                                                .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
                                        }
                                    }
                                    .padding(6)
                                }
                                Spacer()
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .highPriorityGesture(LongPressGesture(minimumDuration: 0.3).onEnded { _ in
                        if !isSelecting {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                isSelecting = true
                                selectedIds.insert(asset.localIdentifier)
                            }
                            FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                        }
                    })
                    // Simplify: no per-item context menu in list for lighter UI
                }
            }
            .padding(.horizontal, PhotoSheetStyle.sectionHorizontalPadding)
        }
        .modifier(DayCachingModifier(viewModel: viewModel, assets: group.assets))
    }
}

private struct DayCachingModifier: ViewModifier {
    @ObservedObject var viewModel: PhotoSheetViewModel
    let assets: [PHAsset]
    @State private var didCache = false
    private let targetSize = CGSize(width: 160, height: 160)
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Start bounded preheat while this section is visible.
                if !didCache {
                    viewModel.startCaching(assets: assets, targetSize: targetSize)
                    didCache = true
                }
            }
            .onDisappear {
                if didCache {
                    viewModel.stopCaching(assets: assets, targetSize: targetSize)
                    didCache = false
                }
            }
    }
}

// Wrapper to make PHAsset identifiable for use in sheets
struct IdentifiableAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct IdentifiableAssets: Identifiable {
    let assets: [PHAsset]
    var id: String { assets.map { $0.localIdentifier }.joined(separator: ",") }
}

struct IdentifiableAssetsWithIndex: Identifiable {
    let assets: [PHAsset]
    let index: Int
    var id: String { assets.map { $0.localIdentifier }.joined(separator: ",") + "@\(index)" }
}
