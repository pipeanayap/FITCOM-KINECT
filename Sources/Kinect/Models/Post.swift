import Foundation

/// Una publicación del feed, leída de `posts_public` (SCRUM-43).
struct Post: Codable, Identifiable, Hashable {
    var id: UUID
    var authorId: UUID
    var kind: String
    var body: String?
    var imagePaths: [String]
    var activityId: UUID?
    var groupId: UUID?
    var isHidden: Bool
    var createdAt: Date
    var authorName: String
    var authorAvatar: String?
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool
}

/// Lo que se manda al publicar (kind = 'post' es el valor por omisión de la tabla).
struct NewPost: Encodable {
    var authorId: UUID
    var body: String?
    var imagePaths: [String]
    var activityId: UUID?
    var groupId: UUID?
}

/// Comentario con el nombre público de quien lo escribió (SCRUM-44).
struct PostComment: Codable, Identifiable, Hashable {
    struct Author: Codable, Hashable {
        var fullName: String
        var avatarUrl: String?
    }

    var id: UUID
    var postId: UUID
    var authorId: UUID
    var body: String
    var createdAt: Date
    var profiles: Author?
}

struct NewPostComment: Encodable {
    var postId: UUID
    var authorId: UUID
    var body: String
}

struct NewPostLike: Encodable {
    var postId: UUID
    var userId: UUID
}

struct NewPostReport: Encodable {
    var postId: UUID
    var reporterId: UUID
    var reason: ReportReason
    var description: String?
}
