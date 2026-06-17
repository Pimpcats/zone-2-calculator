import Foundation
import CoreLocation

/// Measures workout distance and pace from the iPhone's GPS.
/// (A heart-rate chest strap can't provide distance/pace — that comes from here.)
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var distanceMeters: Double = 0
    @Published var speedMPS: Double = 0
    @Published var authorized = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var tracking = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
    }

    func start() {
        tracking = true
        lastLocation = nil
        manager.startUpdatingLocation()
    }

    func pause() {
        tracking = false
        manager.stopUpdatingLocation()
    }

    func reset() {
        distanceMeters = 0
        speedMPS = 0
        lastLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        authorized = (s == .authorizedWhenInUse || s == .authorizedAlways)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 else { continue }
            if tracking, let last = lastLocation {
                let d = loc.distance(from: last)
                if d > 0.5 && d < 100 { distanceMeters += d }   // reject GPS jitter/jumps
            }
            lastLocation = loc
            speedMPS = max(0, loc.speed)
        }
    }
}
