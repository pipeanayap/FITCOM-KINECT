import SwiftUI

/// Chat del grupo: sólo para integrantes. Los mensajes propios van a la derecha
/// en coral; los de los demás a la izquierda con su foto y nombre. El autor
/// borra los suyos (mantén presionado) y el creador del grupo puede borrar cualquiera.
struct GroupChatView: View {
    let group: CommunityGroup

    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var model: GroupChatModel
    @State private var draft = ""
    @State private var isSending = false
    @State private var isOnScreen = false
    @FocusState private var inputFocused: Bool

    init(group: CommunityGroup) {
        self.group = group
        _model = State(initialValue: GroupChatModel(groupId: group.id))
    }

    private var myId: UUID? { authStore.userId }
    private var isCreator: Bool { group.createdBy == myId }
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && myId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                LoadingStateView()
            } else if model.loadFailed {
                ErrorStateView(message: "No se pudo abrir el chat. Revisa tu conexión.") {
                    Task { await model.reload() }
                }
            } else if model.messages.isEmpty {
                EmptyStateView(
                    title: "Aún no hay mensajes",
                    message: "Escribe el primero para saludar al grupo.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                messageList
            }
        }
        .background(Color.screenBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isOnScreen = true
            tabBar.isHidden = true
        }
        // El detalle del grupo vuelve a mostrar la barra al desaparecer, y eso
        // llega después de que el chat la escondió: mientras el chat esté a la
        // vista, se vuelve a esconder.
        .onChange(of: tabBar.isHidden) { _, hidden in
            if isOnScreen && !hidden { tabBar.isHidden = true }
        }
        .task { await model.start() }
        .onDisappear {
            isOnScreen = false
            Task { await model.stop() }
        }
    }

    // MARK: - Mensajes

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? model.messages[index - 1] : nil
                        if previous == nil || !Calendar.current.isDate(previous!.createdAt, inSameDayAs: message.createdAt) {
                            dayHeader(message.createdAt)
                        }
                        let startsRun = previous == nil
                            || previous!.authorId != message.authorId
                            || !Calendar.current.isDate(previous!.createdAt, inSameDayAs: message.createdAt)
                        bubble(message, startsRun: startsRun)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Fmt.locale)).capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private func bubble(_ message: GroupMessage, startsRun: Bool) -> some View {
        let mine = message.authorId == myId
        return HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 48) } else { avatar(message, visible: startsRun) }

            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if startsRun && !mine {
                    Text(message.authorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.brandText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        mine ? Color.brandAccent : Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                Text(message.createdAt.formatted(.dateTime.hour().minute().locale(Fmt.locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.body
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                if mine || isCreator {
                    Button(role: .destructive) {
                        Task { await model.delete(message) }
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
            }

            if !mine { Spacer(minLength: 48) }
        }
        .padding(.top, startsRun ? 8 : 1)
    }

    @ViewBuilder
    private func avatar(_ message: GroupMessage, visible: Bool) -> some View {
        if visible {
            CachedAsyncImage(url: message.profiles?.avatarUrl.flatMap { URL(string: $0) }) {
                ZStack {
                    Circle().fill(Color.brandAccent.opacity(0.15))
                    Text(initials(message.authorName))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brandAccent)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else {
            Color.clear.frame(width: 30, height: 30)
        }
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }

    // MARK: - Escribir

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Mensaje", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onChange(of: draft) { _, text in
                        if text.count > GroupChatService.maxLength {
                            draft = String(text.prefix(GroupChatService.maxLength))
                        }
                    }

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(canSend ? Color.brandAccent : Color.gray.opacity(0.35), in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Enviar mensaje")
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color.screenBackground)
    }

    private func send() async {
        guard let myId, canSend else { return }
        isSending = true
        let text = draft
        draft = ""
        if await !model.send(text, authorId: myId) { draft = text }
        isSending = false
    }
}
