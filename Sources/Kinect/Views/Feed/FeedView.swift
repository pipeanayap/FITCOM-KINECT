import SwiftUI

private struct ActivityIdRow: Decodable { var activityId: UUID }

private struct ImageViewerItem: Identifiable {
    let id = UUID()
    let post: Post
    let index: Int
}

private enum FeedMode { case forYou, following }

/// Pestaña Inicio: historias, selector Para ti / Siguiendo y feed paginado
/// (SCRUM-43, 48, 49). Cada actividad nueva aparece sola como post; desde ahí
/// se puede unir uno (SCRUM-45). La campana lleva a las notificaciones (SCRUM-50).
struct FeedView: View {
    @Environment(AuthStore.self) private var authStore

    let onOpenProfile: () -> Void
    /// Sube cuando se crea algo desde el menú central para recargar el feed.
    var refreshToken = 0

    @State private var posts: [Post] = []
    @State private var activities: [UUID: Activity] = [:]
    @State private var joinedIds: Set<UUID> = []
    @State private var followingIds: Set<UUID> = []
    @State private var mode: FeedMode = .forYou
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var joiningId: UUID?
    @State private var path = NavigationPath()
    @State private var reportTarget: Post?
    @State private var viewer: ImageViewerItem?
    @State private var myStories: [Story] = []
    @State private var storyGroups: [StoryGroup] = []
    @State private var storyViewer: StoryViewerItem?
    @State private var showStoryCompose = false
    @State private var unreadCount = 0

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage, retry: reload)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 26) {
                            VStack(alignment: .leading, spacing: 14) {
                                header.padding(.horizontal)
                                if authStore.isSignedIn || !storyGroups.isEmpty { storiesRow }
                                modePicker.padding(.horizontal)
                            }

                            if let actionError {
                                Label(actionError, systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                                    .padding(.horizontal)
                            }

                            if posts.isEmpty { emptyState.padding(.horizontal) }

                            ForEach($posts) { $post in
                                PostCardView(
                                    post: $post,
                                    activity: post.activityId.flatMap { activities[$0] },
                                    isJoined: post.activityId.map { joinedIds.contains($0) } ?? false,
                                    isJoining: joiningId == post.activityId && joiningId != nil,
                                    onJoin: { join($0) },
                                    onDelete: { delete($0) },
                                    onHide: { hide($0) },
                                    onReport: { reportTarget = $0 },
                                    onOpenImages: { viewer = ImageViewerItem(post: $0, index: $1) }
                                )
                                .onAppear {
                                    if post.id == posts.last?.id { Task { await loadMore() } }
                                }
                            }

                            if isLoadingMore {
                                ProgressView().tint(.brandAccent).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .background(Color.screenBackground)
                    .statusBarCover()
                    .refreshable { await reload() }
                }
            }
            .background(Color.screenBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { ActivityDetailView(activityId: $0) }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationDestination(for: PostRoute.self) { PostLoaderView(id: $0.id) }
            .navigationDestination(for: ProfileRoute.self) { PublicProfileView(userId: $0.userId) }
            .navigationDestination(for: NotificationsRoute.self) { _ in NotificationsView() }
            .navigationDestination(for: CommunityGroup.self) { group in GroupDetailView(group: group) {} }
            .sheet(item: $reportTarget) { ReportPostView(postId: $0.id) }
            .sheet(isPresented: $showStoryCompose) {
                StoryComposeView { Task { await loadStories() } }
            }
            .fullScreenCover(item: $viewer) { item in
                ImageViewerView(
                    post: item.post,
                    index: item.index,
                    onChange: { updated in
                        if let position = posts.firstIndex(where: { $0.id == updated.id }) { posts[position] = updated }
                    },
                    onOpenComments: { post in
                        // Espera a que el visor termine de cerrarse antes de abrir el post.
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            path.append(post)
                        }
                    }
                )
            }
            .fullScreenCover(item: $storyViewer, onDismiss: { Task { await loadStories() } }) { item in
                StoryViewerView(item: item) { Task { await loadStories() } }
            }
            .task { await reload() }
            .onChange(of: authStore.userId) { _, _ in Task { await reload() } }
            .onChange(of: refreshToken) { _, _ in Task { await reload() } }
            .onChange(of: mode) { _, _ in Task { await reload() } }
            // Al volver de las notificaciones se actualiza el indicador.
            .onChange(of: path.count) { _, _ in Task { await loadUnread() } }
        }
    }

    // MARK: - Encabezado

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inicio").font(.largeTitle.bold()).foregroundStyle(Color.brandText)
                Text("Lo que pasa en tu comunidad").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if authStore.isSignedIn {
                NavigationLink(value: NotificationsRoute()) {
                    Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(unreadCount > 0 ? Color.brandAccent : Color.brandText)
                        .frame(width: 46, height: 46)
                        .background(Color.cardBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notificaciones")
            }
            Button(action: onOpenProfile) {
                ZStack {
                    Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 46, height: 46)
                    if let urlString = authStore.profile?.avatarUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                        CachedAsyncImage(url: url) {
                            Text(initials).font(.subheadline.weight(.bold)).foregroundStyle(Color.brandAccent)
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    } else {
                        Text(initials).font(.subheadline.weight(.bold)).foregroundStyle(Color.brandAccent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var initials: String {
        guard let name = authStore.profile?.fullName, !name.isEmpty else { return "?" }
        return String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }

    private var storiesRow: some View {
        StoriesRowView(
            myName: authStore.profile?.fullName ?? "",
            myAvatar: authStore.profile?.avatarUrl,
            hasMyStories: !myStories.isEmpty,
            groups: storyGroups,
            onOpenMine: {
                guard let me = authStore.userId, let name = authStore.profile?.fullName else { return }
                let mine = StoryGroup(authorId: me, authorName: name, authorAvatar: authStore.profile?.avatarUrl, stories: myStories)
                storyViewer = StoryViewerItem(groups: [mine], startIndex: 0)
            },
            onAdd: {
                if authStore.isSignedIn { showStoryCompose = true } else { onOpenProfile() }
            },
            onOpen: { group in
                guard let index = storyGroups.firstIndex(of: group) else { return }
                storyViewer = StoryViewerItem(groups: storyGroups, startIndex: index)
            }
        )
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            FilterChip(label: "Para ti", isSelected: mode == .forYou) { mode = .forYou }
            FilterChip(label: "Siguiendo", isSelected: mode == .following) { mode = .following }
            Spacer()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if mode == .following {
            EmptyStateView(
                title: authStore.isSignedIn ? "Aún no sigues a nadie" : "Inicia sesión",
                message: authStore.isSignedIn
                    ? "Toca el nombre de alguien en el feed y sigue a quien quieras ver aquí."
                    : "Inicia sesión para seguir a otras personas.",
                systemImage: "person.2"
            )
            .padding(.top, 20)
        } else {
            EmptyStateView(
                title: "Todavía no hay publicaciones",
                message: "Publica algo o crea una actividad para empezar.",
                systemImage: "text.bubble"
            )
            .padding(.top, 20)
        }
    }

    // MARK: - Carga

    /// Quiénes entran al feed según el modo: `nil` = todos; en "Siguiendo",
    /// las personas que sigo y yo.
    private var authorFilter: [UUID]? {
        guard mode == .following else { return nil }
        var ids = Array(followingIds)
        if let me = authStore.userId { ids.append(me) }
        return ids
    }

    private func reload() async {
        errorMessage = nil
        isLoading = posts.isEmpty
        defer { isLoading = false }
        do {
            if let userId = authStore.userId {
                followingIds = Set((try? await FollowService.followingIds(userId: userId)) ?? [])
            } else {
                followingIds = []
            }
            let first = try await PostService.feed(authorIds: authorFilter)
            posts = first
            reachedEnd = first.count < PostService.pageSize
            await hydrate(for: first)
            if let userId = authStore.userId {
                joinedIds = (try? await activeActivityIds(userId: userId)) ?? []
            } else {
                joinedIds = []
            }
        } catch {
            errorMessage = "No se pudo cargar el feed."
        }
        await loadStories()
        await loadUnread()
    }

    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd, let last = posts.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let next = try? await PostService.feed(before: last.createdAt, authorIds: authorFilter) else { return }
        reachedEnd = next.count < PostService.pageSize
        let known = Set(posts.map(\.id))
        let fresh = next.filter { !known.contains($0.id) }
        posts.append(contentsOf: fresh)
        await hydrate(for: fresh)
    }

    private func loadStories() async {
        let all = (try? await StoryService.active()) ?? []
        let me = authStore.userId
        myStories = all.filter { $0.authorId == me }
        storyGroups = StoryService.groups(from: all.filter { $0.authorId != me })
    }

    private func loadUnread() async {
        unreadCount = authStore.isSignedIn ? await NotificationService.unreadCount() : 0
    }

    /// Trae de una sola consulta las actividades adjuntas a estos posts.
    private func hydrate(for batch: [Post]) async {
        let ids = Array(Set(batch.compactMap(\.activityId))).filter { activities[$0] == nil }
        guard let loaded = try? await ActivityService.byIds(ids) else { return }
        for activity in loaded { activities[activity.id] = activity }
    }

    private func activeActivityIds(userId: UUID) async throws -> Set<UUID> {
        let rows: [ActivityIdRow] = try await SupabaseManager.client
            .from("participations")
            .select("activity_id")
            .eq("user_id", value: userId)
            .eq("status", value: ParticipationStatus.activa.rawValue)
            .execute()
            .value
        return Set(rows.map(\.activityId))
    }

    // MARK: - Acciones

    private func join(_ activity: Activity) {
        guard let userId = authStore.userId, joiningId == nil else { return }
        actionError = nil
        joiningId = activity.id
        Task {
            defer { joiningId = nil }
            do {
                try await ParticipationService.join(activityId: activity.id, userId: userId)
                joinedIds.insert(activity.id)
                if let fresh = try? await ActivityService.detail(id: activity.id) { activities[activity.id] = fresh }
            } catch {
                actionError = "No te pudiste unir: la actividad está llena o ya no está disponible."
                if let fresh = try? await ActivityService.detail(id: activity.id) { activities[activity.id] = fresh }
            }
        }
    }

    private func delete(_ post: Post) {
        Task {
            do {
                try await PostService.delete(post)
                posts.removeAll { $0.id == post.id }
            } catch {
                actionError = "No se pudo eliminar la publicación."
            }
        }
    }

    private func hide(_ post: Post) {
        Task {
            do {
                try await PostService.setHidden(postId: post.id, hidden: true)
                posts.removeAll { $0.id == post.id }
            } catch {
                actionError = "No se pudo ocultar la publicación."
            }
        }
    }
}
