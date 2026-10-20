import SwiftUI

/// Perfil básico: nombre, zona e intereses deportivos (US-02).
struct ProfileView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var fullName = ""
    @State private var zone = ""
    @State private var sportsInterestsText = ""
    @State private var avatarUrl = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoadFromProfile = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos básicos") {
                    TextField("Nombre", text: $fullName)
                    TextField("Zona de referencia", text: $zone)
                    TextField("Deportes de interés (separados por coma)", text: $sportsInterestsText)
                    TextField("URL de foto de perfil (opcional)", text: $avatarUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Guardar cambios")
                        }
                    }
                    .disabled(fullName.isEmpty || isSaving)
                }

                Section {
                    Button("Cerrar sesión", role: .destructive) {
                        Task { try? await authStore.signOut() }
                    }
                }
            }
            .navigationTitle("Mi perfil")
            .onAppear(perform: loadFromProfileIfNeeded)
        }
    }

    private func loadFromProfileIfNeeded() {
        guard !didLoadFromProfile, let profile = authStore.profile else { return }
        didLoadFromProfile = true
        fullName = profile.fullName
        zone = profile.zone ?? ""
        sportsInterestsText = profile.sportsInterests.joined(separator: ", ")
        avatarUrl = profile.avatarUrl ?? ""
    }

    private func save() async {
        guard let userId = authStore.userId else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let interests = sportsInterestsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        do {
            _ = try await ProfileService.update(
                id: userId,
                with: ProfileUpdate(
                    fullName: fullName,
                    zone: zone.isEmpty ? nil : zone,
                    sportsInterests: interests,
                    avatarUrl: avatarUrl.isEmpty ? nil : avatarUrl
                )
            )
            await authStore.refreshProfile()
        } catch {
            errorMessage = "No se pudo guardar el perfil. Intenta de nuevo."
        }
    }
}
