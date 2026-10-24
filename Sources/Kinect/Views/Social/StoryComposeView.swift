import SwiftUI

/// Publicar una historia (SCRUM-49): una foto y un texto opcional. Se borra
/// sola a las 24 horas.
struct StoryComposeView: View {
    let onPosted: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var caption = ""
    @State private var showPicker = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Elegir una foto", systemImage: "photo.badge.plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                            .glassSurface(Capsule())
                            .environment(\.colorScheme, .dark)
                    }
                }

                VStack(spacing: 10) {
                    Spacer()
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    if image != nil {
                        TextField("Agrega un texto…", text: $caption)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .glassSurface(Capsule())
                            .environment(\.colorScheme, .dark)
                            .onChange(of: caption) { _, new in if new.count > 200 { caption = String(new.prefix(200)) } }
                        Button("Cambiar foto") { showPicker = true }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
            }
            .navigationTitle("Nueva historia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(isPosting) }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Compartir") { Task { await post() } }.disabled(image == nil)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoPickerView(limit: 1) { picked in
                    if let first = picked.first { image = first }
                    showPicker = false
                }
                .ignoresSafeArea()
            }
            .task {
                // Abre el selector solo, para ir directo a elegir la foto.
                try? await Task.sleep(for: .milliseconds(350))
                if image == nil { showPicker = true }
            }
        }
        .tint(.brandAccent)
        .interactiveDismissDisabled(isPosting)
    }

    private func post() async {
        guard let userId = authStore.userId, let image,
              let data = ImageUploadService.prepare(image, maxSide: 1440) else { return }
        errorMessage = nil
        isPosting = true
        defer { isPosting = false }
        var path: String?
        do {
            let uploaded = try await ImageUploadService.upload(data, userId: userId)
            path = uploaded
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            try await StoryService.create(
                NewStory(authorId: userId, imagePath: uploaded, caption: trimmed.isEmpty ? nil : trimmed)
            )
            onPosted()
            dismiss()
        } catch {
            if let path { await ImageUploadService.delete(paths: [path]) }
            errorMessage = "No se pudo publicar. Intenta de nuevo."
        }
    }
}
