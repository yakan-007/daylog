import SwiftUI
import Photos
import CoreLocation

// A view for a single video thumbnail
struct VideoThumbnailView: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var thumbnail: UIImage? = nil
    let size: CGFloat?
    
    init(asset: PHAsset, viewModel: PhotoSheetViewModel, size: CGFloat? = nil) {
        self.asset = asset
        self.viewModel = viewModel
        self.size = size
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
            if let durLabel = durationLabel {
                badge(text: durLabel)
                    .padding(6)
            }
        }
        .frame(width: size ?? 100, height: size ?? 100)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        .onAppear {
            let size = CGSize(width: 200, height: 200)
            viewModel.loadThumbnail(for: asset, targetSize: size) { image in
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
    @State private var showMap = false
    @State private var playAllAssets: [PHAsset]? = nil
    @State private var shareAssets: [PHAsset]? = nil
    @State private var assetToDelete: IdentifiableAsset? = nil
    @State private var showDeleteDialog: Bool = false
    @State private var assetListToPlay: IdentifiableAssetsWithIndex? = nil
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<String> = []
    enum ViewMode: String, CaseIterable { case list = "リスト"; case calendar = "カレンダー" }
    @State private var viewMode: ViewMode = .list

    var body: some View {
        NavigationView {
            Group {
                if viewMode == .list {
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
                                isSelecting: isSelecting,
                                selectedIds: $selectedIds
                            )
                        }
                    }
                } else {
                    MonthGridView(
                        months: viewModel.buildMonthSections(),
                        viewModel: viewModel,
                        onTapDay: { assets in self.playAllAssets = sortOldestFirst(assets) },
                        onShareDay: { assets in self.shareAssets = sortOldestFirst(assets) },
                        onDeleteDay: { assets in self.delete(assets: assets) },
                        isSelecting: isSelecting,
                        selectedIds: $selectedIds
                    )
                }
            }
            .navigationTitle(isSelecting ? "選択中 (\(selectedIds.count))" : (viewMode == .list ? "動画" : "カレンダー"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isSelecting ? "完了" : "選択") {
                        isSelecting.toggle()
                        if !isSelecting { selectedIds.removeAll() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Picker("モード", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
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
                            Button {
                                let assets = selectedIds.compactMap { id in findAsset(by: id) }
                                if !assets.isEmpty { shareAssets = assets }
                            } label: { Image(systemName: "square.and.arrow.up") }
                            .disabled(selectedIds.isEmpty)

                            Button(role: .destructive) {
                                let assets = selectedIds.compactMap { id in findAsset(by: id) }
                                delete(assets: assets)
                            } label: { Image(systemName: "trash") }
                            .disabled(selectedIds.isEmpty)
                        } else {
                            Button { showMap = true } label: { Image(systemName: "map") }
                            Button("閉じる") { dismiss() }
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
        .sheet(isPresented: $showMap) {
            MapVideosView(viewModel: viewModel)
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
    }

    private func sortOldestFirst(_ assets: [PHAsset]) -> [PHAsset] {
        return assets.sorted { (a, b) in
            let ad = a.creationDate ?? .distantPast
            let bd = b.creationDate ?? .distantPast
            return ad < bd
        }
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
}

struct DaySectionView: View {
    let group: DayVideoGroup
    @ObservedObject var viewModel: PhotoSheetViewModel
    var onPlayAll: ([PHAsset]) -> Void
    var onShareAll: ([PHAsset]) -> Void
    var onTapAsset: (PHAsset) -> Void
    var onDeleteAsset: (PHAsset) -> Void
    var isSelecting: Bool = false
    @Binding var selectedIds: Set<String>

    var body: some View {
        Section(header: DateHeaderView(date: group.date, assets: group.assets, viewModel: viewModel, onPlayAll: onPlayAll, onShareAll: onShareAll)) {
            let columns: [GridItem] = [GridItem(.adaptive(minimum: 100))]
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(group.assets, id: \.self) { asset in
                    Button(action: {
                        if isSelecting {
                            if selectedIds.contains(asset.localIdentifier) {
                                selectedIds.remove(asset.localIdentifier)
                            } else {
                                selectedIds.insert(asset.localIdentifier)
                            }
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
                    .contextMenu {
                        Button(role: .destructive) { onDeleteAsset(asset) } label: { Label("削除", systemImage: "trash") }
                    }
                }
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
