#if DEBUG
import SwiftUI
import MapKit
import CoreLocation
import Combine
import Photos
import Foundation

struct MapVideosView: View {
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var locator = MapLocationProvider()
    @State private var selectedPlaceId: String? = nil
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
            let dayKey = dayId(date: group.date, coordinate: center)
            return DayCluster(id: dayKey, date: group.date, assets: assets, coordinate: center)
        }
        .sorted { $0.date > $1.date }
    }

    // Group nearby day clusters into place clusters (~100m grid)
    var placeClusters: [PlaceCluster] {
        let buckets = Dictionary(grouping: dayClusters) { (dc: DayCluster) -> String in
            gridKey(for: dc.coordinate)
        }
        return buckets.values.map { days in
            let coords = days.map { $0.coordinate }
            let center = avgCoordinate(coords)
            let sortedDays = days.sorted { $0.date > $1.date }
            let key = gridKey(for: center)
            return PlaceCluster(id: key, days: sortedDays, coordinate: center)
        }.sorted { ($0.days.first?.date ?? .distantPast) > ($1.days.first?.date ?? .distantPast) }
    }

    private var selectedPlace: PlaceCluster? {
        guard let selectedPlaceId else { return nil }
        return placeClusters.first(where: { $0.id == selectedPlaceId })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(placeClusters) { plc in
                        Annotation("", coordinate: plc.coordinate) {
                            Button(action: {
                                selectedPlaceId = plc.id
                            }) {
                                ZStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(selectedPlaceId == plc.id ? Color(hex: 0xFFC857) : .red)
                                    Text("\(plc.days.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background((selectedPlaceId == plc.id ? Color(hex: 0xFFC857) : .red).opacity(0.92))
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
                        onClose: { selectedPlaceId = nil },
                        onPlayRecent: {
                            let recent = plc.days.prefix(5).flatMap { $0.assets }
                            playDay = IdentifiableAssets(assets: sortedOldest(recent))
                            selectedPlaceId = nil
                        },
                        onShareRecent: {
                            let recent = plc.days.prefix(5).flatMap { $0.assets }
                            shareDay = IdentifiableAssets(assets: sortedOldest(recent))
                            selectedPlaceId = nil
                        },
                        onPlayDay: { dc in
                            playDay = IdentifiableAssets(assets: sortedOldest(dc.assets))
                            selectedPlaceId = nil
                        },
                        onShareDay: { dc in
                            shareDay = IdentifiableAssets(assets: sortedOldest(dc.assets))
                            selectedPlaceId = nil
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
    let id: String
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
    let id: String
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
    @State private var resolvedPlaceName: String? = nil

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
        .onAppear {
            loadThumbnail()
            PlaceNameResolver.shared.resolveName(for: place.coordinate) { name in
                self.resolvedPlaceName = name
            }
        }
    }

    private func loadThumbnail() {
        if let rep = place.days.first?.assets.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }).first {
            let opts = PHImageRequestOptions(); opts.resizeMode = .fast; opts.deliveryMode = .opportunistic; opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: rep, targetSize: CGSize(width: 112, height: 112), contentMode: .aspectFill, options: opts) { img, _ in
                self.thumbnail = img
            }
        }
    }

    private func placeTitle() -> String { resolvedPlaceName ?? "この周辺" }
    private func dayTitle(_ date: Date) -> String { let f = DateFormatter(); f.locale = .current; f.dateFormat = "M/d"; return f.string(from: date) }
}

private func sortedOldest(_ assets: [PHAsset]) -> [PHAsset] {
    assets.sorted { (a, b) in (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast) }
}

private func gridKey(for coordinate: CLLocationCoordinate2D) -> String {
    let x = Int((coordinate.latitude * 1000.0).rounded())
    let y = Int((coordinate.longitude * 1000.0).rounded())
    return "\(x)_\(y)"
}

private func dayId(date: Date, coordinate: CLLocationCoordinate2D) -> String {
    let day = Int(date.timeIntervalSince1970 / 86_400)
    return "\(day)_\(gridKey(for: coordinate))"
}

final class PlaceNameResolver {
    static let shared = PlaceNameResolver()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private init() {}

    func resolveName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        let key = gridKey(for: coordinate)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            completion(cached)
            return
        }
        lock.unlock()

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let placemark = placemarks?.first
            let name = placemark?.locality ?? placemark?.subLocality ?? placemark?.name ?? "この周辺"
            self.lock.lock()
            self.cache[key] = name
            self.lock.unlock()
            DispatchQueue.main.async {
                completion(name)
            }
        }
    }
}
#endif
