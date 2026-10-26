import Foundation
import Supabase

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

    /// Comprueba el esquema antes de subir una imagen para evitar archivos sin referencia.
    static func checkPhotoSupport() async throws {
        try await SupabaseManager.client
            .from("community_groups")
            .select("photo_url")
            .limit(1)
            .execute()
    }

    static func failureMessage(_ error: Error, fallback: String) -> String {
        if let databaseError = error as? PostgrestError {
            if databaseError.code == "P0001" { return databaseError.message }
            if databaseError.code == "23505" { return "Ya existe una solicitud o invitación pendiente." }
            if ["PGRST202", "PGRST205", "42P01"].contains(databaseError.code ?? "") {
                return "Esta función de grupos aún no está habilitada en el servidor."
            }
            if ["42703", "PGRST204"].contains(databaseError.code ?? ""),
               databaseError.message.contains("photo_url") {
                return "Las fotos de grupos aún no están habilitadas en el servidor."
            }
            if databaseError.code == "42501" {
                return "No tienes permiso para realizar este cambio en el grupo."
            }
        }
        if let storageError = error as? StorageError {
            if storageError.message.lowercased().contains("bucket") {
                return "El almacenamiento de fotos no está disponible en el servidor."
            }
            if storageError.statusCode == "403" || storageError.statusCode == "401" {
                return "No se pudo subir la foto. Vuelve a iniciar sesión e intenta de nuevo."
            }
            return "No se pudo subir la foto. Revisa tu conexión e intenta de nuevo."
        }
        return fallback
    }

    /// La RLS permite borrar únicamente al creador. Exige una fila devuelta
    /// para no interpretar un borrado rechazado por RLS como un éxito.
    static func delete(groupId: UUID) async throws {
        let _: InsertedGroupRow = try await SupabaseManager.client
            .from("community_groups")
            .delete()
            .eq("id", value: groupId)
            .select("id")
            .single()
            .execute()
            .value
    }

    static func setPhoto(groupId: UUID, photoUrl: String) async throws -> CommunityGroup {
        let _: InsertedGroupRow = try await SupabaseManager.client
            .from("community_groups")
            .update(["photo_url": photoUrl])
            .eq("id", value: groupId)
            .select("id")
            .single()
            .execute()
            .value
        return try await detail(id: groupId)
    }

    private struct SendRequestParams: Encodable {
        var pGroupId: UUID
        var pUserId: UUID
        var pKind: String
    }

    private struct RespondRequestParams: Encodable {
        var pGroupId: UUID
        var pUserId: UUID
        var pAccept: Bool
    }

    static func sendRequest(groupId: UUID, userId: UUID, invitation: Bool = false) async throws {
        try await SupabaseManager.client
            .rpc("send_group_request", params: SendRequestParams(
                pGroupId: groupId, pUserId: userId, pKind: invitation ? "invitation" : "request"
            ))
            .execute()
    }

    static func respond(groupId: UUID, userId: UUID, accept: Bool) async throws {
        try await SupabaseManager.client
            .rpc("respond_group_request", params: RespondRequestParams(
                pGroupId: groupId, pUserId: userId, pAccept: accept
            ))
            .execute()
    }

    static func requests(groupId: UUID) async throws -> [GroupJoinRequest] {
        try await SupabaseManager.client
            .from("community_group_requests")
            .select("id, group_id, user_id, kind, profiles(full_name, avatar_url)")
            .eq("group_id", value: groupId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Busca por @usuario; evita interpolar filtros o descargar todos los perfiles.
    static func inviteCandidates(username: String) async throws -> [GroupInviteCandidate] {
        let term = username.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        guard term.count >= 2 else { return [] }
        return try await SupabaseManager.client
            .from("profiles")
            .select("id, full_name, username")
            .ilike("username", pattern: "%\(term.replacingOccurrences(of: "_", with: "\\_"))%")
            .order("username", ascending: true)
            .limit(20)
            .execute()
            .value
    }

    private struct RemoveMemberParams: Encodable {
        var pGroupId: UUID
        var pUserId: UUID
    }

    static func removeMember(groupId: UUID, userId: UUID) async throws {
        try await SupabaseManager.client
            .rpc("remove_group_member", params: RemoveMemberParams(pGroupId: groupId, pUserId: userId))
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
