import Foundation

/// Las personas de una actividad: quién la organiza y quiénes van (incluido
/// quien organiza, que se inscribe solo al crearla).
struct ActivitySocial {
    var organizer: Attendee?
    var attendees: [Attendee] = []
}

/// Trae, con dos consultas para todo un listado, las caras que muestran las
/// tarjetas de actividad (en vez de una consulta por tarjeta).
enum ActivitySocialService {
    private struct ProfileRow: Decodable {
        var id: UUID
        var fullName: String
        var avatarUrl: String?
    }

    private struct ParticipationRow: Decodable {
        var activityId: UUID
        var profiles: GroupMember.ProfileInfo?
    }

    static func load(for activities: [Activity]) async -> [UUID: ActivitySocial] {
        guard !activities.isEmpty else { return [:] }
        let activityIds = activities.map(\.id)
        let organizerIds = Array(Set(activities.map(\.organizerId)))

        async let organizerRows: [ProfileRow]? = try? SupabaseManager.client
            .from("profiles")
            .select("id, full_name, avatar_url")
            .in("id", values: organizerIds)
            .execute()
            .value
        async let participationRows: [ParticipationRow]? = try? SupabaseManager.client
            .from("participations")
            .select("activity_id, profiles(full_name, avatar_url)")
            .in("activity_id", values: activityIds)
            .eq("status", value: ParticipationStatus.activa.rawValue)
            .order("joined_at", ascending: true)
            .limit(800)
            .execute()
            .value

        let organizers = Dictionary(
            uniqueKeysWithValues: ((await organizerRows) ?? []).map {
                ($0.id, Attendee(name: $0.fullName, avatarUrl: $0.avatarUrl))
            }
        )
        var attendeesByActivity: [UUID: [Attendee]] = [:]
        for row in (await participationRows) ?? [] {
            guard let profile = row.profiles else { continue }
            attendeesByActivity[row.activityId, default: []]
                .append(Attendee(name: profile.fullName, avatarUrl: profile.avatarUrl))
        }

        var result: [UUID: ActivitySocial] = [:]
        for activity in activities {
            result[activity.id] = ActivitySocial(
                organizer: organizers[activity.organizerId],
                attendees: attendeesByActivity[activity.id] ?? []
            )
        }
        return result
    }

    private struct MemberRow: Decodable {
        var groupId: UUID
        var profiles: GroupMember.ProfileInfo?
    }

    /// Caras de quienes integran cada grupo (una sola consulta para toda la lista).
    static func loadMembers(for groups: [CommunityGroup]) async -> [UUID: [Attendee]] {
        guard !groups.isEmpty else { return [:] }
        let rows: [MemberRow]? = try? await SupabaseManager.client
            .from("community_group_members")
            .select("group_id, profiles(full_name, avatar_url)")
            .in("group_id", values: groups.map(\.id))
            .order("joined_at", ascending: true)
            .limit(800)
            .execute()
            .value
        var result: [UUID: [Attendee]] = [:]
        for row in rows ?? [] {
            guard let profile = row.profiles else { continue }
            result[row.groupId, default: []].append(Attendee(name: profile.fullName, avatarUrl: profile.avatarUrl))
        }
        return result
    }
}
