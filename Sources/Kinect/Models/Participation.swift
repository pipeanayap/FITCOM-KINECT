import Foundation

enum ParticipationStatus: String, Codable {
    case activa
    case cancelada
}

struct Participation: Codable, Identifiable, Hashable {
    var id: UUID
    var activityId: UUID
    var userId: UUID
    var status: ParticipationStatus
    var joinedAt: Date
    var leftAt: Date?
}

/// Lo que se manda al unirse a una actividad (US-07).
struct NewParticipation: Encodable {
    var activityId: UUID
    var userId: UUID
}

/// Participante de una actividad con su nombre público (US-08).
struct Participant: Codable, Identifiable, Hashable {
    var id: UUID
    var userId: UUID
    var status: ParticipationStatus
    var joinedAt: Date
    var profile: ParticipantProfile

    struct ParticipantProfile: Codable, Hashable {
        var fullName: String
        var avatarUrl: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, status, joinedAt
        case profile = "profiles"
    }
}

/// Una actividad a la que el usuario se unió, junto con su inscripción (US-09).
/// `ActivityService` arma esto por separado (participación + actividad),
/// sin depender de que PostgREST pueda embeber a través de la vista pública.
struct MyParticipation: Identifiable, Hashable {
    var participation: Participation
    var activity: Activity
    var id: UUID { participation.id }
}
