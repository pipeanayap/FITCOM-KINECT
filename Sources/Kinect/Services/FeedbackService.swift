import Foundation

/// Encuesta posterior a la actividad (US-16).
enum FeedbackService {
    static func submit(_ feedback: NewActivityFeedback) async throws {
        try await SupabaseManager.client
            .from("activity_feedback")
            .insert(feedback)
            .execute()
    }

    /// Resultados de las encuestas, para el panel de administración (US-17).
    static func all() async throws -> [ActivityFeedback] {
        try await SupabaseManager.client
            .from("activity_feedback")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}
