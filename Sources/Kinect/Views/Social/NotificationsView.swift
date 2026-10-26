import SwiftUI

/// Notificaciones dentro de la app (SCRUM-50): quién hizo qué y cuándo. Al
/// abrirla se marcan como leídas (las no leídas se resaltan durante la visita).
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var items: [AppNotification] = []
    @State private var unreadIds: Set<UUID> = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    tabBar.isHidden = false
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.brandText)
                        .frame(width: 36, height: 36)
                        .background(Color.cardBackground, in: Circle())
                }
                Text("Notificaciones").font(.headline).foregroundStyle(Color.brandText)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                Spacer(); ProgressView().tint(.brandAccent); Spacer()
            } else if items.isEmpty {
                EmptyStateView(
                    title: "Sin notificaciones",
                    message: "Aquí verás la actividad de tu comunidad y las solicitudes e invitaciones a grupos.",
                    systemImage: "bell"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in row(item) }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color.screenBackground)
        .statusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: GroupRoute.self) { route in GroupLoaderView(id: route.id) }
        .task { await load() }
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
        }
    }

    @ViewBuilder
    private func row(_ item: AppNotification) -> some View {
        switch item.kind {
        case "group_request", "group_invitation", "group_accepted", "group_rejected":
            if let groupId = item.groupId {
                NavigationLink(value: GroupRoute(id: groupId)) { content(item) }.buttonStyle(.plain)
            } else {
                content(item)
            }
        case "follow":
            NavigationLink(value: ProfileRoute(userId: item.actorId)) { content(item) }.buttonStyle(.plain)
        case "join":
            if let activityId = item.activityId {
                NavigationLink(value: activityId) { content(item) }.buttonStyle(.plain)
            } else {
                content(item)
            }
        default:
            if let postId = item.postId {
                NavigationLink(value: PostRoute(id: postId)) { content(item) }.buttonStyle(.plain)
            } else {
                content(item)
            }
        }
    }

    private func content(_ item: AppNotification) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.brandAccent.opacity(0.15))
                if let urlString = item.actorAvatar, !urlString.isEmpty, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { initials(item) }.clipShape(Circle())
                } else {
                    initials(item)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol(item.kind))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(color(item.kind), in: Circle())
                    .overlay(Circle().stroke(Color.cardBackground, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(item.actorName).fontWeight(.bold)) \(item.text)")
                    .font(.subheadline)
                    .foregroundStyle(Color.brandText)
                    .multilineTextAlignment(.leading)
                Text(Fmt.relative(item.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if unreadIds.contains(item.id) {
                Circle().fill(Color.brandAccent).frame(width: 9, height: 9)
            }
        }
        .padding(12)
        .background(
            unreadIds.contains(item.id) ? Color.brandAccent.opacity(0.08) : Color.cardBackground,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func initials(_ item: AppNotification) -> some View {
        Text(String(item.actorName.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }

    private func symbol(_ kind: String) -> String {
        switch kind {
        case "like": "heart.fill"
        case "comment": "bubble.right.fill"
        case "follow": "person.fill.badge.plus"
        case "group_request", "group_invitation", "group_accepted", "group_rejected": "person.3.fill"
        default: "figure.run"
        }
    }

    private func color(_ kind: String) -> Color {
        switch kind {
        case "like": .red
        case "comment": .brandPrimary
        case "follow": .brandAccent
        default: .brandWarning
        }
    }

    private func load() async {
        defer { isLoading = false }
        items = (try? await NotificationService.list()) ?? []
        unreadIds = Set(items.filter { $0.readAt == nil }.map(\.id))
        if let userId = authStore.userId { await NotificationService.markAllRead(userId: userId) }
    }
}

/// Abre un post a partir de su id (las notificaciones sólo traen el id).
struct PostLoaderView: View {
    let id: UUID

    @State private var post: Post?
    @State private var failed = false

    var body: some View {
        Group {
            if let post {
                PostDetailView(post: post)
            } else if failed {
                EmptyStateView(title: "Publicación no disponible", message: "Puede que se haya eliminado.", systemImage: "text.bubble")
            } else {
                LoadingStateView()
            }
        }
        .task {
            do { post = try await PostService.detail(id: id) } catch { failed = true }
        }
    }
}

/// Las notificaciones guardan el id; el grupo puede haber sido eliminado u ocultado.
struct GroupLoaderView: View {
    let id: UUID
    @State private var group: CommunityGroup?
    @State private var failed = false

    var body: some View {
        Group {
            if let group {
                GroupDetailView(group: group, onChange: {})
            } else if failed {
                EmptyStateView(title: "Grupo no disponible", message: "Puede que se haya eliminado u ocultado.", systemImage: "person.3")
            } else {
                LoadingStateView()
            }
        }
        .task {
            do { group = try await GroupService.detail(id: id) } catch { failed = true }
        }
    }
}
