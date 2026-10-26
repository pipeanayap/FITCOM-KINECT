import SwiftUI

/// Navegación principal de la app (TECH-04). Inicio, Explorar, Grupos y Mis
/// planes son pestañas siempre visibles (cada una gestiona su propio
/// requisito de sesión); "Crear" es el botón central que abre un menú con
/// actividad, publicación, historia o grupo. Perfil no es una pestaña: la
/// burbuja de perfil abre un panel lateral (estilo Twitter) desde el que se
/// entra a tu perfil o a la configuración (donde está Moderación para admins,
/// US-15). Sin sesión, el panel ofrece iniciar sesión.
struct RootView: View {
    private enum CreateSheet: String, Identifiable {
        case activity, post, story, group
        var id: String { rawValue }
    }

    @Environment(AuthStore.self) private var authStore
    @State private var selectedTab: FitcomTab = .home
    @State private var showDrawer = false
    /// Configuración y cuenta (o inicio de sesión si no hay sesión).
    @State private var showSettings = false
    @State private var showAuth = false
    @State private var showMyProfile = false
    @State private var tabBar = TabBarState()
    @State private var tabBarHeight: CGFloat = 80
    @State private var showCreateMenu = false
    @State private var createSheet: CreateSheet?
    /// Sube al crear algo para que el feed y los grupos se recarguen.
    @State private var refreshToken = 0
    @State private var exploreToken = 0
    /// Aparte porque Mis planes también se recarga al abrir su pestaña (por ejemplo
    /// después de unirte a algo desde el feed).
    @State private var plansToken = 0

    var body: some View {
        if authStore.isLoading {
            LoadingStateView()
        } else {
            ZStack(alignment: .leading) {
                SideDrawerView(
                    onProfile: { closeDrawer(then: { showMyProfile = true }) },
                    onSettings: { closeDrawer(then: { showSettings = true }) },
                    onSignIn: { closeDrawer(then: { showAuth = true }) }
                )

                mainContent
                    .overlay {
                        if showDrawer {
                            // Con el panel abierto, tocar el contenido (o arrastrar
                            // hacia la izquierda) lo cierra.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { closeDrawer() }
                                .gesture(DragGesture().onEnded { if $0.translation.width < -50 { closeDrawer() } })
                        }
                    }
                    // Máscara (no clipShape): tiene que cubrir también las zonas seguras
                    // de arriba y abajo, o el panel se asoma como barras blancas.
                    .mask {
                        RoundedRectangle(cornerRadius: showDrawer ? 34 : 0, style: .continuous)
                            .ignoresSafeArea()
                    }
                    .shadow(color: .black.opacity(showDrawer ? 0.25 : 0), radius: 18, x: -4)
                    .offset(x: showDrawer ? SideDrawerView.width : 0)
            }
            .onChange(of: authStore.isSignedIn) { _, signedIn in
                showAuth = false
                if !signedIn {
                    showSettings = false
                    // Se cerró la sesión: nada de lo que dependía de la cuenta puede
                    // quedar abierto (el perfil a pantalla completa se quedaba en
                    // blanco sin usuario y tapaba toda la app).
                    showMyProfile = false
                    createSheet = nil
                    showCreateMenu = false
                    showDrawer = false
                    selectedTab = .home
                }
            }
            .onChange(of: selectedTab) { _, tab in
                tabBar.activeTab = tab
                if tab == .explore && tabBar.exploreAtRoot { tabBar.isHidden = false }
                if tab == .mine { plansToken += 1 }
                if tab == .explore { exploreToken += 1 }
            }
            .onChange(of: tabBar.requestedTab) { _, tab in
                // Otra pantalla (p. ej. el perfil) pidió ir a una pestaña.
                guard let tab else { return }
                selectedTab = tab
                showMyProfile = false
                tabBar.requestedTab = nil
            }
            // Las hojas cuelgan de aquí (fuera de mainContent): también necesitan el estado de la barra.
            .environment(tabBar)
            .tint(.brandAccent)
            .sheet(isPresented: $showAuth) { AuthView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showMyProfile) { myProfile }
            .sheet(item: $createSheet) { sheet in createContent(sheet) }
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                screen(.home) { FeedView(onOpenProfile: openDrawer, refreshToken: refreshToken) }
                screen(.explore) { ActivityListView(onOpenProfile: openDrawer, refreshToken: exploreToken) }
                screen(.groups) { GroupListView(refreshToken: refreshToken) }
                screen(.mine) { MyActivitiesView(refreshToken: plansToken) }
            }
            // El contenido sigue por detrás de la barra (se ve a través del
            // vidrio); este margen sólo deja que el último elemento suba por encima.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserva hasta el borde superior real de la barra, incluido
                // el botón Crear, más 8 puntos de separación para las acciones.
                Color.clear.frame(height: tabBar.isHidden ? 0 : max(0, tabBarHeight - 12 + 8))
            }

            if showCreateMenu {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)
                CreateMenuView { option in
                    closeMenu()
                    open(option)
                }
                .padding(.bottom, 100)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }

            // Más abajo que el borde seguro, pero sin tocar la pantalla
            // (deja libre la línea del indicador de inicio).
            FitcomTabBar(selected: $selectedTab, isCreateOpen: $showCreateMenu)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: TabBarFrameKey.self, value: geometry.frame(in: .global))
                    }
                }
                .offset(y: tabBar.isHidden ? 140 : 12)
                .opacity(tabBar.isHidden ? 0 : 1)
                .allowsHitTesting(!tabBar.isHidden)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .onPreferenceChange(TabBarFrameKey.self) { frame in
            guard frame.height > 0 else { return }
            tabBarHeight = frame.height
            if !tabBar.isHidden { tabBar.topEdge = frame.minY }
        }
        .animation(.easeInOut(duration: 0.25), value: tabBar.isHidden)
        .onChange(of: tabBar.isHidden) { _, hidden in if hidden { showCreateMenu = false } }
        .environment(tabBar)
        .tint(.brandAccent)
    }

    // MARK: - Panel lateral

    private func openDrawer() {
        showCreateMenu = false
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { showDrawer = true }
    }

    /// Cierra el panel y, si hay algo que abrir, lo abre cuando termina la animación.
    private func closeDrawer(then action: (() -> Void)? = nil) {
        withAnimation(.spring(duration: 0.3)) { showDrawer = false }
        guard let action else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            action()
        }
    }

    @ViewBuilder
    private var myProfile: some View {
        if let me = authStore.userId {
            NavigationStack {
                PublicProfileView(userId: me)
                    .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
                    .navigationDestination(for: PostRoute.self) { PostLoaderView(id: $0.id) }
                    .navigationDestination(for: ProfileRoute.self) { PublicProfileView(userId: $0.userId) }
                    .navigationDestination(for: UUID.self) { ActivityDetailView(activityId: $0) }
                    .navigationDestination(for: CommunityGroup.self) { group in GroupDetailView(group: group) {} }
            }
            .environment(tabBar)
            .tint(.brandAccent)
        }
    }

    // MARK: - Crear

    private func closeMenu() {
        withAnimation(.spring(duration: 0.3)) { showCreateMenu = false }
    }

    /// Crear requiere sesión: sin ella se abre el inicio de sesión.
    private func open(_ option: CreateMenuView.Option) {
        guard authStore.isSignedIn else {
            showAuth = true
            return
        }
        switch option {
        case .activity: createSheet = .activity
        case .post: createSheet = .post
        case .story: createSheet = .story
        case .group: createSheet = .group
        }
    }

    @ViewBuilder
    private func createContent(_ sheet: CreateSheet) -> some View {
        switch sheet {
        case .activity:
            if let userId = authStore.userId {
                ActivityFormView(
                    organizerId: userId,
                    saveAction: .create { try await ActivityService.create($0) },
                    onSaved: { _ in
                        exploreToken += 1
                        created(in: .home)
                    }
                )
            }
        case .post:
            ComposePostView { created(in: .home) }
        case .story:
            StoryComposeView { created(in: .home) }
        case .group:
            CreateGroupView { _ in created(in: .groups) }
        }
    }

    private func created(in tab: FitcomTab) {
        selectedTab = tab
        refreshToken += 1
        plansToken += 1
    }

    /// Mantiene las pantallas montadas a la vez (igual que haría un TabView
    /// nativo) para que cada una conserve su propio estado y su propia pila
    /// de navegación al cambiar de pestaña.
    @ViewBuilder
    private func screen(_ tab: FitcomTab, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

private struct TabBarFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let frame = nextValue()
        if frame.height > 0 { value = frame }
    }
}
