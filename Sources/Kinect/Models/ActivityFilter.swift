import Foundation

/// Filtros combinables del listado de actividades (US-06).
struct ActivityFilter: Equatable {
    var sport: String?
    var zone: String?
    var level: ActivityLevel?
    var fromDate: Date?
    var toDate: Date?

    var isEmpty: Bool {
        sport == nil && zone == nil && level == nil && fromDate == nil && toDate == nil
    }

    static let empty = ActivityFilter()
}
