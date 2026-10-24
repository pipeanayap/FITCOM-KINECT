import Foundation

/// Perfil básico de un usuario (US-02). Se crea solo al registrarse.
struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var fullName: String
    var username: String?
    var bio: String?
    var zone: String?
    var sportsInterests: [String]
    var avatarUrl: String?
    var isAdmin: Bool
    var createdAt: Date
    var updatedAt: Date
}

/// Campos editables del perfil propio (US-02, SCRUM-51: nombre, @usuario, bio,
/// zona, intereses, foto).
struct ProfileUpdate: Encodable {
    var fullName: String
    var username: String?
    var bio: String?
    var zone: String?
    var sportsInterests: [String]
    var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case fullName, username, bio, zone, sportsInterests, avatarUrl
    }

    /// bio, zona y foto se mandan siempre (como null si están vacías) para poder
    /// borrarlas; el usuario sólo se manda si hay uno (no se puede dejar vacío).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fullName, forKey: .fullName)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encode(bio, forKey: .bio)
        try c.encode(zone, forKey: .zone)
        try c.encode(sportsInterests, forKey: .sportsInterests)
        try c.encode(avatarUrl, forKey: .avatarUrl)
    }
}
