import SwiftUI

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
    @State private var isBusy = false
    @State private var showLeaveConfirmation = false
    @State private var showForm = false
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
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
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
                    if authStore.isAdmin {
                        // Moderación: un admin puede ocultar el grupo.
                        Menu {
                            Button(role: .destructive) { Task { await hide() } } label: {
                                Label("Ocultar grupo", systemImage: "eye.slash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.18), in: Circle())
                        }
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
            } else if isMember {
                Button("Salir") { showLeaveConfirmation = true }
                    .buttonStyle(.fitcomSecondary(tint: .red))
                    .disabled(isBusy)
            } else {
                Button("Unirme") { Task { await join() } }
                    .buttonStyle(.fitcomPrimary(disabled: isBusy, fullWidth: false))
                    .disabled(isBusy)
            }
        }
        .cardStyle()
    }

    private func memberRow(_ member: GroupMember) -> some View {
        NavigationLink(value: ProfileRoute(userId: member.userId)) { memberContent(member) }
            .buttonStyle(.plain)
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
        if let fresh = try? await GroupService.detail(id: group.id) { group = fresh }
        members = (try? await GroupService.members(groupId: group.id)) ?? []
        activities = (try? await GroupService.upcomingActivities(groupId: group.id)) ?? []
    }

    private func join() async {
        guard let userId = authStore.userId else { return }
        await perform("No se pudo unir al grupo.") {
            try await GroupService.join(groupId: group.id, userId: userId)
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
            errorMessage = failure
        }
    }
}
