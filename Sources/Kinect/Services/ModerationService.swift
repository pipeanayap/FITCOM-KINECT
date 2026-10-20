import Foundation

/// Revisar reportes y ocultar/restablecer actividades (US-15). Sólo
/// administradores pueden llamar esto: lo exige la RLS, y además la
/// pantalla que lo usa sólo aparece si `AuthStore.isAdmin`.
enum ModerationService {
    static func pendingReports() async throws -> [ReportWithActivity] {
        let reports: [ActivityReport] = try await SupabaseManager.client
            .from("activity_reports")
            .select()
            .eq("status", value: ReportStatus.pendiente.rawValue)
            .order("created_at", ascending: true)
            .execute()
            .value

        var result: [ReportWithActivity] = []
        for report in reports {
            if let activity = try? await ActivityService.detail(id: report.activityId) {
                result.append(ReportWithActivity(report: report, activity: activity))
            }
        }
        return result
    }

    static func markReviewed(reportId: UUID) async throws {
        try await SupabaseManager.client
            .from("activity_reports")
            .update(["status": ReportStatus.revisado.rawValue])
            .eq("id", value: reportId)
            .execute()
    }

    static func hide(activityId: UUID, adminId: UUID) async throws {
        try await setHidden(true, activityId: activityId, adminId: adminId, action: .ocultar)
    }

    static func restore(activityId: UUID, adminId: UUID) async throws {
        try await setHidden(false, activityId: activityId, adminId: adminId, action: .restablecer)
    }

    /// Cada ocultar/restablecer queda en la bitácora (US-15: "las acciones de
    /// moderación quedan registradas").
    private static func setHidden(
        _ hidden: Bool, activityId: UUID, adminId: UUID, action: ModerationActionType
    ) async throws {
        try await SupabaseManager.client
            .from("activities")
            .update(["is_hidden": hidden])
            .eq("id", value: activityId)
            .execute()
        try await SupabaseManager.client
            .from("moderation_actions")
            .insert(NewModerationAction(activityId: activityId, adminId: adminId, action: action))
            .execute()
    }
}
