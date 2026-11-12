import SwiftUI
import UIKit

/// Detalle de un grupo (SCRUM-41): unirse/salir, miembros, próximas
/// actividades del grupo y atajo para publicar una actividad en él.
struct GroupDetailView: View {
    @State var group: CommunityGroup
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var members: [GroupMember] = []
    @State private var activities: [Activity] = []
    @State private var requests: [GroupJoinRequest] = []
    @State private var membershipLoaded = false
    /// Hay mensajes de otra persona que aún no has visto en el chat.
    @State private var chatHasNew = false
    @State private var showInvite = false
    @State private var isBusy = false
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var memberToRemove: GroupMember?
    @State private var showRemoveConfirmation = false
    @State private var showForm = false
    @State private var showPhotoPicker = false
    @State private var showAllMembers = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                // Lo que pide una respuesta va primero: solicitudes (si creas el grupo)
                // o la invitación que te mandaron.
                if isCreator, membershipLoaded, !requests.isEmpty {
                    pendingRequests
                } else if !isCreator, membershipLoaded, let invitation = myRequest, invitation.isInvitation {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Te invitaron a este grupo", systemImage: "envelope.open.fill")
                            .font(.cardTitle)
                            .foregroundStyle(Color.brandText)
                        responseButtons(invitation)
                    }
                    .cardStyle()
                }

                if membershipLoaded && (isMember || isCreator) {
                    actionRow
                } else {
                    joinArea
                }

                if let description = group.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                activitiesSection
                membersSection

                // Salir es poco frecuente y destructivo: va al final y discreto.
                if membershipLoaded, isMember, !isCreator {
                    Button("Salir del grupo") { showLeaveConfirmation = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandDangerText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isBusy)
                }

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .background(Color.screenBackground)
        .statusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showForm) {
            if let userId = authStore.userId {
                ActivityFormView(
                    organizerId: userId,
                    group: group,
                    saveAction: .create { try await ActivityService.create($0) },
                    onSaved: { _ in Task { await load() } }
                )
            }
        }
        .sheet(isPresented: $showInvite, onDismiss: { Task { await load() } }) {
            InviteGroupMembersView(groupId: group.id, excludedIds: Set(members.map(\.userId) + requests.map(\.userId)))
        }
        .onAppear {
            tabBar.isHidden = true
            // Al volver del chat, el aviso se apaga (o aparece si llegó algo mientras tanto).
            Task { await refreshChatBadge() }
        }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(limit: 1) { picked in
                showPhotoPicker = false
                if let image = picked.first { Task { await updatePhoto(image) } }
            }
        }
        .confirmationDialog("¿Eliminar integrante?", isPresented: $showRemoveConfirmation, titleVisibility: .visible, presenting: memberToRemove) { member in
            Button("Eliminar del grupo", role: .destructive) { Task { await removeMember(member) } }
            Button("Cancelar", role: .cancel) {}
        } message: { member in
            Text("\(member.profiles?.fullName ?? "Esta persona") dejará de pertenecer al grupo. Para volver a entrar necesitará una nueva solicitud o invitación.")
        }
        .confirmationDialog("¿Eliminar este grupo?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Eliminar grupo", role: .destructive) { Task { await deleteGroup() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán el grupo y su lista de miembros. Las actividades y publicaciones se conservarán sin el grupo. Esta acción no se puede deshacer.")
        }
        .confirmationDialog("¿Salir de este grupo?", isPresented: $showLeaveConfirmation, titleVisibility: .visible) {
            Button("Salir del grupo", role: .destructive) { Task { await leave() } }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            SportVisuals.gradient(for: group.sport ?? "")
            Image(systemName: group.sport.map(SportVisuals.symbol(for:)) ?? "person.3.fill")
                .font(.system(size: 150, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12))
                .offset(x: 60, y: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let photoUrl = group.photoUrl, let url = URL(string: photoUrl) {
                CachedAsyncImage(url: url) { Color.clear }
                    .id(url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        tabBar.isHidden = false
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.22), in: Circle())
                    }
                    .buttonStyle(.fitcomPressable)
                    .accessibilityLabel("Volver")
                    Spacer()
                    if isBusy { ProgressView().tint(.white) }
                    if isCreator || authStore.isAdmin {
                        // Moderación: un admin puede ocultar el grupo.
                        Menu {
                            if isCreator {
                                Button { showPhotoPicker = true } label: {
                                    Label(group.photoUrl == nil ? "Agregar foto" : "Cambiar foto", systemImage: "photo")
                                }
                                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                                    Label("Eliminar grupo", systemImage: "trash")
                                }
                            }
                            if authStore.isAdmin {
                                Button(role: .destructive) { Task { await hide() } } label: {
                                    Label("Ocultar grupo", systemImage: "eye.slash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.22), in: Circle())
                        }
                        .disabled(isBusy)
                        .accessibilityLabel("Más opciones")
                    }
                }
                Spacer(minLength: 12)
                Text([group.sport, group.zone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .metaCaps(.white.opacity(0.85))
                    .lineLimit(1)
                Text(group.name)
                    .font(.displayL)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 2)

                // Quiénes están y cuál es tu lugar, en una sola línea.
                HStack(spacing: 8) {
                    if !members.isEmpty {
                        AvatarStack(people: members.map { Attendee(name: $0.profiles?.fullName ?? "", avatarUrl: $0.profiles?.avatarUrl) },
                                    total: max(members.count, group.memberCount), size: 28, ring: .white)
                    }
                    Text(group.memberCount == 1 ? "1 miembro" : "\(group.memberCount) miembros")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if let role = roleLabel {
                        Text(role)
                            .metaCaps(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.22), in: Capsule())
                    }
                }
                .padding(.top, 10)
            }
            .padding(20)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: DS.heroRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    /// Tu lugar en el grupo, para que se entienda de un vistazo.
    private var roleLabel: String? {
        guard authStore.isSignedIn, membershipLoaded else { return nil }
        if isCreator { return "Creador" }
        if isMember { return "Miembro" }
        if let pending = myRequest { return pending.isInvitation ? "Invitación" : "Solicitud enviada" }
        return nil
    }

    // MARK: - Acciones

    /// Las tres cosas que se hacen aquí, como botones iguales: el chat (lo principal) en
    /// coral y el resto en suave. Sustituye a los dos botones gigantes de antes.
    private var actionRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                GroupChatView(group: group)
            } label: {
                actionTile(icon: "bubble.left.and.bubble.right.fill", title: "Chat", filled: true, badge: chatHasNew)
            }
            .buttonStyle(.fitcomPressable)
            .accessibilityHint(chatHasNew ? "Hay mensajes nuevos" : "")

            if isCreator {
                Button { showInvite = true } label: {
                    actionTile(icon: "person.badge.plus", title: "Invitar")
                }
                .buttonStyle(.fitcomPressable)
                .disabled(isBusy)
            }

            Button { showForm = true } label: {
                actionTile(icon: "calendar.badge.plus", title: "Actividad")
            }
            .buttonStyle(.fitcomPressable)
            .disabled(isBusy)
        }
    }

    private func actionTile(icon: String, title: String, filled: Bool = false, badge: Bool = false) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(filled ? Color.white : Color.brandAccent)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(filled ? Color.white : Color.brandAccent)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(filled ? Color.brandAccent : Color.cardBackground, lineWidth: 2))
                            .offset(x: 6, y: -4)
                    }
                }
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(filled ? Color.white : Color.brandText)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            filled ? Color.brandAccent : Color.cardBackground,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    /// Para quien aún no es del grupo: iniciar sesión, solicitar o esperar respuesta.
    @ViewBuilder
    private var joinArea: some View {
        if !authStore.isSignedIn {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inicia sesión para unirte a este grupo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Iniciar sesión") { tabBar.requestedAuthReason = "Inicia sesión para unirte a este grupo." }
                    .buttonStyle(.fitcomPrimary(disabled: false))
            }
        } else if !membershipLoaded {
            HStack(spacing: 10) {
                if errorMessage == nil { ProgressView() }
                Button("Reintentar") { Task { await load() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isBusy)
            }
            .frame(maxWidth: .infinity)
        } else if let pending = myRequest, !pending.isInvitation {
            Label("Solicitud enviada. Te avisaremos cuando respondan.", systemImage: "hourglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        } else if myRequest == nil {
            Button("Solicitar unirme") { Task { await join() } }
                .buttonStyle(.fitcomPrimary(disabled: isBusy))
                .disabled(isBusy)
        }
    }

    // MARK: - Secciones

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "Próximas actividades")
            if activities.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(Color.brandAccent)
                    Text(isMember || isCreator
                         ? "Aún no hay actividades. Crea la primera con el botón de arriba."
                         : "Este grupo todavía no tiene actividades.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            } else {
                ForEach(activities) { activity in
                    NavigationLink(value: activity.id) { ActivityRowView(activity: activity) }
                        .buttonStyle(.fitcomPressable)
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeaderView(title: "Miembros")
                if members.count > 5 {
                    Button(showAllMembers ? "Ver menos" : "Ver todos (\(members.count))") {
                        withAnimation(.easeOut(duration: 0.2)) { showAllMembers.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandAccentText)
                }
            }
            let shown = showAllMembers ? members : Array(members.prefix(5))
            VStack(spacing: 0) {
                ForEach(shown) { member in
                    memberRow(member)
                    if member.id != shown.last?.id { Divider() }
                }
            }
            .cardStyle(padding: 12)
        }
    }

    private var myRequest: GroupJoinRequest? { requests.first { $0.userId == authStore.userId } }

    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "Pendientes (\(requests.count))")
            VStack(spacing: 0) {
                ForEach(requests) { request in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink(value: ProfileRoute(userId: request.userId)) {
                            HStack(spacing: 12) {
                                AvatarView(url: request.profiles?.avatarUrl, name: request.profiles?.fullName ?? "", size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.profiles?.fullName ?? "Usuario")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Color.brandText)
                                    Text(request.isInvitation ? "Invitación enviada, sin respuesta" : "Quiere unirse al grupo")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.fitcomPressable)
                        if !request.isInvitation { responseButtons(request) }
                    }
                    .padding(.vertical, 8)
                    if request.id != requests.last?.id { Divider() }
                }
            }
            .cardStyle(padding: 12)
        }
    }

    private func responseButtons(_ request: GroupJoinRequest) -> some View {
        HStack(spacing: 12) {
            Button("Aceptar") { Task { await respond(request, accept: true) } }
                .buttonStyle(.fitcomPrimary(disabled: isBusy, fullWidth: false))
            Button("Rechazar") { Task { await respond(request, accept: false) } }
                .buttonStyle(.fitcomSecondary(tint: .red))
        }
        .disabled(isBusy || !membershipLoaded)
    }

    private func respond(_ request: GroupJoinRequest, accept: Bool) async {
        guard !isBusy else { return }
        await perform("No se pudo responder. Actualiza el grupo e intenta de nuevo.") {
            try await GroupService.respond(groupId: group.id, userId: request.userId, accept: accept)
        }
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: ProfileRoute(userId: member.userId)) { memberContent(member) }
                .buttonStyle(.fitcomPressable)
            if isCreator, member.userId != group.createdBy {
                Menu {
                    Button(role: .destructive) {
                        memberToRemove = member
                        showRemoveConfirmation = true
                    } label: {
                        Label("Eliminar del grupo", systemImage: "person.fill.xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandText)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(isBusy || !membershipLoaded)
                .accessibilityLabel("Opciones de \(member.profiles?.fullName ?? "integrante")")
            }
        }
    }

    private func removeMember(_ member: GroupMember) async {
        guard isCreator, member.userId != group.createdBy, !isBusy else { return }
        await perform("No se pudo eliminar al integrante. Intenta de nuevo.") {
            try await GroupService.removeMember(groupId: group.id, userId: member.userId)
        }
        memberToRemove = nil
    }

    private func memberContent(_ member: GroupMember) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: member.profiles?.avatarUrl, name: member.profiles?.fullName ?? "", size: 40)
            Text(member.profiles?.fullName ?? "Usuario")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.brandText)
                .lineLimit(1)
            Spacer()
            if member.userId == group.createdBy {
                roleChip("Creador", tint: .brandPrimaryText, fill: .brandPrimary)
            } else if member.isAdmin {
                roleChip("Admin", tint: .brandPrimaryText, fill: .brandPrimary)
            }
        }
        .padding(.vertical, 6)
    }

    private func roleChip(_ text: String, tint: Color, fill: Color) -> some View {
        Text(text)
            .metaCaps(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill.opacity(0.15), in: Capsule())
    }

    private var isMember: Bool { members.contains { $0.userId == authStore.userId } }
    private var isCreator: Bool { group.createdBy == authStore.userId }

    private func refreshChatBadge() async {
        guard membershipLoaded, isMember || isCreator else {
            chatHasNew = false
            return
        }
        chatHasNew = await GroupChatService.hasUnread(
            groupId: group.id, me: authStore.userId, since: ChatReadState.lastSeen(group.id)
        )
    }

    private func load() async {
        membershipLoaded = false
        do {
            group = try await GroupService.detail(id: group.id)
            members = try await GroupService.members(groupId: group.id)
            if authStore.isSignedIn {
                requests = try await GroupService.requests(groupId: group.id)
            } else {
                requests = []
            }
            membershipLoaded = true
            errorMessage = nil
            await refreshChatBadge()
        } catch {
            errorMessage = GroupService.failureMessage(error, fallback: "No se pudieron cargar las solicitudes del grupo. Desliza para reintentar.")
        }
        activities = (try? await GroupService.upcomingActivities(groupId: group.id)) ?? []
    }

    private func updatePhoto(_ image: UIImage) async {
        guard isCreator, !isBusy, let userId = authStore.userId else { return }
        guard let data = ImageUploadService.prepare(image) else {
            errorMessage = "No se pudo preparar la foto. Elige otra imagen."
            return
        }
        await perform("No se pudo guardar la foto del grupo.") {
            try await GroupService.checkPhotoSupport()
            let path = try await ImageUploadService.upload(data, userId: userId)
            guard let url = ImageUploadService.publicURL(for: path) else {
                await ImageUploadService.delete(paths: [path])
                throw URLError(.badURL)
            }
            group = try await GroupService.setPhoto(groupId: group.id, photoUrl: url.absoluteString)
        }
    }

    private func deleteGroup() async {
        guard isCreator, !isBusy else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await GroupService.delete(groupId: group.id)
            onChange()
            tabBar.isHidden = false
            dismiss()
        } catch {
            errorMessage = GroupService.failureMessage(error, fallback: "No se pudo eliminar el grupo. Intenta de nuevo.")
        }
    }

    private func join() async {
        guard !isBusy, membershipLoaded, let userId = authStore.userId else { return }
        await perform("No se pudo enviar la solicitud.") {
            try await GroupService.sendRequest(groupId: group.id, userId: userId)
        }
    }

    private func leave() async {
        guard let userId = authStore.userId else { return }
        await perform("No se pudo salir del grupo.") {
            try await GroupService.leave(groupId: group.id, userId: userId)
        }
    }

    private func hide() async {
        do {
            try await GroupService.setHidden(groupId: group.id, hidden: true)
            onChange()
            tabBar.isHidden = false
            dismiss()
        } catch {
            errorMessage = "No se pudo ocultar el grupo."
        }
    }

    private func perform(_ failure: String, _ action: () async throws -> Void) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await action()
            await load()
            onChange()
        } catch {
            errorMessage = GroupService.failureMessage(error, fallback: failure)
        }
    }
}
