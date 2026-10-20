import Foundation

/// Encuesta opcional después de una actividad (US-16).
struct ActivityFeedback: Codable, Identifiable, Hashable {
    var id: UUID
    var activityId: UUID
    var userId: UUID
    var activityHappened: Bool
    var metPeople: Bool?
    var easeRating: Int?
    var comment: String?
    var createdAt: Date
}

struct NewActivityFeedback: Encodable {
    var activityId: UUID
    var userId: UUID
    var activityHappened: Bool
    var metPeople: Bool?
    var easeRating: Int?
    var comment: String?
}
