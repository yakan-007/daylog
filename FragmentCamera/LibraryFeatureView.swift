import Photos
import SwiftUI

struct DaylogLibrarySheetView: View {
    @ObservedObject var viewModel: LibraryFeatureViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    libraryHeader

                    if viewModel.sections.isEmpty, !viewModel.isRefreshing {
                        emptyState
                    } else {
                        ForEach(viewModel.sections) { section in
                            DaySectionCard(
                                section: section,
                                viewModel: viewModel
                            )
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentSection: section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.92), Color(hex: 0x131313)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("日別ライブラリ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(AppTheme.onGlass)
                }
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近の記録")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.onGlass)
            Text("日ごとのまとまりで、すぐ再生できます。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.onGlass.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Text("まだ記録がありません")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.onGlass)
            Text("まずは1本だけ撮ってみましょう。保存されるとここに日ごとのまとまりで並びます。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.onGlass.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

private struct DaySectionCard: View {
    let section: DaySection
    @ObservedObject var viewModel: LibraryFeatureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DaylogFormatters.weekdayFormatter.string(from: section.date).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                    Text(DaylogFormatters.dayTitleFormatter.string(from: section.date))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.onGlass)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(section.clipCount)本")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.onGlass)
                    Text(DaylogFormatters.durationLabel(section.totalDuration))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.onGlass.opacity(0.7))
                }
                Button(action: { viewModel.play(section: section) }) {
                    Label("再生", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.clips) { clip in
                        LibraryClipCard(
                            clip: clip,
                            viewModel: viewModel,
                            onTap: { viewModel.play(asset: clip) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}

private struct LibraryClipCard: View {
    let clip: ClipSummary
    @ObservedObject var viewModel: LibraryFeatureViewModel
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var hasRequestedThumbnail = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 126, height: 164)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 126, height: 164)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else {
                            ProgressView()
                                .tint(AppTheme.accent)
                        }
                    }

                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(timeLabel)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(DaylogFormatters.durationLabel(clip.duration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            guard thumbnail == nil, !hasRequestedThumbnail else { return }
            hasRequestedThumbnail = true
            requestID = viewModel.requestThumbnail(
                for: clip.assetLocalIdentifier,
                targetSize: CGSize(width: 252, height: 328)
            ) { image in
                thumbnail = image
            }
        }
        .onDisappear {
            viewModel.cancelThumbnailRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: clip.capturedAt)
    }
}
