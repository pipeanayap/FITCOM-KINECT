import Foundation

private struct InsertedPostRow: Decodable { var id: UUID }

/// Feed, publicar, likes, comentarios y reportes (SCRUM-43 a SCRUM-46).
/// Los permisos reales (autor, admin, grupos propios) viven en la base de datos.
enum PostService {
    static let pageSize = 20

    /// Una página del feed, de lo más nuevo a lo más viejo; `before` es el
    /// `createdAt` del último post ya cargado.
    /// Con `authorIds` sólo trae a esas personas (feed "Siguiendo", SCRUM-48).
    static func feed(before: Date? = nil, limit: Int = pageSize, authorIds: [UUID]? = nil) async throws -> [Post] {
        if let authorIds, authorIds.isEmpty { return [] }
        var query = SupabaseManager.client
            .from("posts_public")
            .select()
            .eq("is_hidden", value: false)
        if let authorIds { query = query.in("author_id", values: authorIds) }
        if let before { query = query.lt("created_at", value: before) }
        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Publicaciones de una persona para su perfil (sin las tarjetas automáticas de actividad).
    static func byAuthor(_ authorId: UUID, limit: Int = 60) async throws -> [Post] {
        try await SupabaseManager.client
            .from("posts_public")
            .select()
            .eq("author_id", value: authorId)
            .eq("kind", value: "post")
            .eq("is_hidden", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func detail(id: UUID) async throws -> Post {
        try await SupabaseManager.client
            .from("posts_public")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func create(_ draft: NewPost) async throws -> Post {
        let inserted: InsertedPostRow = try await SupabaseManager.client
            .from("posts")
            .insert(draft)
            .select("id")
            .single()
            .execute()
            .value
        return try await detail(id: inserted.id)
    }

    /// Borra el post (sólo autor o admin, por RLS) y, de mejor esfuerzo, sus fotos.
    static func delete(_ post: Post) async throws {
        try await SupabaseManager.client
            .from("posts")
            .delete()
            .eq("id", value: post.id)
            .execute()
        await ImageUploadService.delete(paths: post.imagePaths)
    }

    /// (Moderación) Sólo un admin puede ocultar un post ajeno; la RLS lo exige.
    static func setHidden(postId: UUID, hidden: Bool) async throws {
        try await SupabaseManager.client
            .from("posts")
            .update(["is_hidden": hidden])
            .eq("id", value: postId)
            .execute()
    }

    static func like(postId: UUID, userId: UUID) async throws {
        try await SupabaseManager.client
            .from("post_likes")
            .insert(NewPostLike(postId: postId, userId: userId))
            .execute()
    }

    static func unlike(postId: UUID, userId: UUID) async throws {
        try await SupabaseManager.client
            .from("post_likes")
            .delete()
            .eq("post_id", value: postId)
            .eq("user_id", value: userId)
            .execute()
    }

    static func comments(postId: UUID) async throws -> [PostComment] {
        try await SupabaseManager.client
            .from("post_comments")
            .select("id, post_id, author_id, body, created_at, profiles(full_name, avatar_url)")
            .eq("post_id", value: postId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func addComment(postId: UUID, authorId: UUID, body: String) async throws {
        try await SupabaseManager.client
            .from("post_comments")
            .insert(NewPostComment(postId: postId, authorId: authorId, body: body))
            .execute()
    }

    static func deleteComment(id: UUID) async throws {
        try await SupabaseManager.client
            .from("post_comments")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func report(postId: UUID, reporterId: UUID, reason: ReportReason, description: String?) async throws {
        try await SupabaseManager.client
            .from("post_reports")
            .insert(NewPostReport(postId: postId, reporterId: reporterId, reason: reason, description: description))
            .execute()
    }
}
