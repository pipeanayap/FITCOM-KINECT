import Foundation

/// Métricas de uso para evaluar el POC (US-17). Sólo cuenta filas; no expone
/// nombres ni datos personales de nadie.
struct UsageMetrics {
    var activitiesCreated: Int
    var activitiesWithParticipants: Int
    var totalJoins: Int
    var activitiesAtCapacity: Int
    var activitiesCancelled: Int
    var participationsLeft: Int
}

enum MetricsService {
    private struct CapacitySnapshot: Decodable {
        var capacity: Int
        var participantCount: Int
    }

    static func summary() async throws -> UsageMetrics {
        async let created = count(table: "activities")
        async let cancelled = count(
            table: "activities", column: "status", value: ActivityExplicitStatus.cancelada.rawValue
        )
        async let joins = count(table: "participations")
        async let left = count(
            table: "participations", column: "status", value: ParticipationStatus.cancelada.rawValue
        )

        let snapshots: [CapacitySnapshot] = try await SupabaseManager.client
            .from("activities_public")
            .select("capacity, participant_count")
            .execute()
            .value

        return try await UsageMetrics(
            activitiesCreated: created,
            activitiesWithParticipants: snapshots.filter { $0.participantCount > 0 }.count,
            totalJoins: joins,
            activitiesAtCapacity: snapshots.filter { $0.participantCount >= $0.capacity }.count,
            activitiesCancelled: cancelled,
            participationsLeft: left
        )
    }

    private static func count(table: String, column: String? = nil, value: String? = nil) async throws -> Int {
        var query = SupabaseManager.client.from(table).select("id", head: true, count: .exact)
        if let column, let value {
            query = query.eq(column, value: value)
        }
        let response = try await query.execute()
        return response.count ?? 0
    }
}
