import SwiftUI

/// Pestaña de grupos / comunidades (SCRUM-41): "Mis grupos" y "Descubrir",
/// con filtro por deporte y botón para crear uno.
struct GroupListView: View {
    @Environment(AuthStore.self) private var authStore

    /// Sube cuando se crea algo desde el menú central para recargar la lista.
    var refreshToken = 0

    @State private var groups: [CommunityGroup] = []
    @State private var myIds: Set<UUID> = []
    @State private var sportFilter: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreate = false
    /// Caras de quienes integran cada grupo (se cargan después de la lista).
    @State private var faces: [UUID: [Attendee]] = [:]
    @State private var path = NavigationPath()
    @Environment(TabBarState.self) private var tabBar

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            SkeletonList(count: 4)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .scrollDisabled(true)
                    .background(Color.screenBackground)
                    .statusBarCover()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage, retry: load)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            if !availableSports.isEmpty { sportChips }

                            if groups.isEmpty {
                                EmptyStateView(
                                    title: "Todavía no hay grupos",
                                    message: "Crea el primero y junta a tu comunidad.",
                                    systemImage: "person.3",
                                    actionTitle: "Crear grupo",
                                    action: { tabBar.requestedCreate = .group }
                                )
                                .padding(.top, 20)
                            } else {
                                if !myGroups.isEmpty {
                                    SectionHeaderView(title: "Mis grupos")
                                    myGroupsCarousel
                                }
                                SectionHeaderView(title: "Descubrir").padding(.top, 4)
                                if discover.isEmpty {
                                    Text("No hay más grupos con ese filtro.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(discover) { row($0) }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .background(Color.screenBackground)
                    .statusBarCover()
                    .refreshable { await load() }
                }
            }
            .background(Color.screenBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CommunityGroup.self) { group in
                GroupDetailView(group: group) { Task { await load() } }
            }
            .navigationDestination(for: UUID.self) { ActivityDetailView(activityId: $0) }
            .navigationDestination(for: ProfileRoute.self) { PublicProfileView(userId: $0.userId) }
            .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
            .navigationDestination(for: PostRoute.self) { PostLoaderView(id: $0.id) }
            .sheet(isPresented: $showCreate) {
                CreateGroupView { created in
                    Task {
                        await load()
                        path.append(created)
                    }
                }
            }
            .task { await load() }
            .onChange(of: authStore.userId) { _, _ in Task { await load() } }
            .onChange(of: refreshToken) { _, _ in Task { await load() } }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grupos").font(.displayXL).foregroundStyle(Color.brandText)
                Text("Encuentra tu comunidad").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if authStore.isSignedIn {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.brandAccent, in: Circle())
                }
                .buttonStyle(.fitcomPressable)
                .accessibilityLabel("Crear grupo")
            }
        }
        .padding(.top, 4)
    }

    private var sportChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Todos", isSelected: sportFilter == nil) { sportFilter = nil }
                ForEach(availableSports, id: \.self) { sport in
                    FilterChip(label: sport, isSelected: sportFilter == sport) {
                        sportFilter = sportFilter == sport ? nil : sport
                    }
                }
            }
        }
    }

    private func row(_ group: CommunityGroup) -> some View {
        NavigationLink(value: group) { GroupRowView(group: group, faces: faces[group.id] ?? []) }
            .buttonStyle(.fitcomPressable)
    }

    /// Tus grupos como tarjetas con portada, para recorrerlos de lado.
    private var myGroupsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(myGroups) { group in
                    NavigationLink(value: group) { GroupCoverCard(group: group, faces: faces[group.id] ?? []) }
                        .buttonStyle(.fitcomPressable)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var myGroups: [CommunityGroup] { groups.filter { myIds.contains($0.id) } }

    private var discover: [CommunityGroup] {
        groups.filter { group in
            guard !myIds.contains(group.id) else { return false }
            guard let sportFilter else { return true }
            return group.sport == sportFilter
        }
    }

    private var availableSports: [String] {
        Array(Set(groups.compactMap(\.sport))).sorted()
    }

    private func load() async {
        errorMessage = nil
        isLoading = groups.isEmpty
        defer { isLoading = false }
        do {
            groups = try await GroupService.list()
            let loaded = groups
            Task { faces = await ActivitySocialService.loadMembers(for: loaded) }
            if let userId = authStore.userId {
                myIds = (try? await GroupService.myGroupIds(userId: userId)) ?? []
            } else {
                myIds = []
            }
        } catch {
            errorMessage = "No se pudieron cargar los grupos."
        }
    }
}

/// Portada de un grupo: foto o degradado del deporte.
private struct GroupCover: View {
    let group: CommunityGroup
    var glyphSize: CGFloat = 40

    var body: some View {
        CachedAsyncImage(url: group.photoUrl.flatMap { URL(string: $0) }) {
            ZStack {
                SportVisuals.gradient(for: group.sport ?? "")
                Image(systemName: group.sport.map(SportVisuals.symbol(for:)) ?? "person.3.fill")
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .id(group.photoUrl)
    }
}

/// Tarjeta de un grupo en la lista: portada, deporte y zona, y las caras de quienes están.
struct GroupRowView: View {
    let group: CommunityGroup
    var faces: [Attendee] = []

    var body: some View {
        HStack(spacing: 14) {
            GroupCover(group: group, glyphSize: 24)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text([group.sport, group.zone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .metaCaps(Color.brandAccentText)
                    .lineLimit(1)
                Text(group.name)
                    .font(.cardTitle)
                    .foregroundStyle(Color.brandText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if !faces.isEmpty {
                        AvatarStack(people: faces, total: group.memberCount, size: 22)
                    }
                    Text(group.memberCount == 1 ? "1 miembro" : "\(group.memberCount) miembros")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

/// Tarjeta vertical con portada, para el carrusel de "Mis grupos".
struct GroupCoverCard: View {
    let group: CommunityGroup
    var faces: [Attendee] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupCover(group: group, glyphSize: 52)
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(group.name)
                .font(.cardTitle)
                .foregroundStyle(Color.brandText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
            HStack(spacing: 6) {
                if !faces.isEmpty {
                    AvatarStack(people: faces, total: group.memberCount, size: 22)
                }
                Spacer(minLength: 0)
                Text(group.memberCount == 1 ? "1 miembro" : "\(group.memberCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandAccentText)
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }
}
