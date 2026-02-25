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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.stroke, lineWidth: 1)
                    )

                if let date = date, let rep = assets.first {
                    // Thumbnail
                    VideoThumbnailView(asset: rep, viewModel: viewModel, size: side, showsDurationBadge: false)

                    // Simple day number (top-left) — avoid truncation
                    VStack {
                        HStack {
                            Text(dayNumber(from: date))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .allowsTightening(true)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.25))
                                .clipShape(Capsule())
                                .padding(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                } else if let date = date { // day with no assets (for 7-col calendar)
                    VStack {
                        HStack {
                            Text(dayNumber(from: date))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .allowsTightening(true)
                                .foregroundColor(.secondary)
                                .padding(4)
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
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            ScrollView {
                LazyVStack(spacing: PhotoSheetStyle.sectionSpacing) {
                    ForEach(months) { month in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Text(String(format: "%d年%d月", month.year, month.month))
                                    .font(AppTheme.titleFont)
                                    .foregroundColor(AppTheme.onGlass)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .allowsTightening(true)
                                    .layoutPriority(1)
                                Spacer(minLength: 12)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .photoSheetCard(radius: PhotoSheetStyle.headerCornerRadius)
                            .padding(.horizontal, PhotoSheetStyle.sectionHorizontalPadding)
                            // 7-column calendar for all widths
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
                                            .foregroundColor(AppTheme.onGlass.opacity(0.72))
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
                                        DayCellView(date: date, assets: assets, viewModel: viewModel)
                                            .frame(width: cell)
                                            .opacity(assets.isEmpty ? 0.9 : 1.0)
                                            .onTapGesture {
                                                guard !assets.isEmpty else { return }
                                                onTapDay(sortedOldest(assets))
                                            }
                                            .contextMenu {
                                                if !assets.isEmpty {
                                                    Button { onTapDay(sortedOldest(assets)) } label: { Label("再生", systemImage: "play.fill") }
                                                    if let onShareDay = onShareDay { Button { onShareDay(sortedOldest(assets)) } label: { Label("書き出し", systemImage: "square.and.arrow.up") } }
                                                }
                                            }
                                    }
                                }
                        }
                        .padding(.horizontal, AppTheme.spacingS)
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
                .padding(.bottom, PhotoSheetStyle.contentBottomInset)
            }
        }
    }

    private func sortedOldest(_ assets: [PHAsset]) -> [PHAsset] {
        assets.sorted { (a, b) in (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast) }
    }

    private func allAssets(in month: MonthSection) -> [PHAsset] {
        month.assetsByDay.keys.sorted().flatMap { day in month.assetsByDay[day] ?? [] }
    }

    private func weekdaySymbols() -> [String] {
        // Keep Japanese weekday labels for a consistent Japanese UI.
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        let start = Calendar.current.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func totalDurationLabel(for assets: [PHAsset]) -> String? {
        let sec = Int(assets.reduce(0.0) { $0 + $1.duration }.rounded())
        if sec <= 0 { return nil }
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
}
