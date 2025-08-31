import SwiftUI
import MapKit
import CoreLocation
import Combine
import Photos

struct MapVideosView: View {
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var locator = MapLocationProvider()
    @State private var selected: IdentifiableAsset? = nil
    @State private var selectedDay: IdentifiableAssets? = nil
    @State private var isSatellite: Bool = false
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

    var visibleClusters: [DayCluster] {
        guard let r = currentRegion else { return dayClusters }
        return dayClusters.filter { contains(r, $0.coordinate) }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(dayClusters) { cl in
                        Annotation("", coordinate: cl.coordinate) {
                            Button(action: {
                                // Zoom into this day's region
                                let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                                cameraPosition = .region(MKCoordinateRegion(center: cl.coordinate, span: span))
                            }) {
                                ZStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.red)
                                    Text("\(cl.assets.count)")
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
                .mapStyle(isSatellite ? .imagery : .standard)
                .mapControls { MapUserLocationButton() }

                // Bottom carousel of visible day clusters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(visibleClusters) { cl in
                            DayCard(cluster: cl, onPlay: {
                                selectedDay = IdentifiableAssets(assets: cl.assets)
                            })
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
                .background(LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom))
            }
            .navigationTitle("マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { isSatellite.toggle() }) {
                            Image(systemName: isSatellite ? "globe.americas.fill" : "map")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        Button(action: { if let r = currentRegion { cameraPosition = .region(r) } }) {
                            Image(systemName: "location.circle")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                }
            }
        }
        .sheet(item: $selected) { item in PlayerView(asset: item.asset) }
        .sheet(item: Binding(get: {
            selectedDay
        }, set: { newVal in
            selectedDay = newVal
        })) { identifiable in
            DayPlayerView(assets: identifiable.assets)
        }
        .onAppear {
            if let first = dayClusters.first {
                cameraPosition = .region(MKCoordinateRegion(center: first.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
            } else {
                locator.requestCurrentLocation()
            }
        }
        .onReceive(locator.$lastCoordinate.compactMap { $0 }) { coord in
            cameraPosition = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
        }
        .onChange(of: cameraPosition) { newValue in
            if case MapCameraPosition.region(let r) = newValue { currentRegion = r }
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

private struct ThumbnailOverlay: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: 1))
                    .offset(y: -32)
            }
        }
        .onAppear {
            let options = PHImageRequestOptions()
            options.resizeMode = .fast
            options.deliveryMode = .opportunistic
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 56, height: 56), contentMode: .aspectFill, options: options) { img, _ in
                self.image = img
            }
        }
    }
}

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

private struct DayCard: View {
    let cluster: DayCluster
    var onPlay: () -> Void
    @State private var thumbnail: UIImage? = nil
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Group {
                    if let image = thumbnail {
                        Image(uiImage: image).resizable().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)).frame(width: 56, height: 56)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateTitle(cluster.date)).font(.system(size: 14, weight: .bold))
                    HStack(spacing: 6) {
                        if cluster.assets.count > 1 { chip("\(cluster.assets.count)") }
                        if let dur = totalDurationLabel(cluster.assets) { chip(dur) }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onAppear {
            // Load rep thumbnail (oldest)
            if let rep = cluster.assets.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }).first {
                let opts = PHImageRequestOptions(); opts.resizeMode = .fast; opts.deliveryMode = .opportunistic
                PHImageManager.default().requestImage(for: rep, targetSize: CGSize(width: 112, height: 112), contentMode: .aspectFill, options: opts) { img, _ in
                    self.thumbnail = img
                }
            }
        }
    }
    private func dateTitle(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd (EEE)"; return f.string(from: date) }
    private func chip(_ text: String) -> some View { Text(text).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(.ultraThinMaterial).clipShape(Capsule()) }
    private func totalDurationLabel(_ assets: [PHAsset]) -> String? { let s = Int(assets.reduce(0.0){$0+$1.duration}.rounded()); if s<=0 {return nil}; let h=s/3600,m=(s%3600)/60,sec=s%60; return h>0 ? String(format:"%d:%02d:%02d",h,m,sec) : String(format:"%d:%02d",m,sec) }
}
