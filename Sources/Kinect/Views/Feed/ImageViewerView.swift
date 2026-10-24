import SwiftUI

/// Visor a pantalla completa de las fotos de un post (SCRUM-43).
///
/// - Cerrar: deslizar hacia arriba o abajo desde cualquier parte (la foto se
///   achica y el fondo se aclara) o con el botón.
/// - Un toque oculta/muestra los controles; doble toque da like.
/// - Abajo, los mismos corazón y comentario del feed, con sus conteos.
struct ImageViewerView: View {
    @State var post: Post
    @State var index: Int
    /// Avisa al feed cuando cambia el like para que la tarjeta no se quede vieja.
    let onChange: (Post) -> Void
    let onOpenComments: (Post) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var dragY: CGFloat = 0
    @State private var chromeVisible = true
    @State private var heartVisible = false

    /// 0 = quieto, 1 = arrastrado lo suficiente como para cerrarse.
    private var progress: Double { min(Double(abs(dragY)) / 260, 1) }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - progress * 0.75).ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(post.imagePaths.enumerated()), id: \.offset) { offset, path in
                    FittedRemoteImage(url: ImageUploadService.publicURL(for: path))
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .scaleEffect(1 - progress * 0.18)
            .offset(y: dragY)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { doubleTapLike() }
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } }

            Image(systemName: "heart.fill")
                .font(.system(size: 110))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 16)
                .scaleEffect(heartVisible ? 1 : 0.4)
                .opacity(heartVisible ? 1 : 0)
                .allowsHitTesting(false)

            if chromeVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomBar
                }
                .opacity(1 - progress * 2)
                .transition(.opacity)
            }
        }
        .simultaneousGesture(dismissDrag)
        .presentationBackground(.clear)
    }

    // MARK: - Controles

    private var topBar: some View {
        ZStack {
            if post.imagePaths.count > 1 {
                Text("\(index + 1) / \(post.imagePaths.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassSurface(Capsule())
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .glassSurface(Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar")
                Spacer()
            }
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let body = post.body, !body.isEmpty {
                Text("\(Text(post.authorName).fontWeight(.bold)) \(body)")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Text(post.authorName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassSurface(Capsule())
            }

            HStack(spacing: 2) {
                Button(action: toggleLike) {
                    HStack(spacing: 7) {
                        Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(post.likedByMe ? Color.red : .white)
                            .symbolEffect(.bounce, value: post.likedByMe)
                        Text("\(post.likeCount)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!authStore.isSignedIn)

                Button {
                    onOpenComments(post)
                    dismiss()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(post.commentCount)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .glassSurface(Capsule())
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Gestos

    /// Deslizar en vertical cierra el visor. Sólo reacciona si el movimiento es
    /// más vertical que horizontal, para no estorbar al pasar de foto.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard dragY != 0 || abs(value.translation.height) > abs(value.translation.width) else { return }
                dragY = value.translation.height
            }
            .onEnded { value in
                guard dragY != 0 else { return }
                if abs(value.translation.height) > 110 || abs(value.predictedEndTranslation.height) > 320 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.28)) { dragY = 0 }
                }
            }
    }

    private func doubleTapLike() {
        guard authStore.isSignedIn else { return }
        if !post.likedByMe { toggleLike() }
        withAnimation(.spring(duration: 0.35)) { heartVisible = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { heartVisible = false }
        }
    }

    /// Respuesta inmediata; si el servidor falla se revierte.
    private func toggleLike() {
        guard let userId = authStore.userId else { return }
        let wasLiked = post.likedByMe
        post.likedByMe = !wasLiked
        post.likeCount += wasLiked ? -1 : 1
        onChange(post)
        let postId = post.id
        Task {
            do {
                if wasLiked {
                    try await PostService.unlike(postId: postId, userId: userId)
                } else {
                    try await PostService.like(postId: postId, userId: userId)
                }
            } catch {
                post.likedByMe = wasLiked
                post.likeCount += wasLiked ? 1 : -1
                onChange(post)
            }
        }
    }
}

/// Misma caché que `CachedAsyncImage`, pero la foto completa sin recortar
/// (visor de fotos e historias).
struct FittedRemoteImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = ImageMemoryCache.shared.object(forKey: url as NSURL) { image = cached; return }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            if let (data, _) = try? await URLSession.shared.data(for: request), let loaded = UIImage(data: data) {
                ImageMemoryCache.shared.setObject(loaded, forKey: url as NSURL)
                image = loaded
            }
        }
    }
}
