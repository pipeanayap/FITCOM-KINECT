import MapKit
import SwiftUI

/// Mapa pequeño con un pin (SCRUM-35). Envuelve MKMapView porque el `Map`
/// de SwiftUI usa un módulo de cross-import que el build de xtool no incluye.
struct MapPreview: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let title: String

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isUserInteractionEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = title
        map.addAnnotation(pin)
        map.setRegion(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200),
            animated: false
        )
    }
}
