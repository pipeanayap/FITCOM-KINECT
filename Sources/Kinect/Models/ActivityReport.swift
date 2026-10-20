import Foundation

/// Motivo de un reporte (US-14). Coincide con el CHECK de la migración.
enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case contenidoInapropiado = "contenido_inapropiado"
    case spam
    case actividadFalsa = "actividad_falsa"
    case otro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .contenidoInapropiado: "Contenido inapropiado"
        case .spam: "Spam"
        case .actividadFalsa: "Actividad falsa"
        case .otro: "Otro"
        }
    }
}

enum ReportStatus: String, Codable {
    case pendiente
    case revisado
}

struct ActivityReport: Codable, Identifiable, Hashable {
    var id: UUID
    var activityId: UUID
    var reporterId: UUID
    var reason: ReportReason
    var description: String?
    var status: ReportStatus
    var createdAt: Date
}

struct NewActivityReport: Encodable {
    var activityId: UUID
    var reporterId: UUID
    var reason: ReportReason
    var description: String?
}

/// Un reporte pendiente junto con la actividad que señala (US-15).
/// Se arma en ``ModerationService`` combinando dos consultas, no un embed de
/// PostgREST, para no depender de una relación que no pude probar en vivo.
struct ReportWithActivity: Identifiable, Hashable {
    var report: ActivityReport
    var activity: Activity
    var id: UUID { report.id }
}
