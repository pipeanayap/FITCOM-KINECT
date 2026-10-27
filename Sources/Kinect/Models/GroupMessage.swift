import Foundation

/// Mensaje del chat de un grupo, leído de `group_messages`.
struct GroupMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var groupId: UUID
    var authorId: UUID
    var body: String
    var createdAt: Date
    var profiles: GroupMember.ProfileInfo?

    var authorName: String { profiles?.fullName ?? "Integrante" }
}

/// Lo que se manda al escribir un mensaje.
struct NewGroupMessage: Encodable {
    var groupId: UUID
    var authorId: UUID
    var body: String
}
