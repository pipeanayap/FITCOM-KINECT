import SwiftUI

/// Navegación principal de la app (TECH-04). Explorar, Mis planes y Crear
/// son siempre visibles (cada una gestiona su propio requisito de sesión);
/// Perfil ya no es una pestaña — se abre como hoja desde el ícono de la
/// esquina superior derecha en Explorar, y ahí adentro, si hay sesión y es
/// admin, se entra a Moderación (US-15). Sin sesión, ese mismo ícono abre
/// el inicio de sesión.
struct RootView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var selectedTab: FitcomTab = .explore
    @State private var showProfile = false

    var body: some View {
        if authStore.isLoading {
            LoadingStateView()
        } else {
            ZStack(alignment: .bottom) {
                ZStack {
                    screen(.explore) { ActivityListView(onOpenProfile: { showProfile = true }) }
                    screen(.mine) { MyActivitiesView() }
                    screen(.create) { CreateActivityView() }
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }

                FitcomTabBar(selected: $selectedTab)
                    .padding(.bottom, 2)
            }
            .tint(.brandAccent)
            .sheet(isPresented: $showProfile) {
                profileOrAuth
            }
        }
    }

    /// Mantiene las cuatro pantallas montadas a la vez (igual que haría un
    /// TabView nativo) para que cada una conserve su propio estado y su
    /// propia pila de navegación al cambiar de pestaña.
    @ViewBuilder
    private func screen(_ tab: FitcomTab, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }

    @ViewBuilder
    private var profileOrAuth: some View {
        if authStore.isSignedIn {
            ProfileView()
        } else {
            AuthView()
        }
    }
}
