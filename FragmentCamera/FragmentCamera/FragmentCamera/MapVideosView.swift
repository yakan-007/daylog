import SwiftUI
import MapKit
import CoreLocation
import Combine
import Photos

struct MapVideosView: View {
    @ObservedObject var viewModel: PhotoSheetViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var locator = MapLocationProvider()
    @State private var selectedDay: IdentifiableAssets? = nil
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
        ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(dayClusters) { cl in
                        Annotation("", coordinate: cl.coordinate) {
                            Button(action: {
                                selectedDay = IdentifiableAssets(assets: sortedOldest(cl.assets))
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
                .mapControls { MapUserLocationButton() }

            }
        .sheet(item: Binding(get: {
            selectedDay
        }, set: { newVal in
            selectedDay = newVal
        })) { identifiable in
            DayPlayerView(assets: identifiable.assets)
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

// DayCard removed (simplified map)
