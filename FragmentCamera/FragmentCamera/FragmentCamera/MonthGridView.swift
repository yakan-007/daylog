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
    let date: Date?
    let assets: [PHAsset]
    @ObservedObject var viewModel: PhotoSheetViewModel
    let isSelecting: Bool
    @Binding var selectedIds: Set<String>

    private var isSelectedAll: Bool {
        guard !assets.isEmpty else { return false }
        return Set(assets.map { $0.localIdentifier }).isSubset(of: selectedIds)
    }
    private var isPartiallySelected: Bool {
        let set = Set(assets.map { $0.localIdentifier })
        return !assets.isEmpty && !set.isSubset(of: selectedIds) && !set.isDisjoint(with: selectedIds)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                if let date = date, let rep = assets.first {
                    // Thumbnail (hide per-clip duration to avoid confusion)
                    VideoThumbnailView(asset: rep, viewModel: viewModel, size: side, showsDurationBadge: false)

                    // Weekday over Day (top-left, stacked)
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(weekdayShort(from: date))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(dayNumber(from: date))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)

                    // Count badge (top-right) when not selecting
                    if !isSelecting && assets.count > 1 {
                        VStack {
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
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }

                    // Total duration (bottom-right)
                    if let label = totalDurationLabel() {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(label)
                                    .font(.system(size: 10, weight: .semibold))
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
                } else if let date = date { // day with no assets (for 7-col calendar)
                    VStack {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(weekdayShort(from: date))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(dayNumber(from: date))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                } // else leading empty cell
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dayNumber(from date: Date) -> String {
        let d = Calendar.current.component(.day, from: date)
        return String(d)
    }
    private func weekdayShort(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "EEE" // localized short weekday
        return df.string(from: date)
    }

    private func totalDurationLabel() -> String? {
        guard !assets.isEmpty else { return nil }
        let total = Int(assets.reduce(0.0) { $0 + $1.duration }.rounded())
        if total <= 0 { return nil }
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        else { return String(format: "%d:%02d", m, s) }
    }
}

struct MonthGridView: View {
    let months: [MonthSection]
    @ObservedObject var viewModel: PhotoSheetViewModel
    var onTapDay: ([PHAsset]) -> Void
    var onShareDay: (([PHAsset]) -> Void)? = nil
    var onDeleteDay: (([PHAsset]) -> Void)? = nil
    var onPlayMonth: (([PHAsset]) -> Void)? = nil
    var onShareMonth: (([PHAsset]) -> Void)? = nil
    var onDeleteMonth: (([PHAsset]) -> Void)? = nil
    @Binding var isSelecting: Bool
    @Binding var selectedIds: Set<String>
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let useAdaptive = hSize == .compact
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(months) { month in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(month.year)年\(month.month)月")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Spacer()
                                if useAdaptive {
                                    // Compact width: collapse into menu to save space
                                    Menu {
                                        if let onPlayMonth = onPlayMonth { Button { onPlayMonth(sortedOldest(allAssets(in: month))) } label: { Label("この月を再生", systemImage: "play.fill") } }
                                        if let onShareMonth = onShareMonth { Button { onShareMonth(sortedOldest(allAssets(in: month))) } label: { Label("この月を共有", systemImage: "square.and.arrow.up") } }
                                        if let onDeleteMonth = onDeleteMonth { Button(role: .destructive) { onDeleteMonth(allAssets(in: month)) } label: { Label("この月を削除", systemImage: "trash") } }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                } else {
                                    HStack(spacing: 10) {
                                        if let onPlayMonth = onPlayMonth {
                                            Button(action: { onPlayMonth(sortedOldest(allAssets(in: month))) }) {
                                                Label("再生", systemImage: "play.fill")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        if let onShareMonth = onShareMonth {
                                            Button(action: { onShareMonth(sortedOldest(allAssets(in: month))) }) {
                                                Label("共有", systemImage: "square.and.arrow.up")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        if let onDeleteMonth = onDeleteMonth {
                                            Button(role: .destructive, action: { onDeleteMonth(allAssets(in: month)) }) {
                                                Label("削除", systemImage: "trash")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                            if useAdaptive {
                                // Adaptive grid: only existing days, bigger tiles, vertical scroll
                                let days = month.assetsByDay.keys.sorted()
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: spacing)], spacing: spacing) {
                                    ForEach(days, id: \.self) { d in
                                        let assets = month.assetsByDay[d] ?? []
                                        let date = Calendar.current.date(byAdding: .day, value: d - 1, to: month.firstDate)!
                                        DayCellView(date: date, assets: assets, viewModel: viewModel, isSelecting: isSelecting, selectedIds: $selectedIds)
                                            .onTapGesture { handleTap(assets) }
                                            .onLongPressGesture(minimumDuration: 0.3) {
                                                if !isSelecting {
                                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                                        isSelecting = true
                                                        toggleSelection(for: assets)
                                                    }
                                                    FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                                                }
                                            }
                                            .contextMenu { contextMenu(assets) }
                                    }
                                }
                            } else {
                                // 7-column calendar for iPad/regular
                                let columnsCount = 7
                                let totalSpacing = spacing * CGFloat(columnsCount - 1)
                                let horizontalPadding: CGFloat = 16
                                let available = max(0, proxy.size.width - horizontalPadding - totalSpacing)
                                let cell = floor(available / CGFloat(columnsCount))
                                // Weekday header row
                                HStack(spacing: spacing) {
                                    ForEach(weekdaySymbols(), id: \.self) { wd in
                                        Text(wd)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .frame(width: cell)
                                    }
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: spacing, alignment: .center), count: columnsCount), spacing: spacing) {
                                    // Leading empty days
                                    ForEach(0..<month.leadingEmpty, id: \.self) { _ in
                                        Color.clear
                                            .frame(width: cell)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    // Days of month
                                    ForEach(1...month.numberOfDays, id: \.self) { d in
                                        let assets = month.assetsByDay[d] ?? []
                                        let date = Calendar.current.date(byAdding: .day, value: d - 1, to: month.firstDate)!
                                        DayCellView(date: date, assets: assets, viewModel: viewModel, isSelecting: isSelecting, selectedIds: $selectedIds)
                                            .frame(width: cell)
                                            .onTapGesture { handleTap(assets) }
                                            .onLongPressGesture(minimumDuration: 0.3) {
                                                if !isSelecting {
                                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                                        isSelecting = true
                                                        toggleSelection(for: assets)
                                                    }
                                                    FeedbackManager.shared.triggerFeedback(soundEnabled: false)
                                                }
                                            }
                                            .contextMenu { contextMenu(assets) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .onAppear {
                            // Pre-cache month assets with a reasonable default size for current width
                            let approxCell = max(100, min(180, proxy.size.width / 3 - spacing * 2))
                            let ts = CGSize(width: approxCell * 2, height: approxCell * 2)
                            viewModel.startCaching(assets: allAssets(in: month), targetSize: ts)
                        }
                        .onDisappear {
                            let approxCell = max(100, min(180, proxy.size.width / 3 - spacing * 2))
                            let ts = CGSize(width: approxCell * 2, height: approxCell * 2)
                            viewModel.stopCaching(assets: allAssets(in: month), targetSize: ts)
                        }
                    }
                }
            }
        }
    }

    private func handleTap(_ assets: [PHAsset]) {
        if isSelecting {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { toggleSelection(for: assets) }
            FeedbackManager.shared.triggerFeedback(soundEnabled: false)
        } else {
            onTapDay(sortedOldest(assets))
        }
    }
    @ViewBuilder private func contextMenu(_ assets: [PHAsset]) -> some View {
        if !assets.isEmpty {
            Button { onTapDay(sortedOldest(assets)) } label: { Label("再生", systemImage: "play.fill") }
            if let onShareDay = onShareDay { Button { onShareDay(sortedOldest(assets)) } label: { Label("共有", systemImage: "square.and.arrow.up") } }
            if let onDeleteDay = onDeleteDay { Button(role: .destructive) { onDeleteDay(assets) } label: { Label("削除", systemImage: "trash") } }
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

    private func allAssets(in month: MonthSection) -> [PHAsset] {
        month.assetsByDay.keys.sorted().flatMap { day in month.assetsByDay[day] ?? [] }
    }

    private func weekdaySymbols() -> [String] {
        var df = DateFormatter(); df.locale = Locale.current
        // Start from calendar.firstWeekday to match layout
        let symbols = df.shortWeekdaySymbols ?? ["日","月","火","水","木","金","土"]
        let start = Calendar.current.firstWeekday - 1 // convert to 0-based
        return Array(symbols[start...] + symbols[..<start])
    }
}
