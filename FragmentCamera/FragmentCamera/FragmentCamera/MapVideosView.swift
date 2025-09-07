import SwiftUI
import MapKit
import CoreLocation
import Combine
import Photos

struct MapVideosView: View {
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var locator = MapLocationProvider()
    @State private var selectedPlace: PlaceCluster? = nil
    @State private var playDay: IdentifiableAssets? = nil
    @State private var shareDay: IdentifiableAssets? = nil
    @State private var currentRegion: MKCoordinateRegion? = nil

    // Group assets by day into clusters with average coordinate
    var dayClusters: [DayCluster] {
        viewModel.groupedVideos.compactMap { group -> DayCluster? in
            let assetsWithLoc = group.assets.compactMap { a -> (PHAsset, CLLocationCoordinate2D)? in
                guard let c = a.location?.coordinate else { return nil }
                return (a, c)
            }
            guard !assetsWithLoc.isEmpty else { return nil }
            let coords = assetsWithLoc.map { $0.1 }
            let center = avgCoordinate(coords)
            let assets = assetsWithLoc.map { $0.0 }
            return DayCluster(date: group.date, assets: assets, coordinate: center)
        }
        .sorted { $0.date > $1.date }
    }

    // Group nearby day clusters into place clusters (~100m grid)
    var placeClusters: [PlaceCluster] {
        let buckets = Dictionary(grouping: dayClusters) { (dc: DayCluster) -> String in
            let lat = dc.coordinate.latitude
            let lon = dc.coordinate.longitude
            // ~100m grid bucketing
            let x = Int((lat * 1000.0).rounded())
            let y = Int((lon * 1000.0).rounded())
            return "\(x)_\(y)"
        }
        return buckets.values.map { days in
            let coords = days.map { $0.coordinate }
            let center = avgCoordinate(coords)
            return PlaceCluster(days: days.sorted { $0.date > $1.date }, coordinate: center)
        }.sorted { ($0.days.first?.date ?? .distantPast) > ($1.days.first?.date ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(placeClusters) { plc in
                        Annotation("", coordinate: plc.coordinate) {
                            Button(action: {
                                selectedPlace = plc
                            }) {
                                ZStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.red)
                                    Text("\(plc.days.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.red.opacity(0.9))
                                        .clipShape(Capsule())
                                        .offset(y: -28)
                                }
                            }
                        }
                    }
                }
                .mapControls { MapUserLocationButton() }

                if let plc = selectedPlace {
                    PlaceMiniCard(
                        place: plc,
                        onClose: { selectedPlace = nil },
                        onPlayRecent: {
                            let recent = plc.days.prefix(5).flatMap { $0.assets }
                            playDay = IdentifiableAssets(assets: sortedOldest(recent))
                            selectedPlace = nil
                        },
                        onShareRecent: {
                            let recent = plc.days.prefix(5).flatMap { $0.assets }
                            shareDay = IdentifiableAssets(assets: sortedOldest(recent))
                            selectedPlace = nil
                        },
                        onPlayDay: { dc in
                            playDay = IdentifiableAssets(assets: sortedOldest(dc.assets))
                            selectedPlace = nil
                        },
                        onShareDay: { dc in
                            shareDay = IdentifiableAssets(assets: sortedOldest(dc.assets))
                            selectedPlace = nil
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            }
        .sheet(item: $playDay) { identifiable in
            DayPlayerView(assets: identifiable.assets)
        }
        .sheet(item: $shareDay) { identifiable in
            ShareDayView(assets: identifiable.assets)
        }
        .onAppear {
            if let first = dayClusters.first {
                let region = MKCoordinateRegion(center: first.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
                cameraPosition = .region(region)
                currentRegion = region
            } else {
                locator.requestCurrentLocation()
            }
        }
        .onReceive(locator.$lastCoordinate.compactMap { $0 }) { coord in
            let region = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
            cameraPosition = .region(region)
            currentRegion = region
        }
    }
}

final class MapLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastCoordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coord = locations.last?.coordinate {
            DispatchQueue.main.async { self.lastCoordinate = coord }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No-op; keep last known
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }
}

struct DayCluster: Identifiable {
    let id = UUID()
    let date: Date
    let assets: [PHAsset]
    let coordinate: CLLocationCoordinate2D
}

// ThumbnailOverlay removed (simplified map)

// MARK: - Helpers
private func avgCoordinate(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
    guard !coords.isEmpty else { return .init(latitude: 0, longitude: 0) }
    let lat = coords.map { $0.latitude }.reduce(0, +) / Double(coords.count)
    let lon = coords.map { $0.longitude }.reduce(0, +) / Double(coords.count)
    return .init(latitude: lat, longitude: lon)
}

private func contains(_ region: MKCoordinateRegion, _ coordinate: CLLocationCoordinate2D) -> Bool {
    let minLat = region.center.latitude - region.span.latitudeDelta / 2
    let maxLat = region.center.latitude + region.span.latitudeDelta / 2
    let minLon = region.center.longitude - region.span.longitudeDelta / 2
    let maxLon = region.center.longitude + region.span.longitudeDelta / 2
    return (minLat...maxLat).contains(coordinate.latitude) && (minLon...maxLon).contains(coordinate.longitude)
}

// Bottom mini card for selected day
private struct MapMiniDayCard: View {
    let cluster: DayCluster
    var onClose: () -> Void
    var onPlay: () -> Void
    var onShare: () -> Void
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(width: 56, height: 56)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(dateTitle(cluster.date))
                    .font(.system(size: 14, weight: .bold))
                Text(summaryText())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Button(action: onPlay) { Image(systemName: "play.fill") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(action: onShare) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        if let rep = cluster.assets.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }).first {
            let opts = PHImageRequestOptions(); opts.resizeMode = .fast; opts.deliveryMode = .opportunistic; opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: rep, targetSize: CGSize(width: 112, height: 112), contentMode: .aspectFill, options: opts) { img, _ in
                self.thumbnail = img
            }
        }
    }

    private func dateTitle(_ date: Date) -> String { let f = DateFormatter(); f.locale = .current; f.dateFormat = "M/d (EEE)"; return f.string(from: date) }
    private func summaryText() -> String {
        let count = cluster.assets.count
        let sec = Int(cluster.assets.reduce(0.0){$0+$1.duration}.rounded())
        let h = sec/3600, m=(sec%3600)/60
        let dur = h>0 ? String(format:"%d:%02d",h,m) : String(format:"%d分",m)
        return "\(count)本 / \(dur)"
    }
}

struct PlaceCluster: Identifiable {
    let id = UUID()
    let days: [DayCluster]
    let coordinate: CLLocationCoordinate2D
}

private struct PlaceMiniCard: View {
    let place: PlaceCluster
    var onClose: () -> Void
    var onPlayRecent: () -> Void
    var onShareRecent: () -> Void
    var onPlayDay: (DayCluster) -> Void
    var onShareDay: (DayCluster) -> Void
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if let img = thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .frame(width: 56, height: 56)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(placeTitle())
                        .font(.system(size: 14, weight: .bold))
                    Text("\(place.days.count)日")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Button(action: onPlayRecent) { Image(systemName: "play.fill") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(action: onShareRecent) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            // Recent days chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(place.days.prefix(7)) { dc in
                        HStack(spacing: 6) {
                            Text(dayTitle(dc.date))
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(dc.assets.count)本")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .onTapGesture { onPlayDay(dc) }
                        .contextMenu {
                            Button { onPlayDay(dc) } label: { Label("再生", systemImage: "play.fill") }
                            Button { onShareDay(dc) } label: { Label("書き出し", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        if let rep = place.days.first?.assets.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }).first {
            let opts = PHImageRequestOptions(); opts.resizeMode = .fast; opts.deliveryMode = .opportunistic; opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: rep, targetSize: CGSize(width: 112, height: 112), contentMode: .aspectFill, options: opts) { img, _ in
                self.thumbnail = img
            }
        }
    }

    private func placeTitle() -> String { "この場所" } // TODO: reverse geocode (later)
    private func dayTitle(_ date: Date) -> String { let f = DateFormatter(); f.locale = .current; f.dateFormat = "M/d"; return f.string(from: date) }
}

private func sortedOldest(_ assets: [PHAsset]) -> [PHAsset] {
    assets.sorted { (a, b) in (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast) }
}
