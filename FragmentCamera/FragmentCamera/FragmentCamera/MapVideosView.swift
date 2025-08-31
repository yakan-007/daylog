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

    var points: [VideoPoint] {
        viewModel.groupedVideos.flatMap { $0.assets }
            .compactMap { asset in
                guard let loc = asset.location else { return nil }
                return VideoPoint(asset: asset, coordinate: loc.coordinate)
            }
    }

    var body: some View {
        NavigationView {
            Map(position: $cameraPosition) {
                ForEach(points) { point in
                    Annotation("", coordinate: point.coordinate) {
                        Button(action: { selected = IdentifiableAsset(asset: point.asset) }) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundColor(.red)
                                .overlay(ThumbnailOverlay(asset: point.asset))
                        }
                    }
                }
            }
            .mapControls { MapUserLocationButton() }
            .navigationTitle("マップ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selected) { item in
            PlayerView(asset: item.asset)
        }
        .onAppear {
            if let first = points.first {
                cameraPosition = .region(MKCoordinateRegion(center: first.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
            } else {
                locator.requestCurrentLocation()
            }
        }
        .onReceive(locator.$lastCoordinate.compactMap { $0 }) { coord in
            cameraPosition = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
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

struct VideoPoint: Identifiable {
    let id = UUID()
    let asset: PHAsset
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
