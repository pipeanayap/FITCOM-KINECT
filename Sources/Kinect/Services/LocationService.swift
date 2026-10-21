import CoreLocation
import Foundation

/// Ubicación del usuario con permiso "mientras se usa la app" (SCRUM-36).
/// Sólo se pide cuando el usuario activa "Cerca de mí" o usa su ubicación
/// actual al elegir un lugar.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override private init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
    private var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Pide permiso si hace falta y solicita una lectura de ubicación.
    func requestLocation() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorizationStatus = status
            if isAuthorized { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        MainActor.assumeIsolated { currentLocation = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Sin lectura se mantiene el último valor conocido (o nil).
    }
}
