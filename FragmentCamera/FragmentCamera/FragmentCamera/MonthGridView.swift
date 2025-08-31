import SwiftUI
import Photos

struct MonthSection: Identifiable, Hashable {
    let id: String
    let year: Int
    let month: Int
    let firstDate: Date
    let numberOfDays: Int
    let leadingEmpty: Int // number of empty cells before day 1
    let assetsByDay: [Int: [PHAsset]] // day (1-based) -> assets
}

struct DayCellView: View {
    let day: Int?
    let assets: [PHAsset]
    @ObservedObject var viewModel: PhotoSheetViewModel
    let isSelecting: Bool
    @Binding var selectedIds: Set<String>
    let cellSize: CGFloat

    private var isSelectedAll: Bool {
        guard !assets.isEmpty else { return false }
        return Set(assets.map { $0.localIdentifier }).isSubset(of: selectedIds)
    }
    private var isPartiallySelected: Bool {
        let set = Set(assets.map { $0.localIdentifier })
        return !assets.isEmpty && !set.isSubset(of: selectedIds) && !set.isDisjoint(with: selectedIds)
    }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if let day = day, let rep = assets.first {
                // Thumbnail
                VideoThumbnailView(asset: rep, viewModel: viewModel, size: cellSize)

                // Date label (top-left)
                VStack {
                    HStack {
                        Text("\(day)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(6)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                // Count badge (bottom-right)
                if assets.count > 1 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(assets.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(6)
                        }
                    }
                    .allowsHitTesting(false)
                }

                // Selection overlay
                if isSelecting {
                    if isSelectedAll || isPartiallySelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 3)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    }
                    VStack {
                        HStack {
                            Spacer()
                            let iconName: String = isSelectedAll ? "checkmark.circle.fill" : (isPartiallySelected ? "minus.circle.fill" : "circle")
                            Image(systemName: iconName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor((isSelectedAll || isPartiallySelected) ? .accentColor : .white)
                                .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
                                .padding(6)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            } else if let day = day { // day with no assets
                Text("\(day)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } // else leading empty cell
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MonthGridView: View {
    let months: [MonthSection]
    @ObservedObject var viewModel: PhotoSheetViewModel
    var onTapDay: ([PHAsset]) -> Void
    var onShareDay: (([PHAsset]) -> Void)? = nil
    var onDeleteDay: (([PHAsset]) -> Void)? = nil
    var isSelecting: Bool
    @Binding var selectedIds: Set<String>

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let columnsCount = 7
            let totalSpacing = spacing * CGFloat(columnsCount - 1)
            let horizontalPadding: CGFloat = 16
            let available = max(0, proxy.size.width - horizontalPadding - totalSpacing)
            let cell = floor(available / CGFloat(columnsCount))

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(months) { month in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(month.year)年\(month.month)月")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: spacing, alignment: .center), count: columnsCount), spacing: spacing) {
                                // Leading empty days
                                ForEach(0..<month.leadingEmpty, id: \.self) { _ in
                                    Color.clear
                                        .frame(width: cell, height: cell)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                // Days of month
                                ForEach(1...month.numberOfDays, id: \.self) { d in
                                    let assets = month.assetsByDay[d] ?? []
                                    DayCellView(day: d, assets: assets, viewModel: viewModel, isSelecting: isSelecting, selectedIds: $selectedIds, cellSize: cell)
                                        .onTapGesture {
                                            if isSelecting {
                                                toggleSelection(for: assets)
                                            } else {
                                                onTapDay(sortedOldest(assets))
                                            }
                                        }
                                        .contextMenu {
                                            if !assets.isEmpty {
                                                Button { onTapDay(sortedOldest(assets)) } label: { Label("再生", systemImage: "play.fill") }
                                                if let onShareDay = onShareDay { Button { onShareDay(sortedOldest(assets)) } label: { Label("共有", systemImage: "square.and.arrow.up") } }
                                                if let onDeleteDay = onDeleteDay { Button(role: .destructive) { onDeleteDay(assets) } label: { Label("削除", systemImage: "trash") } }
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, horizontalPadding / 2)
                    }
                }
            }
        }
    }

    private func sortedOldest(_ assets: [PHAsset]) -> [PHAsset] {
        assets.sorted { (a, b) in (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast) }
    }

    private func toggleSelection(for assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let ids = Set(assets.map { $0.localIdentifier })
        let allSelected = ids.isSubset(of: selectedIds)
        if allSelected {
            selectedIds.subtract(ids)
        } else {
            selectedIds.formUnion(ids)
        }
    }
}
