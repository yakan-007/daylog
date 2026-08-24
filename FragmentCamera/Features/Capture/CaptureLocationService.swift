@preconcurrency import CoreLocation
import Foundation

/// CLLocationManager のライフサイクルと鮮度判定を CameraService から分離する。
final class CaptureLocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let lock = NSLock()
    private var currentLocation: CLLocation?
    private var lastLocationTimestamp: Date = .distantPast

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func startIfEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            clearLocation()
            stop()
            return
        }

        DispatchQueue.main.async { [manager] in
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func stop() {
        DispatchQueue.main.async { [manager] in
            manager.stopUpdatingLocation()
        }
    }

    func bestRecentLocation(
        maxAge: TimeInterval = 60,
        maximumHorizontalAccuracy: CLLocationAccuracy = 100,
        now: Date = Date()
    ) -> CLLocation? {
        lock.lock()
        defer { lock.unlock() }
        guard let currentLocation else { return nil }
        let age = now.timeIntervalSince(lastLocationTimestamp)
        guard age <= maxAge,
              currentLocation.horizontalAccuracy > 0,
              currentLocation.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return nil
        }
        return currentLocation
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        lock.lock()
        currentLocation = latest
        lastLocationTimestamp = Date()
        lock.unlock()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.location.error(
            "location.capture.fail reason=\(error.localizedDescription, privacy: .private)"
        )
    }

    private func clearLocation() {
        lock.lock()
        currentLocation = nil
        lastLocationTimestamp = .distantPast
        lock.unlock()
    }
}
