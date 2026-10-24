import MapKit
import SwiftUI

/// Un pin del mapa de Explorar: un lugar curado o una actividad (SCRUM-40).
struct MapPin: Identifiable {
    enum Kind { case place, activity }

    let id: String
    let refId: UUID
    let kind: Kind
    let coordinate: CLLocationCoordinate2D
    let title: String
    let symbol: String
}

private final class PinAnnotation: NSObject, MKAnnotation {
    let pin: MapPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.title }

    init(pin: MapPin) { self.pin = pin }
}

/// Mapa con varios pines. Envuelve MKMapView (el `Map` de SwiftUI no compila
/// con el build de xtool, ver MapPreview).
struct MultiPinMapView: UIViewRepresentable {
    let pins: [MapPin]
    let onSelect: (MapPin) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        // León como vista inicial mientras no hay pines.
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 21.1236, longitude: -101.6820),
                latitudinalMeters: 20_000, longitudinalMeters: 20_000
            ),
            animated: false
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        let key = pins.map(\.id).joined(separator: ",")
        guard key != coordinator.lastKey else { return }
        coordinator.lastKey = key

        map.removeAnnotations(map.annotations.filter { $0 is PinAnnotation })
        let annotations = pins.map { PinAnnotation(pin: $0) }
        map.addAnnotations(annotations)
        // Encuadra los pines sólo la primera vez que llegan, para no mover el
        // mapa mientras el usuario lo explora.
        if !coordinator.didFit, !annotations.isEmpty {
            coordinator.didFit = true
            map.showAnnotations(annotations, animated: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (MapPin) -> Void
        var lastKey = ""
        var didFit = false

        init(onSelect: @escaping (MapPin) -> Void) { self.onSelect = onSelect }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? PinAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.annotation = annotation
            view.markerTintColor = UIColor(annotation.pin.kind == .place ? Color.brandPrimary : Color.brandAccent)
            view.glyphImage = UIImage(systemName: annotation.pin.symbol)
            view.canShowCallout = false
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? PinAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            onSelect(annotation.pin)
        }
    }
}
