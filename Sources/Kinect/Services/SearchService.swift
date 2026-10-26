import Foundation

/// Persona devuelta por la búsqueda global.
struct PersonResult: Codable, Identifiable, Hashable {
    var id: UUID
    var fullName: String
    var username: String
    var avatarUrl: String?
    var zone: String?
}

/// Búsqueda global de Explorar: personas y grupos se consultan en el servidor;
/// actividades y lugares ya están cargados y se filtran en la pantalla.
enum SearchService {
    /// Deja sólo letras, números, espacios y guion bajo: lo demás (comas,
    /// paréntesis, comodines) rompería el filtro `or` de PostgREST.
    static func clean(_ text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" })
            .trimmingCharacters(in: .whitespaces)
    }

    static func people(_ query: String) async throws -> [PersonResult] {
        let term = clean(query)
        guard term.count >= 2 else { return [] }
        return try await SupabaseManager.client
            .from("profiles")
            .select("id, full_name, username, avatar_url, zone")
            .or("full_name.ilike.*\(term)*,username.ilike.*\(term)*")
            .order("username", ascending: true)
            .limit(20)
            .execute()
            .value
    }

    static func groups(_ query: String) async throws -> [CommunityGroup] {
        let term = clean(query)
        guard term.count >= 2 else { return [] }
        return try await SupabaseManager.client
            .from("community_groups_public")
            .select()
            .eq("is_hidden", value: false)
            .or("name.ilike.*\(term)*,sport.ilike.*\(term)*,zone.ilike.*\(term)*")
            .order("member_count", ascending: false)
            .limit(20)
            .execute()
            .value
    }
}
