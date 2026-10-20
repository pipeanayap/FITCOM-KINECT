import SwiftUI

/// Navegación principal de la app (TECH-04). Explorar y Mis actividades
/// y Crear son siempre visibles (cada una gestiona su propio requisito de
/// sesión); la pestaña Perfil se vuelve el inicio de sesión cuando no hay
/// sesión, y Moderación sólo aparece para administradores (US-15).
struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        if authStore.isLoading {
            LoadingStateView()
        } else {
            TabView {
                ActivityListView()
                    .tabItem { Label("Explorar", systemImage: "magnifyingglass") }

                MyActivitiesView()
                    .tabItem { Label("Mis actividades", systemImage: "calendar") }

                CreateActivityView()
                    .tabItem { Label("Crear", systemImage: "plus.circle") }

                Group {
                    if authStore.isSignedIn {
                        ProfileView()
                    } else {
                        AuthView()
                    }
                }
                .tabItem { Label("Perfil", systemImage: "person.circle") }

                if authStore.isAdmin {
                    ModerationView()
                        .tabItem { Label("Moderación", systemImage: "shield") }
                }
            }
        }
    }
}
