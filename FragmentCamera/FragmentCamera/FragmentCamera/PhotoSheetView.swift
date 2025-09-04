import SwiftUI
import Photos
import CoreLocation

// A view for a single video thumbnail
struct VideoThumbnailView: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var thumbnail: UIImage? = nil
    @State private var isLoaded: Bool = false
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        .onAppear {
            // Request at 2x of intended display size for retina sharpness
            let side = (size ?? 100) * 2
            let target = CGSize(width: side, height: side)
            viewModel.loadThumbnail(for: asset, targetSize: target) { image in
                self.thumbnail = image
                withAnimation(.easeInOut(duration: 0.15)) { self.isLoaded = (image != nil) }
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
    @Environment(\.horizontalSizeClass) private var hSize

    // Default init is sufficient

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekdayString(from: date))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(dayTitle(from: date))
                    .font(.system(size: 20, weight: .bold))
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let dur = totalDurationLabel() { chip(text: dur) }
            }
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
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
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
        let df = DateFormatter(); df.locale = Locale.current; df.dateFormat = "EEE"
        return df.string(from: date)
    }
    private func dayTitle(from date: Date) -> String {
        let df = DateFormatter(); df.locale = Locale.current; df.dateFormat = "yyyy/MM/dd"
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
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        NavigationView {
            TabView(selection: Binding(get: { selectedTab }, set: { selectedTabRaw = $0.rawValue })) {
                // Days/List (simple, non-sticky headers)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
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
                }
                .refreshable { viewModel.fetchAllVideos() }
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
                    onDeleteMonth: { assets in
                        self.bulkDeleteAssets = assets
                        self.showBulkDeleteDialog = true
                    },
                    isSelecting: $isSelecting,
                    selectedIds: $selectedIds
                )
                .refreshable { viewModel.fetchAllVideos() }
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
                // Leading: Close or Cancel (exit selection)
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelecting {
                        Button("キャンセル") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isSelecting = false
                                selectedIds.removeAll()
                            }
                        }
                        .accessibilityLabel("選択をやめる")
                    } else {
                        Button(action: { dismiss() }) { toolbarIcon("xmark.circle.fill") }
                        .accessibilityLabel("閉じる")
                    }
                }
                // Trailing: Enter selection OR (share, delete)
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelecting {
                        HStack(spacing: 14) {
                            Button {
                                let assets = selectedIds.compactMap { id in findAsset(by: id) }
                                if !assets.isEmpty { shareAssets = assets }
                            } label: { toolbarIcon("square.and.arrow.up") }
                            .disabled(selectedIds.isEmpty)
                            .accessibilityLabel("選択した動画を書き出す")

                            Button(role: .destructive) {
                                let assets = selectedIds.compactMap { id in findAsset(by: id) }
                                self.bulkDeleteAssets = assets
                                self.showBulkDeleteDialog = true
                            } label: { toolbarIcon("trash") }
                            .disabled(selectedIds.isEmpty)
                            .accessibilityLabel("選択した動画を削除")
                        }
                    } else {
                        Button("選択") {
                            withAnimation(.easeInOut(duration: 0.15)) { isSelecting = true }
                            FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                        }
                        .accessibilityLabel("選択モードにする")
                    }
                }
            }
            // Hidden watcher to auto-exit selection when empty
            .background(monitorSelectionAutoExit())
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

    // Standardized toolbar icon with minimum tap target
    @ViewBuilder
    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44, alignment: .center)
            .contentShape(Rectangle())
    }

    

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

// MARK: - Selection helpers (auto-exit)
extension PhotoSheetView {
    // Auto-exit selection when there are no selections left
    private func monitorSelectionAutoExit() -> some View {
        EmptyView()
            .onChange(of: selectedIds) { _, newValue in
                if isSelecting && newValue.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if selectedIds.isEmpty {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isSelecting = false
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
                            onPlayAll(group.assets)
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
        }
        .modifier(DayCachingModifier(viewModel: viewModel, assets: group.assets))
    }
}

private struct DayCachingModifier: ViewModifier {
    @ObservedObject var viewModel: PhotoSheetViewModel
    let assets: [PHAsset]
    @State private var didCache = false
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Avoid start/stop thrash during sticky headers: cache once
                if !didCache {
                    viewModel.startCaching(assets: assets, targetSize: CGSize(width: 200, height: 200))
                    didCache = true
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
