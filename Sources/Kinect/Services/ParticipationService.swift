import Foundation

/// Unirse, salir y consultar participantes de una actividad
/// (US-07, US-08, US-09, US-10). El cupo, los duplicados y que el
/// organizador no se pueda salir se revisan en la base de datos
/// (trigger `check_participation_change`), no sólo aquí.
enum ParticipationService {
    static func join(activityId: UUID, userId: UUID) async throws {
        try await SupabaseManager.client
            .from("participations")
            .insert(NewParticipation(activityId: activityId, userId: userId))
            .execute()
    }

    /// (US-10) Pide confirmación antes de llamar esto; la propia vista lo hace.
    static func leave(participationId: UUID) async throws {
        try await SupabaseManager.client
            .from("participations")
            .update(["status": ParticipationStatus.cancelada.rawValue])
            .eq("id", value: participationId)
            .execute()
    }

    /// Mi inscripción activa en esta actividad, si existe (para saber si ya
    /// me uní al mostrar el detalle, US-05/US-07).
    static func myParticipation(activityId: UUID, userId: UUID) async throws -> Participation? {
        try await SupabaseManager.client
            .from("participations")
            .select()
            .eq("activity_id", value: activityId)
            .eq("user_id", value: userId)
            .eq("status", value: ParticipationStatus.activa.rawValue)
            .maybeSingle()
            .execute()
            .value
    }

    /// Participantes activos con su nombre público (US-08).
    static func participants(activityId: UUID) async throws -> [Participant] {
        try await SupabaseManager.client
            .from("participations")
            .select("id, user_id, status, joined_at, profiles(full_name, avatar_url)")
            .eq("activity_id", value: activityId)
            .eq("status", value: ParticipationStatus.activa.rawValue)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    /// Actividades a las que el usuario se ha unido (US-09). Se resuelve en
    /// dos pasos (participaciones, luego cada actividad) para no depender de
    /// un embed de PostgREST a través de la vista pública que no pude probar.
    static func joined(userId: UUID) async throws -> [MyParticipation] {
        let participations: [Participation] = try await SupabaseManager.client
            .from("participations")
            .select()
            .eq("user_id", value: userId)
            .order("joined_at", ascending: false)
            .execute()
            .value

        var result: [MyParticipation] = []
        for participation in participations {
            if let activity = try? await ActivityService.detail(id: participation.activityId) {
                result.append(MyParticipation(participation: participation, activity: activity))
            }
        }
        return result
    }
}
