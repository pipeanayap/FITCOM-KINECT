import Foundation

/// Grupo / comunidad deportiva (SCRUM-41), leído de `community_groups_public`.
/// (No se llama `Group` para no chocar con la vista `Group` de SwiftUI.)
struct CommunityGroup: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var sport: String?
    var zone: String?
    var photoUrl: String? = nil
    var createdBy: UUID
    var isHidden: Bool
    var createdAt: Date
    var memberCount: Int
}

/// Lo que se manda al crear un grupo.
struct NewCommunityGroup: Encodable {
    var name: String
    var description: String?
    var sport: String?
    var zone: String?
    var photoUrl: String? = nil
    var createdBy: UUID
}

/// Sólo contiene pendientes; al responder se elimina y, si se acepta, se crea la membresía.
struct GroupJoinRequest: Codable, Identifiable {
    var id: UUID
    var groupId: UUID
    var userId: UUID
    var kind: String
    var profiles: GroupMember.ProfileInfo?
    var isInvitation: Bool { kind == "invitation" }
}

struct GroupInviteCandidate: Decodable, Identifiable {
    var id: UUID
    var fullName: String
    var username: String?
}

/// Miembro con su nombre público (mismo embed que `Participant`).
struct GroupMember: Codable, Identifiable, Hashable {
    struct ProfileInfo: Codable, Hashable {
        var fullName: String
        var avatarUrl: String?
    }

    var userId: UUID
    var role: String
    var joinedAt: Date
    var profiles: ProfileInfo?

    var id: UUID { userId }
    var isAdmin: Bool { role == "admin" }
}
