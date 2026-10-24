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
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    LoadingStateView()
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
                                    systemImage: "person.3"
                                )
                                .padding(.top, 20)
                            } else {
                                if !myGroups.isEmpty {
                                    SectionHeaderView(title: "Mis grupos")
                                    ForEach(myGroups) { row($0) }
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
                Text("Grupos").font(.largeTitle.bold()).foregroundStyle(Color.brandText)
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
        NavigationLink(value: group) { GroupRowView(group: group) }
            .buttonStyle(.plain)
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

/// Tarjeta de un grupo en la lista.
struct GroupRowView: View {
    let group: CommunityGroup

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(SportVisuals.gradient(for: group.sport ?? ""))
                Image(systemName: group.sport.map(SportVisuals.symbol(for:)) ?? "person.3.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name).font(.headline).foregroundStyle(Color.brandText).lineLimit(1)
                Text([group.sport, group.zone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label(
                    group.memberCount == 1 ? "1 miembro" : "\(group.memberCount) miembros",
                    systemImage: "person.2.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.brandAccent)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}
