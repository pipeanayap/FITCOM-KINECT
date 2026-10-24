import SwiftUI

/// Publicar en el feed (SCRUM-43): texto, hasta 4 fotos y, opcionalmente, una
/// actividad propia adjunta (SCRUM-45) y un grupo.
struct ComposePostView: View {
    let onPosted: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var images: [UIImage] = []
    @State private var showPicker = false
    @State private var myActivities: [Activity] = []
    @State private var myGroups: [CommunityGroup] = []
    @State private var activityId: UUID?
    @State private var groupId: UUID?
    @State private var isPosting = false
    @State private var errorMessage: String?

    private let maxImages = 4

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("¿Qué estás haciendo?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    Text("\(text.count)/1000")
                        .font(.caption)
                        .foregroundStyle(text.count > 1000 ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section("Fotos") {
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 96, height: 96)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Button { images.remove(at: offset) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }
                    Button {
                        showPicker = true
                    } label: {
                        Label(images.isEmpty ? "Agregar fotos" : "Agregar más (\(images.count)/\(maxImages))", systemImage: "photo.badge.plus")
                    }
                    .disabled(images.count >= maxImages)
                }

                if !myActivities.isEmpty || !myGroups.isEmpty {
                    Section("Adjuntar") {
                        if !myActivities.isEmpty {
                            Picker("Actividad", selection: $activityId) {
                                Text("Ninguna").tag(UUID?.none)
                                ForEach(myActivities) { Text($0.title).tag(UUID?.some($0.id)) }
                            }
                        }
                        if !myGroups.isEmpty {
                            Picker("Grupo", selection: $groupId) {
                                Text("Ninguno").tag(UUID?.none)
                                ForEach(myGroups) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Nueva publicación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(isPosting) }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Publicar") { Task { await post() } }.disabled(!canPost)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoPickerView(limit: maxImages - images.count) { picked in
                    images.append(contentsOf: picked)
                    images = Array(images.prefix(maxImages))
                    showPicker = false
                }
                .ignoresSafeArea()
            }
            .task { await loadOptions() }
        }
        .tint(.brandAccent)
        .interactiveDismissDisabled(isPosting)
    }

    private var canPost: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !images.isEmpty || activityId != nil) && text.count <= 1000
    }

    private func loadOptions() async {
        guard let userId = authStore.userId else { return }
        myGroups = (try? await GroupService.myGroups(userId: userId)) ?? []
        let mine = (try? await ActivityService.mine(organizerId: userId)) ?? []
        myActivities = mine.filter { $0.status == .abierta && $0.scheduledAt > Date() }
    }

    private func post() async {
        guard let userId = authStore.userId else { return }
        errorMessage = nil
        isPosting = true
        defer { isPosting = false }
        var uploaded: [String] = []
        do {
            for image in images {
                guard let data = ImageUploadService.prepare(image) else { continue }
                uploaded.append(try await ImageUploadService.upload(data, userId: userId))
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await PostService.create(
                NewPost(
                    authorId: userId,
                    body: trimmed.isEmpty ? nil : trimmed,
                    imagePaths: uploaded,
                    activityId: activityId,
                    groupId: groupId
                )
            )
            onPosted()
            dismiss()
        } catch {
            // Si falló después de subir, no dejamos fotos huérfanas.
            await ImageUploadService.delete(paths: uploaded)
            errorMessage = "No se pudo publicar. Revisa tu conexión e intenta de nuevo."
        }
    }
}
