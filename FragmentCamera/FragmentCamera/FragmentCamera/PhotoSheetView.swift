import SwiftUI
import Photos
import CoreLocation

// A view for a single video thumbnail
struct VideoThumbnailView: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var thumbnail: UIImage? = nil
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
            Group {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color(uiColor: .secondarySystemBackground))
                }
            }
            if showsDurationBadge, let durLabel = durationLabel {
                badge(text: durLabel)
                    .padding(6)
            }
        }
        .frame(width: size ?? 100, height: size ?? 100)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        .onAppear {
            // Request at 2x of intended display size for retina sharpness
            let side = (size ?? 100) * 2
            let target = CGSize(width: side, height: side)
            viewModel.loadThumbnail(for: asset, targetSize: target) { image in
                self.thumbnail = image
            }
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

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
    
    init(date: Date, assets: [PHAsset], viewModel: PhotoSheetViewModel, onPlayAll: (([PHAsset]) -> Void)? = nil, onShareAll: (([PHAsset]) -> Void)? = nil) {
        self.date = date
        self.assets = assets
        self.onPlayAll = onPlayAll
        self.onShareAll = onShareAll
    }

    var body: some View {
        HStack {
            Text(dateFormatter.string(from: date))
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            Button(action: { onPlayAll?(assets) }) {
                Image(systemName: "play.fill")
            }
            .padding(.trailing, 8)
            Button(action: { onShareAll?(assets) }) {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 8)
    }
}

struct PhotoSheetView: View {
    @StateObject private var viewModel = PhotoSheetViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var assetToPlay: IdentifiableAsset? = nil
    @State private var playAllAssets: [PHAsset]? = nil
    @State private var shareAssets: [PHAsset]? = nil
    @State private var assetToDelete: IdentifiableAsset? = nil
    @State private var showDeleteDialog: Bool = false
    @State private var assetListToPlay: IdentifiableAssetsWithIndex? = nil
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<String> = []
    enum Tab: String, CaseIterable { case list = "リスト"; case calendar = "カレンダー"; case map = "マップ" }
    @AppStorage("photoTab") private var selectedTabRaw: String = Tab.list.rawValue
    private var selectedTab: Tab {
        get { Tab(rawValue: selectedTabRaw) ?? .list }
        set { selectedTabRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationView {
            TabView(selection: Binding(get: { selectedTab }, set: { selectedTabRaw = $0.rawValue })) {
                // Days/List
                ScrollView {
                    ForEach(viewModel.groupedVideos) { group in
                        DaySectionView(
                            group: group,
                            viewModel: viewModel,
                            onPlayAll: { assets in self.playAllAssets = sortOldestFirst(assets) },
                            onShareAll: { assets in self.shareAssets = sortOldestFirst(assets) },
                            onTapAsset: { asset in
                                if let idx = group.assets.firstIndex(of: asset) {
                                    self.assetListToPlay = IdentifiableAssetsWithIndex(assets: group.assets, index: idx)
                                } else {
                                    self.assetToPlay = IdentifiableAsset(asset: asset)
                                }
                            },
                            onDeleteAsset: { asset in
                                self.assetToDelete = IdentifiableAsset(asset: asset)
                                self.showDeleteDialog = true
                            },
                            isSelecting: $isSelecting,
                            selectedIds: $selectedIds
                        )
                    }
                }
                .tabItem { Label("リスト", systemImage: "list.bullet") }
                .tag(Tab.list)

                // Calendar
                MonthGridView(
                    months: viewModel.buildMonthSections(),
                    viewModel: viewModel,
                    onTapDay: { assets in self.playAllAssets = sortOldestFirst(assets) },
                    onShareDay: { assets in self.shareAssets = sortOldestFirst(assets) },
                    onDeleteDay: { assets in self.delete(assets: assets) },
                    onPlayMonth: { assets in self.playAllAssets = sortOldestFirst(assets) },
                    onShareMonth: { assets in self.shareAssets = sortOldestFirst(assets) },
                    isSelecting: $isSelecting,
                    selectedIds: $selectedIds
                )
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(Tab.calendar)

                // Map
                MapVideosView(viewModel: viewModel)
                    .tabItem { Label("マップ", systemImage: "map") }
                    .tag(Tab.map)
            }
            .navigationTitle(isSelecting ? "選択中 (\(selectedIds.count))" : titleForTab(selectedTab))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) { Image(systemName: "xmark.circle.fill") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if isSelecting {
                            // Selection count badge
                            Text("\(selectedIds.count)")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .contentTransition(.numericText())
                            // Select all / clear
                            Button {
                                let target = allSelectableIds()
                                let allSelected = target.isSubset(of: selectedIds)
                                if allSelected { selectedIds.subtract(target) } else { selectedIds.formUnion(target) }
                            } label: {
                                Image(systemName: allSelectableIds().isSubset(of: selectedIds) ? "checkmark.circle.trianglebadge.exclamationmark" : "checkmark.circle")
                            }
                            Button {
                                let assets = selectedIds.compactMap { id in findAsset(by: id) }
                                if !assets.isEmpty { shareAssets = assets }
                            } label: { Image(systemName: "square.and.arrow.up") }
                            .disabled(selectedIds.isEmpty)

                            Button(role: .destructive) {
                                let assets = selectedIds.compactMap { id in findAsset(by: id) }
                                self.bulkDeleteAssets = assets
                                self.showBulkDeleteDialog = true
                            } label: { Image(systemName: "trash") }
                            .disabled(selectedIds.isEmpty)
                            // Exit selection
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isSelecting = false
                                    selectedIds.removeAll()
                                }
                            }) { Image(systemName: "checkmark.circle") }
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) { isSelecting = true }
                                FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                            }) { Image(systemName: "checkmark.circle") }
                        }
                    }
                }
            }
        }
        .onAppear {
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

    private func titleForTab(_ tab: Tab) -> String { tab == .list ? "動画" : (tab == .calendar ? "カレンダー" : "マップ") }

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
                    print("Failed to delete assets: \(error.localizedDescription)")
                }
                self.selectedIds.removeAll()
                self.isSelecting = false
                self.viewModel.fetchAllVideos()
            }
        }
    }

    private func allSelectableIds() -> Set<String> {
        // Use all assets in groupedVideos (covers both list and calendar datasets)
        let ids = viewModel.groupedVideos.flatMap { $0.assets }.map { $0.localIdentifier }
        return Set(ids)
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
        Section(header: DateHeaderView(date: group.date, assets: group.assets, viewModel: viewModel, onPlayAll: onPlayAll, onShareAll: onShareAll)) {
            let columns: [GridItem] = [GridItem(.adaptive(minimum: 100))]
            LazyVGrid(columns: columns, spacing: 2) {
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
                                                .symbolEffect(.bounce, value: selected)
                                        } else {
                                            Circle().fill(.ultraThinMaterial)
                                                .frame(width: 22, height: 22)
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(6)
                                }
                                Spacer()
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.3) {
                        if !isSelecting {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                isSelecting = true
                                selectedIds.insert(asset.localIdentifier)
                            }
                            FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) { onDeleteAsset(asset) } label: { Label("削除", systemImage: "trash") }
                    }
                }
            }
        }
        .onAppear {
            // Pre-cache this day's assets at 2x of 100pt
            viewModel.startCaching(assets: group.assets, targetSize: CGSize(width: 200, height: 200))
        }
        .onDisappear {
            viewModel.stopCaching(assets: group.assets, targetSize: CGSize(width: 200, height: 200))
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
