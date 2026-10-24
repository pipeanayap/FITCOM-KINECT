import CoreLocation
import Foundation

/// Nivel requerido para participar (US-03, US-06).
enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case principiante
    case intermedio
    case avanzado
    case cualquierNivel = "cualquier_nivel"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .principiante: "Principiante"
        case .intermedio: "Intermedio"
        case .avanzado: "Avanzado"
        case .cualquierNivel: "Cualquier nivel"
        }
    }
}

/// Estado explícito que guarda la base de datos (US-03: "comienza abierta").
/// "completa" y "finalizada" no se guardan: se calculan (ver ``ActivityStatus``).
enum ActivityExplicitStatus: String, Codable {
    case abierta
    case cancelada
}

/// Estado real de una actividad una vez considerando cupo y fecha (US-05, US-08).
enum ActivityStatus: String, Codable {
    case abierta
    case completa
    case cancelada
    case finalizada

    var label: String {
        switch self {
        case .abierta: "Abierta"
        case .completa: "Completa"
        case .cancelada: "Cancelada"
        case .finalizada: "Finalizada"
        }
    }
}

/// Una actividad leída desde la vista `activities_public`, que ya trae el
/// conteo de participantes y el estado calculado (US-04 a US-09).
struct Activity: Codable, Identifiable, Hashable {
    var id: UUID
    var organizerId: UUID
    var sport: String
    var title: String
    var description: String?
    var scheduledAt: Date
    var zone: String
    var level: ActivityLevel
    var capacity: Int
    var estimatedCost: Double?
    // coordination_link NO viene aquí: activities_public no lo incluye.
    // Se pide por separado con ActivityService.coordinationLink(activityId:),
    // que en la base de datos sólo responde a organizador/participantes/admin (US-13).
    var status: ActivityExplicitStatus
    var isHidden: Bool
    var createdAt: Date
    var updatedAt: Date
    var participantCount: Int
    var spotsLeft: Int
    var computedStatus: ActivityStatus
    var latitude: Double?
    var longitude: Double?
    var placeId: UUID?
    var groupId: UUID?

    var canAcceptParticipants: Bool { computedStatus == .abierta }

    /// Coordenada del lugar elegido; `nil` en actividades anteriores a SCRUM-35.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Distancia en metros desde `origin`; `nil` si la actividad no tiene coordenadas.
    func distance(from origin: CLLocation) -> CLLocationDistance? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude).distance(from: origin)
    }
}

/// Lo que se manda al crear una actividad (US-03).
struct NewActivity: Encodable {
    var organizerId: UUID
    var sport: String
    var title: String
    var description: String?
    var scheduledAt: Date
    var zone: String
    var level: ActivityLevel
    var capacity: Int
    var estimatedCost: Double?
    var latitude: Double?
    var longitude: Double?
    var placeId: UUID?
    var groupId: UUID?
}

/// Lo que se manda al editar una actividad (US-11): mismos campos, sin organizador.
struct ActivityEdit: Encodable {
    var sport: String
    var title: String
    var description: String?
    var scheduledAt: Date
    var zone: String
    var level: ActivityLevel
    var capacity: Int
    var estimatedCost: Double?
    var latitude: Double?
    var longitude: Double?
    var placeId: UUID?
    var groupId: UUID?
    var coordinationLink: String?
}

extension ActivityEdit {
    enum CodingKeys: String, CodingKey {
        case sport, title, description, scheduledAt, zone, level, capacity, estimatedCost
        case latitude, longitude, placeId, groupId, coordinationLink
    }

    /// `placeId` se manda siempre (como null si no hay): al cambiar a un lugar
    /// de MapKit hay que poder quitar el lugar curado anterior. El resto de los
    /// opcionales se omite cuando es nil, como antes.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sport, forKey: .sport)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(scheduledAt, forKey: .scheduledAt)
        try c.encode(zone, forKey: .zone)
        try c.encode(level, forKey: .level)
        try c.encode(capacity, forKey: .capacity)
        try c.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encode(placeId, forKey: .placeId)
        try c.encodeIfPresent(groupId, forKey: .groupId)
        try c.encodeIfPresent(coordinationLink, forKey: .coordinationLink)
    }
}
