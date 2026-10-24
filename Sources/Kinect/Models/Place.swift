import CoreLocation
import Foundation

/// Lugar deportivo curado por el equipo (SCRUM-40).
struct Place: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var category: String
    var sports: [String]
    var address: String?
    var description: String?
    var latitude: Double
    var longitude: Double
    var isHidden: Bool
    var createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from origin: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: origin)
    }

    var categoryLabel: String {
        switch category {
        case "cancha": "Cancha"
        case "gimnasio": "Gimnasio"
        case "parque": "Parque"
        case "club": "Club"
        case "estudio": "Estudio"
        default: "Lugar"
        }
    }

    var categorySymbol: String {
        switch category {
        case "cancha": "sportscourt.fill"
        case "gimnasio": "dumbbell.fill"
        case "parque": "tree.fill"
        case "club": "building.2.fill"
        case "estudio": "figure.yoga"
        default: "mappin.circle.fill"
        }
    }
}
