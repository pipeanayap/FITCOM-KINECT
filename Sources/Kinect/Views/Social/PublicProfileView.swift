import SwiftUI

private enum ProfileTab: String, CaseIterable {
    case posts = "Publicaciones"
    case plans = "Planes"
    case groups = "Grupos"
}

/// Perfil de una persona (SCRUM-47, 51, 52, 53): @usuario, foto, conteos, bio,
/// intereses, Seguir / Editar perfil, Compartir, la guía "Completa tu perfil"
/// (sólo en el propio) y las pestañas Publicaciones, Planes y Grupos.
struct PublicProfileView: View {
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var stats: ProfileStats?
    @State private var posts: [Post] = []
    @State private var plans: [MyParticipation] = []
    @State private var groups: [CommunityGroup] = []
    @State private var tab: ProfileTab = .posts
    @State private var isLoading = true
    /// La guía "Completa tu perfil" depende de los grupos, que llegan después del
    /// perfil; hasta entonces no se decide si mostrarla (si no, aparecía un instante
    /// y se quitaba).
    @State private var checklistReady = false
    @State private var isBusy = false
    @State private var isUploadingAvatar = false
    @State private var errorMessage: String?
    @State private var showEdit = false
    @State private var showSettings = false
    @State private var showAvatarPicker = false
    @State private var showCompose = false

    private var isMe: Bool { authStore.userId == userId }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 16) {
                    topBar

                    if let stats {
                        header(stats)
                        identity(stats)
                        buttons(stats)
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                        if isMe && checklistReady && completedSteps(stats) < 4 { completeCard(stats) }
                        tabPicker
                        tabContent
                    } else if isLoading {
                        ProgressView().tint(.brandAccent).padding(.top, 60)
                    } else {
                        EmptyStateView(title: "No se encontró el perfil", message: "Puede que ya no exista.", systemImage: "person.slash")
                    }
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if isMe, stats != nil { composeButton }
        }
        .background(Color.screenBackground)
        .statusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: tab) { _, _ in Task { await loadTab() } }
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
        }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await load() } }) { ProfileView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCompose) { ComposePostView { Task { await load() } } }
        .sheet(isPresented: $showAvatarPicker) {
            PhotoPickerView(limit: 1) { picked in
                showAvatarPicker = false
                if let image = picked.first { Task { await uploadAvatar(image) } }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Barra superior

    private var topBar: some View {
        ZStack {
            Text(stats?.username.map { "@\($0)" } ?? "")
                .font(.headline)
                .foregroundStyle(Color.brandText)
            HStack(spacing: 8) {
                circleButton("chevron.left") {
                    tabBar.isHidden = false
                    dismiss()
                }
                Spacer()
                if let stats {
                    ShareLink(item: shareText(stats)) { circleIcon("square.and.arrow.up") }
                }
                if isMe {
                    Menu {
                        Button { showSettings = true } label: { Label("Configuración y cuenta", systemImage: "gearshape") }
                    } label: { circleIcon("ellipsis") }
                }
            }
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleIcon(symbol) }.buttonStyle(.plain)
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.brandText)
            .frame(width: 38, height: 38)
            .background(Color.cardBackground, in: Circle())
    }

    private func shareText(_ stats: ProfileStats) -> String {
        "Mira el perfil de @\(stats.username ?? stats.fullName) en FITCOM"
    }

    // MARK: - Encabezado

    private func header(_ stats: ProfileStats) -> some View {
        HStack(spacing: 18) {
            avatar(stats)
            HStack(spacing: 0) {
                statColumn(stats.plansCount ?? 0, "Planes")
                statColumn(stats.followersCount, "Seguidores")
                statColumn(stats.followingCount, "Siguiendo")
            }
        }
    }

    private func avatar(_ stats: ProfileStats) -> some View {
        ZStack {
            Circle().strokeBorder(
                LinearGradient(colors: [Color.brandAccent, Color.brandWarning], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 3
            )
            Circle().fill(Color.brandAccent.opacity(0.15)).padding(5)
            if let urlString = stats.avatarUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { initials(stats) }.clipShape(Circle()).padding(5)
            } else {
                initials(stats)
            }
            if isUploadingAvatar {
                Circle().fill(.black.opacity(0.35)).padding(5)
                ProgressView().tint(.white)
            }
        }
        .frame(width: 92, height: 92)
        .overlay(alignment: .bottomTrailing) {
            if isMe {
                Button { showAvatarPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.brandAccent, in: Circle())
                        .overlay(Circle().stroke(Color.screenBackground, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAvatar)
                .accessibilityLabel("Cambiar foto de perfil")
            }
        }
    }

    private func initials(_ stats: ProfileStats) -> some View {
        Text(String(stats.fullName.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
            .font(.title.bold())
            .foregroundStyle(Color.brandAccent)
    }

    private func statColumn(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold()).foregroundStyle(Color.brandText)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Nombre, bio e intereses

    private func identity(_ stats: ProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stats.fullName).font(.title2.bold()).foregroundStyle(Color.brandText)

            if let bio = stats.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).foregroundStyle(Color.brandText)
            } else if isMe {
                Button { showEdit = true } label: {
                    Text("Añade una bio para que tu comunidad te conozca.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if let zone = stats.zone, !zone.isEmpty {
                Label(zone, systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(.secondary)
            }

            if !stats.sportsInterests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stats.sportsInterests, id: \.self) { sport in
                            Label(sport.capitalized, systemImage: SportVisuals.symbol(for: sport))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.cardBackground, in: Capsule())
                                .foregroundStyle(Color.brandText)
                        }
                    }
                }
            } else if isMe {
                Button { showEdit = true } label: {
                    Text("+ Intereses")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.brandAccent.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.brandAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Botones

    private func buttons(_ stats: ProfileStats) -> some View {
        HStack(spacing: 10) {
            if isMe {
                Button("Editar perfil") { showEdit = true }
                    .buttonStyle(.fitcomPrimary(disabled: false))
            } else if authStore.isSignedIn {
                if stats.followedByMe {
                    Button("Siguiendo") { Task { await toggleFollow() } }
                        .buttonStyle(.fitcomSecondary(tint: .brandAccent))
                        .disabled(isBusy)
                } else {
                    Button("Seguir") { Task { await toggleFollow() } }
                        .buttonStyle(.fitcomPrimary(disabled: isBusy))
                        .disabled(isBusy)
                }
            }
            ShareLink(item: shareText(stats)) {
                Text("Compartir perfil")
                    .font(.headline)
                    .foregroundStyle(Color.brandText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cardBackground, in: Capsule())
            }
        }
    }

    // MARK: - Completa tu perfil

    private struct Step: Identifiable {
        let title: String
        let done: Bool
        let action: () -> Void
        var id: String { title }
    }

    private func steps(_ stats: ProfileStats) -> [Step] {
        [
            Step(title: "Foto de perfil", done: !(stats.avatarUrl ?? "").isEmpty, action: { showAvatarPicker = true }),
            Step(title: "Escribe tu bio", done: !(stats.bio ?? "").isEmpty, action: { showEdit = true }),
            Step(title: "Elige tus intereses", done: !stats.sportsInterests.isEmpty, action: { showEdit = true }),
            Step(title: "Únete a tu primer grupo", done: !groups.isEmpty, action: goToGroups),
        ]
    }

    private func completedSteps(_ stats: ProfileStats) -> Int { steps(stats).filter(\.done).count }

    private func completeCard(_ stats: ProfileStats) -> some View {
        let all = steps(stats)
        let done = all.filter(\.done).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Completa tu perfil").font(.headline).foregroundStyle(Color.brandText)
                Spacer()
                Text("\(done) de \(all.count)").font(.subheadline.weight(.bold)).foregroundStyle(Color.brandAccent)
            }
            ProgressView(value: Double(done), total: Double(all.count)).tint(.brandAccent)
            VStack(spacing: 0) {
                ForEach(all) { step in
                    Button { if !step.done { step.action() } } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().strokeBorder(step.done ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1.5)
                                    .background(Circle().fill(step.done ? Color.brandAccent : Color.clear))
                                if step.done {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .frame(width: 26, height: 26)
                            Text(step.title)
                                .font(.subheadline)
                                .strikethrough(step.done)
                                .foregroundStyle(step.done ? Color.secondary : Color.brandText)
                            Spacer()
                            if !step.done {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private func goToGroups() {
        tabBar.requestedTab = .groups
        tabBar.isHidden = false
        dismiss()
    }

    // MARK: - Pestañas

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tab == item ? Color.brandText : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tab == item ? Color.cardBackground : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .posts: postsGrid
        case .plans: plansList
        case .groups: groupsList
        }
    }

    @ViewBuilder
    private var postsGrid: some View {
        if posts.isEmpty {
            emptyText(isMe ? "Todavía no has publicado nada." : "Todavía no ha publicado nada.")
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(posts) { post in
                    NavigationLink(value: post) { tile(post) }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var plansList: some View {
        if plans.isEmpty {
            emptyText(isMe ? "Aún no estás en ningún plan." : "Todavía no está en ningún plan.")
        } else {
            VStack(spacing: 12) {
                ForEach(plans.sorted { $0.activity.scheduledAt > $1.activity.scheduledAt }) { entry in
                    NavigationLink(value: entry.activity.id) { ActivityRowView(activity: entry.activity) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var groupsList: some View {
        if groups.isEmpty {
            emptyText(isMe ? "Aún no perteneces a ningún grupo." : "Todavía no pertenece a ningún grupo.")
        } else {
            VStack(spacing: 12) {
                ForEach(groups) { group in
                    NavigationLink(value: group) { GroupRowView(group: group) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.top, 16)
    }

    private func tile(_ post: Post) -> some View {
        Color.cardBackground
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let path = post.imagePaths.first {
                    CachedAsyncImage(url: ImageUploadService.publicURL(for: path)) {
                        ProgressView().tint(.brandAccent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                } else {
                    Text(post.body ?? "")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.brandText)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            LinearGradient(
                                colors: [Color.brandAccent.opacity(0.16), Color.brandPrimary.opacity(0.10)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay(alignment: .topTrailing) {
                if post.imagePaths.count > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Botón flotante para publicar (sólo en el propio perfil).
    private var composeButton: some View {
        Button { showCompose = true } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .glassSurface(Circle(), tint: Color.brandAccent.opacity(0.85), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
        .accessibilityLabel("Nueva publicación")
    }

    // MARK: - Datos

    private func load() async {
        isLoading = stats == nil
        defer { isLoading = false }
        stats = try? await FollowService.stats(userId: userId)
        posts = (try? await PostService.byAuthor(userId)) ?? []
        // Los grupos se usan en la guía "Completa tu perfil", así que se cargan siempre.
        groups = (try? await GroupService.myGroups(userId: userId)) ?? []
        checklistReady = true
        if tab == .plans { await loadPlans() }
    }

    private func loadTab() async {
        if tab == .plans { await loadPlans() }
    }

    private func loadPlans() async {
        plans = (try? await ParticipationService.joined(userId: userId)) ?? []
    }

    private func uploadAvatar(_ image: UIImage) async {
        guard let me = authStore.userId, let data = ImageUploadService.prepare(image, maxSide: 600) else { return }
        errorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let path = try await ImageUploadService.upload(data, userId: me)
            guard let url = ImageUploadService.publicURL(for: path) else { return }
            try await ProfileService.setAvatar(id: me, url: url.absoluteString)
            await authStore.refreshProfile()
            await load()
        } catch {
            errorMessage = "No se pudo subir la foto. Intenta de nuevo."
        }
    }

    /// Respuesta inmediata en el botón y en el conteo; si falla se revierte.
    private func toggleFollow() async {
        guard let me = authStore.userId, var current = stats, !isBusy else { return }
        let original = current
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        current.followedByMe.toggle()
        current.followersCount += current.followedByMe ? 1 : -1
        stats = current
        do {
            if current.followedByMe {
                try await FollowService.follow(followerId: me, followeeId: userId)
            } else {
                try await FollowService.unfollow(followerId: me, followeeId: userId)
            }
        } catch {
            stats = original
            errorMessage = "No se pudo actualizar. Intenta de nuevo."
        }
    }
}
