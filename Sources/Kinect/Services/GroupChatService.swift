import Foundation
import Supabase

/// Chat de los grupos. La base de datos exige que quien lee o escribe sea
/// miembro del grupo; aquí sólo se arman las consultas.
enum GroupChatService {
    private static let columns = "id, group_id, author_id, body, created_at, profiles(full_name, avatar_url)"
    static let maxLength = 1000

    /// Últimos mensajes, del más viejo al más nuevo.
    static func recent(groupId: UUID, limit: Int = 100) async throws -> [GroupMessage] {
        let rows: [GroupMessage] = try await SupabaseManager.client
            .from("group_messages")
            .select(columns)
            .eq("group_id", value: groupId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.reversed()
    }

    static func send(groupId: UUID, authorId: UUID, body: String) async throws -> GroupMessage {
        try await SupabaseManager.client
            .from("group_messages")
            .insert(NewGroupMessage(groupId: groupId, authorId: authorId, body: body))
            .select(columns)
            .single()
            .execute()
            .value
    }

    static func delete(id: UUID) async throws {
        try await SupabaseManager.client
            .from("group_messages")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

/// Estado del chat abierto: carga los mensajes y se mantiene al día con
/// Realtime. Si Realtime no conecta (p. ej. la migración aún no se aplicó),
/// cae a consultar cada pocos segundos para que el chat funcione igual.
@MainActor
@Observable
final class GroupChatModel {
    let groupId: UUID
    private(set) var messages: [GroupMessage] = []
    private(set) var isLoading = true
    private(set) var loadFailed = false
    var errorMessage: String?

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(groupId: UUID) {
        self.groupId = groupId
    }

    func start() async {
        await reload()
        isLoading = false
        await subscribe()
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        if let channel { await SupabaseManager.client.realtimeV2.removeChannel(channel) }
        channel = nil
    }

    func reload() async {
        do {
            let fresh = try await GroupChatService.recent(groupId: groupId)
            if fresh != messages { messages = fresh }
            loadFailed = false
        } catch {
            if messages.isEmpty { loadFailed = true }
        }
    }

    func send(_ text: String, authorId: UUID) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        do {
            let sent = try await GroupChatService.send(groupId: groupId, authorId: authorId, body: body)
            if !messages.contains(where: { $0.id == sent.id }) { messages.append(sent) }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "No se pudo enviar el mensaje. Intenta de nuevo."
            return false
        }
    }

    func delete(_ message: GroupMessage) async {
        let previous = messages
        messages.removeAll { $0.id == message.id }
        do {
            try await GroupChatService.delete(id: message.id)
        } catch {
            messages = previous
            errorMessage = "No se pudo eliminar el mensaje."
        }
    }

    private func subscribe() async {
        guard channel == nil else { return }
        let channel = SupabaseManager.client.realtimeV2.channel("group-chat-\(groupId.uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self, schema: "public", table: "group_messages",
            filter: .eq("group_id", value: groupId)
        )
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "group_messages")
        self.channel = channel
        tasks = [
            Task { [weak self] in for await _ in inserts { await self?.reload() } },
            Task { [weak self] in for await _ in deletes { await self?.reload() } },
        ]
        do {
            try await channel.subscribeWithError()
        } catch {
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await self?.reload()
                }
            })
        }
    }
}
