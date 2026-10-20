import Foundation

/// Perfil básico de un usuario (US-02). Se crea solo al registrarse.
struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var fullName: String
    var zone: String?
    var sportsInterests: [String]
    var avatarUrl: String?
    var isAdmin: Bool
    var createdAt: Date
    var updatedAt: Date
}

/// Campos editables del perfil propio (US-02: nombre, zona, intereses, foto).
struct ProfileUpdate: Encodable {
    var fullName: String
    var zone: String?
    var sportsInterests: [String]
    var avatarUrl: String?
}
