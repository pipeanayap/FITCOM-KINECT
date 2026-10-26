import SwiftUI
import UIKit

/// Formulario para crear un grupo (SCRUM-41). El creador queda como admin
/// del grupo (lo hace un trigger en la base de datos).
struct CreateGroupView: View {
    let onCreated: (CommunityGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var name = ""
    @State private var sport = ""
    @State private var zone = ""
    @State private var description = ""
    @State private var photo: UIImage?
    @State private var showPhotoPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Grupo") {
                    TextField("Nombre (ej. Corredores León)", text: $name)
                    Picker("Deporte", selection: $sport) {
                        Text("Cualquiera").tag("")
                        ForEach(SportVisuals.canonicalSports, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Zona o ciudad", text: $zone)
                }
                Section("Foto del grupo") {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipped()
                    }
                    Button(photo == nil ? "Agregar foto" : "Cambiar foto") { showPhotoPicker = true }
                        .disabled(isSaving)
                }
                Section("Descripción") {
                    TextField("¿De qué trata el grupo?", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Nuevo grupo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Crear") { Task { await save() } }.disabled(!canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(limit: 1) { picked in
                showPhotoPicker = false
                if let image = picked.first { photo = image }
            }
        }
        .tint(.brandAccent)
    }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 3
    }

    private func save() async {
        guard let userId = authStore.userId else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            var photoUrl: String?
            if let photo {
                try await GroupService.checkPhotoSupport()
                guard let data = ImageUploadService.prepare(photo) else {
                    errorMessage = "No se pudo preparar la foto. Elige otra imagen."
                    return
                }
                let path = try await ImageUploadService.upload(data, userId: userId)
                guard let url = ImageUploadService.publicURL(for: path) else {
                    await ImageUploadService.delete(paths: [path])
                    errorMessage = "No se pudo guardar la foto. Intenta de nuevo."
                    return
                }
                photoUrl = url.absoluteString
            }
            let created = try await GroupService.create(
                NewCommunityGroup(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.isEmpty ? nil : description,
                    sport: sport.isEmpty ? nil : sport,
                    zone: zone.isEmpty ? nil : zone,
                    photoUrl: photoUrl,
                    createdBy: userId
                )
            )
            onCreated(created)
            dismiss()
        } catch {
            errorMessage = GroupService.failureMessage(error, fallback: "No se pudo crear el grupo. Intenta de nuevo.")
        }
    }
}
