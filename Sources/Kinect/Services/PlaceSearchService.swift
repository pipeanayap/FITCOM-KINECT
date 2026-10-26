import CoreLocation
import Foundation
import MapKit

/// Lugar elegido en el autocompletado (SCRUM-35).
struct PickedPlace: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    /// Sólo si es un lugar curado de FITCOM (SCRUM-40); `nil` para lugares de MapKit.
    var placeId: UUID?
}

struct PlaceSuggestion: Identifiable, Equatable {
    var id: String { title + "|" + subtitle }
    var title: String
    var subtitle: String
}

/// Autocompletado de lugares con MapKit (sin llaves de API) y resolución a
/// coordenadas reales.
@MainActor
@Observable
final class PlaceSearchService: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [PlaceSuggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                suggestions = []
            }
            completer.queryFragment = trimmed
        }
    }

    /// Sesga las sugerencias hacia donde está el usuario.
    func bias(around location: CLLocation?) {
        guard let location else { return }
        completer.region = MKCoordinateRegion(
            center: location.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000
        )
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.map { PlaceSuggestion(title: $0.title, subtitle: $0.subtitle) }
        MainActor.assumeIsolated {
            suggestions = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : mapped
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    /// Convierte la sugerencia elegida en un lugar con coordenadas.
    func resolve(_ suggestion: PlaceSuggestion) async throws -> PickedPlace {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [suggestion.title, suggestion.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        request.region = completer.region
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw URLError(.cannotFindHost) }
        let coordinate = item.placemark.coordinate
        let name = suggestion.subtitle.isEmpty ? suggestion.title : "\(suggestion.title), \(suggestion.subtitle)"
        return PickedPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// "Usar mi ubicación actual": nombre legible a partir de coordenadas.
    static func place(at location: CLLocation, fallbackName: String = "Mi ubicación actual") async -> PickedPlace {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let mark = placemarks?.first
        let parts = [mark?.name, mark?.locality].compactMap { $0 }.filter { !$0.isEmpty }
        return PickedPlace(
            name: parts.isEmpty ? fallbackName : parts.joined(separator: ", "),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
