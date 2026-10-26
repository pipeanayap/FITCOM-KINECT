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
    @State private var showInvite = false
    @State private var isBusy = false
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var memberToRemove: GroupMember?
    @State private var showRemoveConfirmation = false
    @State private var showForm = false
    @State private var showPhotoPicker = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero

                if let description = group.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color.brandText)
                        .cardStyle()
                }

                membershipCard
                if isCreator {
                    Button { showInvite = true } label: {
                        Label("Invitar personas", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.fitcomPrimary(disabled: isBusy || !membershipLoaded))
                    .disabled(isBusy || !membershipLoaded)
                    if membershipLoaded && !requests.isEmpty { pendingRequests }
                } else if membershipLoaded, let invitation = myRequest, invitation.isInvitation {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Te han invitado a este grupo").font(.headline)
                        responseButtons(invitation)
                    }
                    .cardStyle()
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                SectionHeaderView(title: "Próximas actividades").padding(.top, 4)
                if activities.isEmpty {
                    Text("Este grupo todavía no tiene actividades.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activities) { activity in
                        NavigationLink(value: activity.id) { ActivityRowView(activity: activity) }
                            .buttonStyle(.plain)
                    }
                }
                if isMember, let userId = authStore.userId {
                    Button("Crear actividad en este grupo") { showForm = true }
                        .buttonStyle(.fitcomPrimary)
                        .sheet(isPresented: $showForm) {
                            ActivityFormView(
                                organizerId: userId,
                                group: group,
                                saveAction: .create { try await ActivityService.create($0) },
                                onSaved: { _ in Task { await load() } }
                            )
                        }
                }

                SectionHeaderView(title: "Miembros (\(members.count))").padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(members) { member in
                        memberRow(member)
                        if member.id != members.last?.id { Divider() }
                    }
                }
                .cardStyle(padding: 12)

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .background(Color.screenBackground)
        .statusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showInvite, onDismiss: { Task { await load() } }) {
            InviteGroupMembersView(groupId: group.id, excludedIds: Set(members.map(\.userId) + requests.map(\.userId)))
        }
        .onAppear { tabBar.isHidden = true }
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
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 70, y: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let photoUrl = group.photoUrl, let url = URL(string: photoUrl) {
                CachedAsyncImage(url: url) { Color.clear }
                    .id(url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .overlay(Color.black.opacity(0.35))
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        tabBar.isHidden = false
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.18), in: Circle())
                    }
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
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.18), in: Circle())
                        }
                        .disabled(isBusy)
                    }
                }
                Spacer()
                Text([group.sport, group.zone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.75))
                Text(group.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
            .padding(20)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private var membershipCard: some View {
        HStack {
            Label(
                group.memberCount == 1 ? "1 miembro" : "\(group.memberCount) miembros",
                systemImage: "person.2.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.brandAccent)
            Spacer()
            if !authStore.isSignedIn {
                Text("Inicia sesión para unirte").font(.footnote).foregroundStyle(.secondary)
            } else if isCreator {
                Text("Eres el creador").font(.footnote).foregroundStyle(.secondary)
            } else if !membershipLoaded {
                Button("Reintentar") { Task { await load() } }
                    .font(.footnote)
                    .disabled(isBusy)
            } else if isMember {
                Button("Salir") { showLeaveConfirmation = true }
                    .buttonStyle(.fitcomSecondary(tint: .red))
                    .disabled(isBusy)
            } else {
                if let pending = myRequest {
                    Text(pending.isInvitation ? "Invitación pendiente" : "Solicitud pendiente")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Solicitar unirme") { Task { await join() } }
                        .buttonStyle(.fitcomPrimary(disabled: isBusy, fullWidth: false))
                        .disabled(isBusy)
                }
            }
        }
        .cardStyle()
    }

    private var myRequest: GroupJoinRequest? { requests.first { $0.userId == authStore.userId } }

    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "Solicitudes e invitaciones (\(requests.count))")
            ForEach(requests) { request in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink(value: ProfileRoute(userId: request.userId)) {
                        Text(request.profiles?.fullName ?? "Usuario")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandText)
                    }
                    Text(request.isInvitation ? "Invitación enviada · pendiente de respuesta" : "Solicita unirse al grupo")
                        .font(.caption).foregroundStyle(.secondary)
                    if !request.isInvitation { responseButtons(request) }
                }
                .cardStyle()
            }
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
                .buttonStyle(.plain)
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
            ZStack {
                Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 36, height: 36)
                Text(initials(member.profiles?.fullName ?? "?"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandAccent)
            }
            Text(member.profiles?.fullName ?? "Usuario").font(.subheadline).foregroundStyle(Color.brandText)
            Spacer()
            if member.isAdmin {
                Text("Admin")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.brandPrimary.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.brandPrimary)
            }
        }
        .padding(.vertical, 8)
    }

    private var isMember: Bool { members.contains { $0.userId == authStore.userId } }
    private var isCreator: Bool { group.createdBy == authStore.userId }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
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
