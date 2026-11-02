import Foundation
import CoreLocation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var place: Place?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ mgr: CLLocationManager) {
        authorizationStatus = mgr.authorizationStatus
        switch mgr.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            mgr.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ mgr: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last, loc.horizontalAccuracy >= 0 else { return }
        location = loc
        place = Place(
            id: "current",
            name: "Current Location",
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude
        )
    }
}