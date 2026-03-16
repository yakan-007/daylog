import AVKit
import Photos
import SwiftUI

@MainActor
final class PlaybackFeatureViewModel: ObservableObject, Identifiable {
    enum Mode {
        case single(PHAsset)
        case day([PHAsset])
    }

    @Published private(set) var mode: Mode
    let id = UUID()

    init(mode: Mode) {
        self.mode = mode
    }

    func loadSingle(asset: PHAsset) {
        mode = .single(asset)
    }

    func loadDay(assets: [PHAsset]) {
        mode = .day(assets)
    }
}

struct PlaybackFeatureView: View {
    @ObservedObject var viewModel: PlaybackFeatureViewModel

    var body: some View {
        switch viewModel.mode {
        case .single(let asset):
            PlaybackSingleView(asset: asset)
        case .day(let assets):
            PlaybackDayView(assets: assets)
        }
    }
}

struct PlaybackSingleView: View {
    let asset: PHAsset

    var body: some View {
        PlayerView(asset: asset)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
    }
}

struct PlaybackDayView: View {
    let assets: [PHAsset]

    var body: some View {
        DayPlayerView(assets: assets)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
    }
}

@MainActor
struct PlaybackFeatureFactory {
    func makeSingle(asset: PHAsset) -> PlaybackFeatureViewModel {
        PlaybackFeatureViewModel(mode: .single(asset))
    }

    func makeDay(assets: [PHAsset]) -> PlaybackFeatureViewModel {
        PlaybackFeatureViewModel(mode: .day(assets))
    }
}
