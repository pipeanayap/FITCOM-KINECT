import Foundation

/// Grupo / comunidad deportiva (SCRUM-41), leído de `community_groups_public`.
/// (No se llama `Group` para no chocar con la vista `Group` de SwiftUI.)
struct CommunityGroup: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var sport: String?
    var zone: String?
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
    var createdBy: UUID
}

struct NewGroupMember: Encodable {
    var groupId: UUID
    var userId: UUID
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
