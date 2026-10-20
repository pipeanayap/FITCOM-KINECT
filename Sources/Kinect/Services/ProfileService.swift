import Foundation

/// Consultar y editar el perfil básico (US-02). Las políticas de RLS ya
/// impiden que alguien edite el perfil de otra persona; aquí sólo se expone
/// la operación sobre el propio id para que la UI no pueda pedir otra cosa.
enum ProfileService {
    static func fetch(id: UUID) async throws -> Profile {
        try await SupabaseManager.client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func update(id: UUID, with update: ProfileUpdate) async throws -> Profile {
        try await SupabaseManager.client
            .from("profiles")
            .update(update)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }
}
