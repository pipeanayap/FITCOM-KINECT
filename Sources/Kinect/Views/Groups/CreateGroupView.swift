import SwiftUI

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
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Crear") { Task { await save() } }.disabled(!canSave)
                    }
                }
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
            let created = try await GroupService.create(
                NewCommunityGroup(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.isEmpty ? nil : description,
                    sport: sport.isEmpty ? nil : sport,
                    zone: zone.isEmpty ? nil : zone,
                    createdBy: userId
                )
            )
            onCreated(created)
            dismiss()
        } catch {
            errorMessage = "No se pudo crear el grupo. Intenta de nuevo."
        }
    }
}
