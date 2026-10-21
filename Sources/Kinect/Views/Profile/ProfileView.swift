import SwiftUI

/// Perfil básico: nombre, zona e intereses deportivos (US-02). Desde aquí
/// los administradores entran al panel de moderación (US-15).
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
                Section {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 88, height: 88)
                            if let url = URL(string: avatarUrl), !avatarUrl.isEmpty {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    avatarInitials
                                }
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                            } else {
                                avatarInitials
                            }
                        }
                        Text(fullName.isEmpty ? "Tu perfil" : fullName).font(.title3.bold())
                        if let zone = authStore.profile?.zone, !zone.isEmpty {
                            Label(zone, systemImage: "mappin.and.ellipse")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                if authStore.isAdmin {
                    Section {
                        NavigationLink {
                            ModerationView()
                        } label: {
                            Label("Panel de moderación", systemImage: "shield.fill")
                                .foregroundStyle(Color.brandAccent)
                        }
                    }
                }

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
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Guardar cambios")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.fitcomPrimary(disabled: fullName.isEmpty || isSaving))
                    .disabled(fullName.isEmpty || isSaving)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Button("Cerrar sesión", role: .destructive) {
                        Task { try? await authStore.signOut() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle("Mi perfil")
            .onAppear(perform: loadFromProfileIfNeeded)
        }
    }

    private var avatarInitials: some View {
        Text(initials)
            .font(.title.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }

    private var initials: String {
        let parts = fullName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
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
