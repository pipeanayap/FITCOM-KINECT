import Foundation

private struct FolloweeRow: Decodable { var followeeId: UUID }

/// Seguir / dejar de seguir y perfil público (SCRUM-47, SCRUM-48).
enum FollowService {
    static func stats(userId: UUID) async throws -> ProfileStats {
        try await SupabaseManager.client
            .from("profile_stats")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }

    static func follow(followerId: UUID, followeeId: UUID) async throws {
        try await SupabaseManager.client
            .from("follows")
            .insert(NewFollow(followerId: followerId, followeeId: followeeId))
            .execute()
    }

    static func unfollow(followerId: UUID, followeeId: UUID) async throws {
        try await SupabaseManager.client
            .from("follows")
            .delete()
            .eq("follower_id", value: followerId)
            .eq("followee_id", value: followeeId)
            .execute()
    }

    static func followingIds(userId: UUID) async throws -> [UUID] {
        let rows: [FolloweeRow] = try await SupabaseManager.client
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: userId)
            .execute()
            .value
        return rows.map(\.followeeId)
    }
}

/// Historias de 24 horas (SCRUM-49). El filtro de vigencia lo aplica la RLS.
enum StoryService {
    static func active() async throws -> [Story] {
        try await SupabaseManager.client
            .from("stories_public")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func byAuthor(_ userId: UUID) async throws -> [Story] {
        try await SupabaseManager.client
            .from("stories_public")
            .select()
            .eq("author_id", value: userId)
            .gt("expires_at", value: Date())
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func create(_ draft: NewStory) async throws {
        try await SupabaseManager.client
            .from("stories")
            .insert(draft)
            .execute()
    }

    /// Ver dos veces la misma historia falla por la llave primaria; se ignora.
    static func markViewed(storyId: UUID, viewerId: UUID) async {
        _ = try? await SupabaseManager.client
            .from("story_views")
            .insert(NewStoryView(storyId: storyId, viewerId: viewerId))
            .execute()
    }

    static func delete(_ story: Story) async throws {
        try await SupabaseManager.client
            .from("stories")
            .delete()
            .eq("id", value: story.id)
            .execute()
        if story.isVideo {
            await StoryMediaService.deleteVideo(path: story.imagePath)
        } else {
            await ImageUploadService.delete(paths: [story.imagePath])
        }
    }

    /// Agrupa por persona: primero quienes tienen historias sin ver, y dentro
    /// de cada bloque la más reciente primero.
    static func groups(from stories: [Story]) -> [StoryGroup] {
        let byAuthor = Dictionary(grouping: stories, by: \.authorId)
        let groups = byAuthor.compactMap { authorId, items -> StoryGroup? in
            guard let first = items.first else { return nil }
            return StoryGroup(
                authorId: authorId, authorName: first.authorName,
                authorAvatar: first.authorAvatar, stories: items.sorted { $0.createdAt < $1.createdAt }
            )
        }
        return groups.sorted { lhs, rhs in
            if lhs.allViewed != rhs.allViewed { return !lhs.allViewed }
            return (lhs.stories.last?.createdAt ?? .distantPast) > (rhs.stories.last?.createdAt ?? .distantPast)
        }
    }
}

/// Notificaciones (SCRUM-50). Las crean triggers en la base de datos.
enum NotificationService {
    static func list(limit: Int = 50) async throws -> [AppNotification] {
        try await SupabaseManager.client
            .from("notifications_public")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func unreadCount() async -> Int {
        let items = (try? await list(limit: 50)) ?? []
        return items.filter { $0.readAt == nil }.count
    }

    static func markAllRead(userId: UUID) async {
        _ = try? await SupabaseManager.client
            .from("notifications")
            .update(["read_at": Date()])
            .eq("user_id", value: userId)
            .is("read_at", value: nil)
            .execute()
    }
}
