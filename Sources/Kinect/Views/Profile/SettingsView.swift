import SwiftUI

/// Configuración y cuenta: lo que antes estaba mezclado dentro de "Editar
/// perfil". Desde aquí se edita el perfil, los administradores entran a
/// Moderación (US-15) y se cierra sesión.
struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.brandAccent.opacity(0.15))
                            if let urlString = authStore.profile?.avatarUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                                CachedAsyncImage(url: url) { initials }.clipShape(Circle())
                            } else {
                                initials
                            }
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authStore.profile?.fullName ?? "").font(.headline)
                            if let email = authStore.session?.user.email {
                                Text(email).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Cuenta") {
                    Button { showEdit = true } label: {
                        Label("Editar perfil", systemImage: "person.crop.circle")
                    }
                }

                if authStore.isAdmin {
                    Section("Administración") {
                        NavigationLink {
                            ModerationView()
                        } label: {
                            Label("Panel de moderación", systemImage: "shield.fill")
                                .foregroundStyle(Color.brandAccent)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { showSignOutConfirmation = true } label: {
                        Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .sheet(isPresented: $showEdit) { ProfileView() }
            .confirmationDialog("¿Cerrar sesión?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                // RootView cierra todo lo abierto y vuelve a Inicio al detectar que ya no hay sesión.
                Button("Cerrar sesión", role: .destructive) { Task { try? await authStore.signOut() } }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .tint(.brandAccent)
    }

    private var initials: some View {
        Text(String((authStore.profile?.fullName ?? "?").split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }
}
