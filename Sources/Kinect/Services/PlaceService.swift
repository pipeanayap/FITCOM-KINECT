import Foundation

/// Lugares deportivos curados (SCRUM-40). Sólo lectura desde la app: los
/// carga el equipo (ver supabase/places_leon.sql).
enum PlaceService {
    static func list() async throws -> [Place] {
        try await SupabaseManager.client
            .from("places")
            .select()
            .eq("is_hidden", value: false)
            .order("name", ascending: true)
            .execute()
            .value
    }

    static func detail(id: UUID) async throws -> Place {
        try await SupabaseManager.client
            .from("places")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    /// Próximas actividades abiertas ligadas a este lugar.
    static func upcomingActivities(placeId: UUID) async throws -> [Activity] {
        try await SupabaseManager.client
            .from("activities_public")
            .select()
            .eq("place_id", value: placeId)
            .eq("status", value: ActivityExplicitStatus.abierta.rawValue)
            .gt("scheduled_at", value: Date())
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }
}
