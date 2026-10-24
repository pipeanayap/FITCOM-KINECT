import Foundation

private struct InsertedGroupRow: Decodable { var id: UUID }
private struct MembershipRow: Decodable { var groupId: UUID }

/// Crear, explorar y unirse a grupos (SCRUM-41). Que el creador no pueda
/// salir y que sólo se publique en grupos propios lo exige la base de datos.
enum GroupService {
    static func list() async throws -> [CommunityGroup] {
        try await SupabaseManager.client
            .from("community_groups_public")
            .select()
            .eq("is_hidden", value: false)
            .order("member_count", ascending: false)
            .execute()
            .value
    }

    static func detail(id: UUID) async throws -> CommunityGroup {
        try await SupabaseManager.client
            .from("community_groups_public")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func create(_ draft: NewCommunityGroup) async throws -> CommunityGroup {
        let inserted: InsertedGroupRow = try await SupabaseManager.client
            .from("community_groups")
            .insert(draft)
            .select("id")
            .single()
            .execute()
            .value
        return try await detail(id: inserted.id)
    }

    static func join(groupId: UUID, userId: UUID) async throws {
        try await SupabaseManager.client
            .from("community_group_members")
            .insert(NewGroupMember(groupId: groupId, userId: userId))
            .execute()
    }

    static func leave(groupId: UUID, userId: UUID) async throws {
        try await SupabaseManager.client
            .from("community_group_members")
            .delete()
            .eq("group_id", value: groupId)
            .eq("user_id", value: userId)
            .execute()
    }

    static func members(groupId: UUID) async throws -> [GroupMember] {
        try await SupabaseManager.client
            .from("community_group_members")
            .select("user_id, role, joined_at, profiles(full_name, avatar_url)")
            .eq("group_id", value: groupId)
            .order("joined_at", ascending: true)
            .execute()
            .value
    }

    /// Ids de los grupos a los que pertenece el usuario.
    static func myGroupIds(userId: UUID) async throws -> Set<UUID> {
        let rows: [MembershipRow] = try await SupabaseManager.client
            .from("community_group_members")
            .select("group_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        return Set(rows.map(\.groupId))
    }

    static func myGroups(userId: UUID) async throws -> [CommunityGroup] {
        let ids = try await myGroupIds(userId: userId)
        guard !ids.isEmpty else { return [] }
        return try await SupabaseManager.client
            .from("community_groups_public")
            .select()
            .in("id", values: Array(ids))
            .eq("is_hidden", value: false)
            .order("name", ascending: true)
            .execute()
            .value
    }

    /// (Moderación) Sólo un admin puede ocultar un grupo ajeno; la RLS lo exige.
    static func setHidden(groupId: UUID, hidden: Bool) async throws {
        try await SupabaseManager.client
            .from("community_groups")
            .update(["is_hidden": hidden])
            .eq("id", value: groupId)
            .execute()
    }

    /// Próximas actividades abiertas publicadas dentro del grupo.
    static func upcomingActivities(groupId: UUID) async throws -> [Activity] {
        try await SupabaseManager.client
            .from("activities_public")
            .select()
            .eq("group_id", value: groupId)
            .eq("status", value: ActivityExplicitStatus.abierta.rawValue)
            .gt("scheduled_at", value: Date())
            .order("scheduled_at", ascending: true)
            .execute()
            .value
    }
}
