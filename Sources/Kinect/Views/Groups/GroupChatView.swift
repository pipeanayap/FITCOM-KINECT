import SwiftUI

/// Chat del grupo: sólo para integrantes. Los mensajes propios van a la derecha
/// en coral; los de los demás a la izquierda con su foto y nombre. El autor
/// borra los suyos (mantén presionado) y el creador del grupo puede borrar
/// cualquiera; al borrar hay 4 segundos para deshacer.
struct GroupChatView: View {
    let group: CommunityGroup

    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var model: GroupChatModel
    @State private var draft = ""
    @State private var isSending = false
    @State private var isOnScreen = false
    @State private var sentToken = 0
    /// La pista de "mantén presionado" sólo se muestra la primera vez.
    @State private var showHint = !UserDefaults.standard.bool(forKey: "chat.hintSeen")
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
                    await model.reload()
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
            ChatReadState.markSeen(group.id)
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
            ChatReadState.markSeen(group.id)
            if showHint { UserDefaults.standard.set(true, forKey: "chat.hintSeen") }
            Task { await model.stop() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: sentToken)
        .animation(.easeOut(duration: 0.18), value: model.pendingDelete?.id)
    }

    // MARK: - Mensajes

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if showHint {
                        Text("Mantén presionado un mensaje para copiarlo o eliminarlo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        let layout = layout(at: index)
                        if layout.newDay { dayHeader(message.createdAt) }
                        bubble(message, startsRun: layout.startsRun)
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
                ChatReadState.markSeen(group.id)
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    /// Si el mensaje abre un día nuevo y si empieza una racha de la misma persona
    /// (sólo entonces lleva foto y nombre).
    private func layout(at index: Int) -> (newDay: Bool, startsRun: Bool) {
        guard index > 0 else { return (true, true) }
        let previous = model.messages[index - 1]
        let current = model.messages[index]
        let newDay = !Calendar.current.isDate(previous.createdAt, inSameDayAs: current.createdAt)
        return (newDay, newDay || previous.authorId != current.authorId)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(mine ? "Tú" : message.authorName): \(message.body)")

            if !mine { Spacer(minLength: 48) }
        }
        .padding(.top, startsRun ? 8 : 1)
    }

    @ViewBuilder
    private func avatar(_ message: GroupMessage, visible: Bool) -> some View {
        if visible {
            AvatarView(url: message.profiles?.avatarUrl, name: message.authorName, size: 30)
        } else {
            Color.clear.frame(width: 30, height: 30)
        }
    }

    // MARK: - Escribir

    private var inputBar: some View {
        VStack(spacing: 6) {
            if model.pendingDelete != nil {
                HStack {
                    Text("Mensaje eliminado")
                        .font(.subheadline)
                        .foregroundStyle(Color.brandText)
                    Spacer()
                    Button("Deshacer") { model.undoDelete() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandAccentText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.cardBackground, in: Capsule())
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
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
                        .frame(width: 44, height: 44)
                        .background(canSend ? Color.brandAccent : Color.gray.opacity(0.35), in: Circle())
                }
                .buttonStyle(.fitcomPressable)
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
        if await model.send(text, authorId: myId) {
            sentToken += 1
        } else {
            draft = text
        }
        isSending = false
    }
}
