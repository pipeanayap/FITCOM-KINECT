import SwiftUI

/// Editar el perfil propio (US-02, SCRUM-51): foto desde la galería, nombre,
/// @usuario, bio, zona e intereses por selección. Cerrar sesión y Moderación
/// viven en ``SettingsView``.
struct ProfileView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var zone = ""
    @State private var interests: Set<String> = []
    @State private var avatarUrl = ""
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var didLoadFromProfile = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 92, height: 92)
                            if let url = URL(string: avatarUrl), !avatarUrl.isEmpty {
                                CachedAsyncImage(url: url) { avatarInitials }
                                    .frame(width: 92, height: 92)
                                    .clipShape(Circle())
                            } else {
                                avatarInitials
                            }
                            if isUploading { ProgressView().tint(.brandAccent) }
                        }
                        Button("Cambiar foto") { showPicker = true }
                            .font(.subheadline.weight(.semibold))
                            .disabled(isUploading)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Datos básicos") {
                    TextField("Nombre", text: $fullName)
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("usuario", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Bio (cuéntale algo a la comunidad)", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                    Text("\(bio.count)/160")
                        .font(.caption)
                        .foregroundStyle(bio.count > 160 ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    TextField("Zona de referencia", text: $zone)
                }

                Section("Intereses") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(SportVisuals.canonicalSports, id: \.self) { sport in
                            FilterChip(label: sport, isSelected: interests.contains(sport)) {
                                if interests.contains(sport) { interests.remove(sport) } else { interests.insert(sport) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

            }
            .scrollContentBackground(.hidden)
            .background(Color.screenBackground)
            .navigationTitle("Editar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                // Guardar siempre a la vista, arriba a la derecha (no hasta abajo del formulario).
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Guardar") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear(perform: loadFromProfileIfNeeded)
            // Tras iniciar sesión el perfil llega un instante después de abrir la hoja.
            .onChange(of: authStore.profile) { _, _ in loadFromProfileIfNeeded() }
            .sheet(isPresented: $showPicker) {
                PhotoPickerView(limit: 1) { picked in
                    showPicker = false
                    if let image = picked.first { Task { await upload(image) } }
                }
                .ignoresSafeArea()
            }
        }
        .tint(.brandAccent)
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

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty && bio.count <= 160 && !isSaving && !isUploading
    }

    private func loadFromProfileIfNeeded() {
        guard !didLoadFromProfile, let profile = authStore.profile else { return }
        didLoadFromProfile = true
        fullName = profile.fullName
        username = profile.username ?? ""
        bio = profile.bio ?? ""
        zone = profile.zone ?? ""
        interests = Set(profile.sportsInterests)
        avatarUrl = profile.avatarUrl ?? ""
    }

    /// Sube la foto elegida (reducida) y la deja puesta; se guarda con el resto.
    private func upload(_ image: UIImage) async {
        guard let userId = authStore.userId, let data = ImageUploadService.prepare(image, maxSide: 600) else { return }
        errorMessage = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let path = try await ImageUploadService.upload(data, userId: userId)
            if let url = ImageUploadService.publicURL(for: path) { avatarUrl = url.absoluteString }
        } catch {
            errorMessage = "No se pudo subir la foto. Intenta de nuevo."
        }
    }

    private func save() async {
        guard let userId = authStore.userId else { return }
        let handle = normalizedUsername
        if !handle.isEmpty, handle.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) == nil {
            errorMessage = "El usuario debe tener de 3 a 20 caracteres: letras minúsculas, números o guion bajo."
            return
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedZone = zone.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await ProfileService.update(
                id: userId,
                with: ProfileUpdate(
                    fullName: fullName.trimmingCharacters(in: .whitespaces),
                    username: handle.isEmpty ? nil : handle,
                    bio: trimmedBio.isEmpty ? nil : trimmedBio,
                    zone: trimmedZone.isEmpty ? nil : trimmedZone,
                    sportsInterests: interests.sorted(),
                    avatarUrl: avatarUrl.isEmpty ? nil : avatarUrl
                )
            )
            await authStore.refreshProfile()
            dismiss()
        } catch {
            let text = String(describing: error)
            errorMessage = text.contains("profiles_username_key") || text.contains("duplicate")
                ? "Ese usuario ya está en uso. Prueba con otro."
                : "No se pudieron guardar los cambios. Intenta de nuevo."
        }
    }
}
