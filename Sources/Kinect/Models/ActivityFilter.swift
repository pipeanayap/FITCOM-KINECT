import Foundation

/// Filtros combinables del listado de actividades (US-06).
struct ActivityFilter: Equatable {
    var sport: String?
    var zone: String?
    var level: ActivityLevel?
    var fromDate: Date?
    var toDate: Date?
    /// Radio máximo en km desde mi ubicación (SCRUM-36); `nil` = sin límite.
    var maxDistanceKm: Double?

    var isEmpty: Bool {
        sport == nil && zone == nil && level == nil && fromDate == nil && toDate == nil && maxDistanceKm == nil
    }

    static let empty = ActivityFilter()
}

/// Texto corto de distancia para tarjetas (SCRUM-36).
enum DistanceFormat {
    static func text(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
}
