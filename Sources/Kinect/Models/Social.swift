import Foundation

// Rutas de navegación (valores para `NavigationLink(value:)`).
struct ProfileRoute: Hashable { let userId: UUID }
struct PostRoute: Hashable { let id: UUID }
struct NotificationsRoute: Hashable {}

/// Perfil público con conteos, leído de `profile_stats` (SCRUM-47).
struct ProfileStats: Codable, Identifiable, Hashable {
    var id: UUID
    var fullName: String
    var zone: String?
    var sportsInterests: [String]
    var avatarUrl: String?
    var followersCount: Int
    var followingCount: Int
    var postsCount: Int
    var followedByMe: Bool
    var username: String?
    var bio: String?
    var plansCount: Int?
}

struct NewFollow: Encodable {
    var followerId: UUID
    var followeeId: UUID
}

/// Historia de 24 horas, leída de `stories_public` (SCRUM-49).
struct Story: Codable, Identifiable, Hashable {
    var id: UUID
    var authorId: UUID
    var imagePath: String
    var caption: String?
    var createdAt: Date
    var expiresAt: Date
    var authorName: String
    var authorAvatar: String?
    var viewedByMe: Bool
    var viewCount: Int
}

struct NewStory: Encodable {
    var authorId: UUID
    var imagePath: String
    var caption: String?
}

struct NewStoryView: Encodable {
    var storyId: UUID
    var viewerId: UUID
}

/// Las historias activas de una misma persona, en orden cronológico.
struct StoryGroup: Identifiable, Hashable {
    var authorId: UUID
    var authorName: String
    var authorAvatar: String?
    var stories: [Story]

    var id: UUID { authorId }
    var allViewed: Bool { stories.allSatisfy(\.viewedByMe) }
    /// Por dónde empezar: la primera historia que todavía no se ha visto.
    var firstUnviewedIndex: Int { stories.firstIndex { !$0.viewedByMe } ?? 0 }
}

/// Notificación dentro de la app, leída de `notifications_public` (SCRUM-50).
struct AppNotification: Codable, Identifiable, Hashable {
    var id: UUID
    var userId: UUID
    var actorId: UUID
    var kind: String
    var postId: UUID?
    var activityId: UUID?
    var readAt: Date?
    var createdAt: Date
    var actorName: String
    var actorAvatar: String?
    var activityTitle: String?

    var text: String {
        switch kind {
        case "like": "le dio me gusta a tu publicación"
        case "comment": "comentó tu publicación"
        case "follow": "empezó a seguirte"
        case "join": "se unió a \"\(activityTitle ?? "tu actividad")\""
        default: "tuvo actividad contigo"
        }
    }
}
