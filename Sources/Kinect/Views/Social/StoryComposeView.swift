@preconcurrency import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Historias de 24 horas: foto o video menor de 50 s, de galería o cámara.
struct StoryComposeView: View {
    let onPosted: () -> Void

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var media: StoryMedia?
    @State private var caption = ""
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var captureVideo = false
    @State private var isPreparing = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    private var isBusy: Bool { isPosting || isPreparing }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let media {
                    switch media {
                    case .image(let image): Image(uiImage: image).resizable().scaledToFit()
                    case .video(let url): StoryVideoView(url: url, isPlaying: !showCamera && !showPicker && !isBusy).id(url)
                    }
                } else {
                    VStack(spacing: 16) {
                        sourceOptions
                        Text("Videos de menos de 50 segundos")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                }

                VStack(spacing: 10) {
                    Spacer()
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    if media != nil {
                        TextField("Agrega un texto…", text: $caption)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .glassSurface(Capsule())
                            .environment(\.colorScheme, .dark)
                            .disabled(isBusy)
                            .onChange(of: caption) { _, new in if new.count > 200 { caption = String(new.prefix(200)) } }
                        Menu("Cambiar foto o video") { sourceButtons }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .disabled(isBusy)
                    }
                }
                .padding()
                if isPreparing { ProgressView("Preparando…").tint(.white).foregroundStyle(.white) }
            }
            .navigationTitle("Nueva historia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cleanupMedia(); dismiss() }.disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting { ProgressView() }
                    else { Button("Compartir") { Task { await post() } }.disabled(media == nil || isBusy) }
                }
            }
            .sheet(isPresented: $showPicker) {
                StoryMediaPickerView { result in
                    showPicker = false
                    Task { await select(result) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                StoryCameraView(video: captureVideo) { result in
                    showCamera = false
                    Task { await select(result) }
                }
                .ignoresSafeArea()
            }
        }
        .tint(.brandAccent)
        .interactiveDismissDisabled(isBusy)
        .onDisappear { if !showCamera && !showPicker && !isBusy { cleanupMedia() } }
    }

    private var sourceOptions: some View {
        VStack(spacing: 14) {
            sourceButtons
        }
        .font(.headline)
        .foregroundStyle(.white)
        .buttonStyle(.bordered)
        .tint(.white)
        .disabled(isBusy)
    }

    @ViewBuilder
    private var sourceButtons: some View {
        Button { showPicker = true } label: { Label("Elegir de galería", systemImage: "photo.on.rectangle") }
        Button { Task { await openCamera(video: false) } } label: { Label("Tomar foto", systemImage: "camera") }
        Button { Task { await openCamera(video: true) } } label: { Label("Grabar video", systemImage: "video") }
    }

    @MainActor
    private func openCamera(video: Bool) async {
        guard !isBusy else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "La cámara no está disponible en este dispositivo."
            return
        }
        let mediaType = video ? UTType.movie.identifier : UTType.image.identifier
        guard UIImagePickerController.availableMediaTypes(for: .camera)?.contains(mediaType) == true else {
            errorMessage = "Este dispositivo no permite ese tipo de captura. Puedes elegir un archivo de la galería."
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            errorMessage = "Permite el acceso a la cámara en Ajustes para capturar una historia."
            return
        }
        if video, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            errorMessage = "Permite el acceso al micrófono en Ajustes para grabar un video con audio."
            return
        }
        captureVideo = video
        errorMessage = nil
        showCamera = true
    }

    @MainActor
    private func select(_ result: Result<StoryMedia?, Error>) async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            guard let selected = try result.get() else { return }
            if case .video(let url) = selected {
                do { _ = try await StoryMediaService.validateVideo(url) }
                catch { try? FileManager.default.removeItem(at: url); throw error }
            }
            cleanupMedia()
            media = selected
            errorMessage = nil
        } catch {
            errorMessage = (error as? StoryMediaError)?.localizedDescription ?? "No se pudo cargar el archivo. Intenta de nuevo."
        }
    }

    private func cleanupMedia() {
        if case .video(let url) = media { try? FileManager.default.removeItem(at: url) }
    }

    @MainActor
    private func post() async {
        guard !isBusy, let userId = authStore.userId, let media else { return }
        errorMessage = nil
        isPosting = true
        defer { isPosting = false }
        var path: String?
        var videoUpload = false
        var preparedURL: URL?
        defer { if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) } }
        do {
            let uploaded: String
            var duration: Double?
            switch media {
            case .image(let image):
                guard let data = ImageUploadService.prepare(image, maxSide: 1440) else { throw StoryMediaError.preparationFailed }
                uploaded = try await ImageUploadService.upload(data, userId: userId)
            case .video(let url):
                let prepared = try await StoryMediaService.prepareVideo(url)
                preparedURL = prepared.url
                duration = prepared.duration
                videoUpload = true
                uploaded = try await StoryMediaService.uploadVideo(prepared.url, userId: userId)
            }
            path = uploaded
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            try await StoryService.create(NewStory(
                authorId: userId, imagePath: uploaded, caption: trimmed.isEmpty ? nil : trimmed,
                mediaType: videoUpload ? "video" : "image", videoDuration: duration
            ))
            cleanupMedia()
            onPosted()
            dismiss()
        } catch {
            if let path {
                if videoUpload { await StoryMediaService.deleteVideo(path: path) }
                else { await ImageUploadService.delete(paths: [path]) }
            }
            errorMessage = (error as? StoryMediaError)?.localizedDescription ?? "No se pudo publicar. Intenta de nuevo."
        }
    }
}
