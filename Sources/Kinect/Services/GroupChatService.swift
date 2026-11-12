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

    /// Sólo lo posterior a `date`: con cada mensaje nuevo no hace falta volver a
    /// pedir los 100 anteriores.
    static func newer(than date: Date, groupId: UUID) async throws -> [GroupMessage] {
        try await SupabaseManager.client
            .from("group_messages")
            .select(columns)
            .eq("group_id", value: groupId)
            .gt("created_at", value: date)
            .order("created_at", ascending: true)
            .limit(100)
            .execute()
            .value
    }

    private struct LatestRow: Decodable {
        var createdAt: Date
        var authorId: UUID
    }

    /// ¿Hay algo escrito por otra persona después de la última vez que abriste el chat?
    static func hasUnread(groupId: UUID, me: UUID?, since lastSeen: Date?) async -> Bool {
        let rows: [LatestRow]? = try? await SupabaseManager.client
            .from("group_messages")
            .select("created_at, author_id")
            .eq("group_id", value: groupId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard let latest = rows?.first, latest.authorId != me else { return false }
        guard let lastSeen else { return true }
        return latest.createdAt > lastSeen
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

/// Cuándo abriste por última vez el chat de cada grupo (sólo en este iPhone),
/// para marcar "Nuevos mensajes" en el detalle del grupo.
enum ChatReadState {
    private static func key(_ groupId: UUID) -> String { "chat.lastSeen.\(groupId.uuidString)" }

    static func lastSeen(_ groupId: UUID) -> Date? {
        UserDefaults.standard.object(forKey: key(groupId)) as? Date
    }

    static func markSeen(_ groupId: UUID) {
        UserDefaults.standard.set(Date(), forKey: key(groupId))
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
    /// Mensaje quitado de la lista que todavía se puede deshacer (4 s).
    private(set) var pendingDelete: GroupMessage?
    var errorMessage: String?

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var deleteTask: Task<Void, Never>?

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
        // Salir de la pantalla confirma el borrado pendiente.
        if let message = pendingDelete {
            deleteTask?.cancel()
            await commitDelete(message)
        }
    }

    /// Carga completa (al abrir). Respeta un borrado que aún se puede deshacer.
    func reload() async {
        do {
            let fresh = try await GroupChatService.recent(groupId: groupId)
                .filter { $0.id != pendingDelete?.id }
            if fresh != messages { messages = fresh }
            loadFailed = false
        } catch {
            AppLog.chat.error("Cargar chat falló: \(error.localizedDescription, privacy: .public)")
            if messages.isEmpty { loadFailed = true }
        }
    }

    /// Sólo lo nuevo desde el último mensaje conocido.
    func loadNewer() async {
        guard let last = messages.last else {
            await reload()
            return
        }
        do {
            let fresh = try await GroupChatService.newer(than: last.createdAt, groupId: groupId)
            let known = Set(messages.map(\.id))
            let added = fresh.filter { !known.contains($0.id) && $0.id != pendingDelete?.id }
            if !added.isEmpty { messages.append(contentsOf: added) }
        } catch {
            AppLog.chat.error("Mensajes nuevos fallaron: \(error.localizedDescription, privacy: .public)")
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
            AppLog.chat.error("Enviar mensaje falló: \(error.localizedDescription, privacy: .public)")
            errorMessage = ErrorText.describe(error, fallback: "No se pudo enviar el mensaje. Intenta de nuevo.")
            return false
        }
    }

    /// Quita el mensaje de la lista y deja 4 segundos para deshacer; después se borra de verdad.
    func delete(_ message: GroupMessage) async {
        if let earlier = pendingDelete {
            deleteTask?.cancel()
            await commitDelete(earlier)
        }
        messages.removeAll { $0.id == message.id }
        pendingDelete = message
        deleteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.commitDelete(message)
        }
    }

    func undoDelete() {
        deleteTask?.cancel()
        deleteTask = nil
        guard let message = pendingDelete else { return }
        pendingDelete = nil
        messages.append(message)
        messages.sort { $0.createdAt < $1.createdAt }
    }

    private func commitDelete(_ message: GroupMessage) async {
        pendingDelete = nil
        do {
            try await GroupChatService.delete(id: message.id)
        } catch {
            AppLog.chat.error("Borrar mensaje falló: \(error.localizedDescription, privacy: .public)")
            messages.append(message)
            messages.sort { $0.createdAt < $1.createdAt }
            errorMessage = ErrorText.describe(error, fallback: "No se pudo eliminar el mensaje.")
        }
    }

    /// Alguien más borró un mensaje: sólo se quita si es de este chat.
    private func removeLocally(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    private func subscribe() async {
        guard channel == nil else { return }
        let channel = SupabaseManager.client.realtimeV2.channel("group-chat-\(groupId.uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self, schema: "public", table: "group_messages",
            filter: .eq("group_id", value: groupId)
        )
        // Los borrados no se pueden filtrar por grupo: sólo se actúa si el id es de este chat.
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "group_messages")
        self.channel = channel
        tasks = [
            Task { [weak self] in for await _ in inserts { await self?.loadNewer() } },
            Task { [weak self] in
                for await action in deletes {
                    guard let raw = action.oldRecord["id"]?.stringValue, let id = UUID(uuidString: raw) else { continue }
                    await self?.removeLocally(id: id)
                }
            },
        ]
        do {
            try await channel.subscribeWithError()
        } catch {
            AppLog.chat.error("Realtime no conectó, se consulta cada 4 s: \(error.localizedDescription, privacy: .public)")
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await self?.loadNewer()
                }
            })
        }
    }
}
