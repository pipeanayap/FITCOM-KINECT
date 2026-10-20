import Foundation

/// Reportar una actividad inapropiada (US-14). El límite de un reporte por
/// persona y actividad es un `unique` en la base de datos.
enum ReportService {
    static func report(
        activityId: UUID, reporterId: UUID, reason: ReportReason, description: String?
    ) async throws {
        try await SupabaseManager.client
            .from("activity_reports")
            .insert(
                NewActivityReport(
                    activityId: activityId, reporterId: reporterId, reason: reason,
                    description: description
                )
            )
            .execute()
    }
}
