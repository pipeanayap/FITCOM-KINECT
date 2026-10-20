import Foundation

/// Sólo se usa para leer el id recién insertado; "activities" (la tabla) no
/// trae los conteos calculados que sí tiene la vista "activities_public".
private struct InsertedRow: Decodable { var id: UUID }

/// Publicar, explorar, filtrar, editar y cancelar actividades
/// (US-03 a US-06, US-09, US-11, US-12).
enum ActivityService {
    /// Explorar (US-04) con filtros combinables (US-06). Sólo actividades
    /// abiertas (no canceladas) que todavía no ocurren; "completa" sigue
    /// contando como abierta a nivel de dato, sólo deja de aceptar gente.
    static func list(filter: ActivityFilter = .empty) async throws -> [Activity] {
        var query = SupabaseManager.client
            .from("activities_public")
            .select()
            .eq("status", value: ActivityExplicitStatus.abierta.rawValue)
            .gt("scheduled_at", value: Date())

        if let sport = filter.sport { query = query.eq("sport", value: sport) }
        if let zone = filter.zone { query = query.eq("zone", value: zone) }
        if let level = filter.level { query = query.eq("level", value: level.rawValue) }
        if let fromDate = filter.fromDate { query = query.gte("scheduled_at", value: fromDate) }
        if let toDate = filter.toDate { query = query.lte("scheduled_at", value: toDate) }

        return try await query
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }

    /// Mías: creadas y a las que me uní (US-09). La actividad puede estar
    /// cancelada o finalizada, a diferencia de ``list(filter:)``.
    static func mine(organizerId: UUID) async throws -> [Activity] {
        try await SupabaseManager.client
            .from("activities_public")
            .select()
            .eq("organizer_id", value: organizerId)
            .order("scheduled_at", ascending: false)
            .execute()
            .value
    }

    static func detail(id: UUID) async throws -> Activity {
        try await SupabaseManager.client
            .from("activities_public")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func create(_ draft: NewActivity) async throws -> Activity {
        let inserted: InsertedRow = try await SupabaseManager.client
            .from("activities")
            .insert(draft)
            .select("id")
            .single()
            .execute()
            .value
        return try await detail(id: inserted.id)
    }

    /// (US-11) El propio formulario no deja elegir una fecha pasada ni un
    /// cupo menor a los participantes actuales; la base de datos lo exige
    /// de nuevo por si acaso (ver trigger `check_activity_update`).
    static func update(id: UUID, with edit: ActivityEdit) async throws -> Activity {
        try await SupabaseManager.client
            .from("activities")
            .update(edit)
            .eq("id", value: id)
            .execute()
        return try await detail(id: id)
    }

    /// (US-12) Se marca como cancelada; nunca se borra, para conservar el historial.
    static func cancel(id: UUID) async throws {
        try await SupabaseManager.client
            .from("activities")
            .update(["status": ActivityExplicitStatus.cancelada.rawValue])
            .eq("id", value: id)
            .execute()
    }

    private struct CoordinationLinkParams: Encodable { var pActivityId: UUID }

    /// (US-13) La función en la base de datos sólo devuelve el enlace si
    /// quien pregunta es el organizador, un participante activo o un admin;
    /// cualquier otra persona recibe `nil`, sin que la app tenga que decidirlo.
    static func coordinationLink(activityId: UUID) async throws -> String? {
        try await SupabaseManager.client
            .rpc("get_coordination_link", params: CoordinationLinkParams(pActivityId: activityId))
            .execute()
            .value
    }
}
