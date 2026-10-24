import SwiftUI

/// Una publicación del feed (SCRUM-43 a SCRUM-46). Con fotos: foto con las
/// cuatro esquinas redondeadas que se desliza y las acciones en una
/// píldora de vidrio sobre la foto; doble toque da like. Sin fotos: el texto
/// va en un bloque tintado. Después: "N me gusta", texto con el nombre en
/// negritas, la actividad adjunta con Unirme y el enlace a los comentarios.
struct PostCardView: View {
    @Binding var post: Post
    let activity: Activity?
    let isJoined: Bool
    let isJoining: Bool
    let onJoin: (Activity) -> Void
    let onDelete: (Post) -> Void
    let onHide: (Post) -> Void
    let onReport: (Post) -> Void
    let onOpenImages: (Post, Int) -> Void
    /// En el detalle del post el botón de comentarios no navega a sí mismo.
    var showsCommentLink = true

    @Environment(AuthStore.self) private var authStore
    @State private var showDeleteConfirmation = false
    @State private var page = 0
    @State private var heartVisible = false
    @State private var captionExpanded = false

    private var hasPhotos: Bool { !post.imagePaths.isEmpty }
    private var hasBody: Bool { !(post.body ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.padding(.horizontal, 16)

            if hasPhotos {
                media
            } else if hasBody {
                textBlock
            }

            if hasPhotos || hasBody { likesLabel }

            if hasPhotos, hasBody { caption.padding(.horizontal, 16) }

            if let activity {
                FeedActivityCard(
                    activity: activity,
                    isJoined: isJoined,
                    isMine: authStore.userId == activity.organizerId,
                    isSignedIn: authStore.isSignedIn,
                    isBusy: isJoining,
                    onJoin: { onJoin(activity) }
                )
                .padding(.horizontal, 16)
            }

            // Un post que sólo trae la actividad: las acciones van debajo de la tarjeta.
            if !hasPhotos && !hasBody {
                actionBar(onPhoto: false).padding(.horizontal, 16)
                likesLabel
            }

            if showsCommentLink {
                NavigationLink(value: post) {
                    Text(post.commentCount > 0
                         ? (post.commentCount == 1 ? "Ver 1 comentario" : "Ver los \(post.commentCount) comentarios")
                         : "Agregar un comentario…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
        .confirmationDialog("¿Eliminar esta publicación?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { onDelete(post) }
            Button("Cancelar", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var likesLabel: some View {
        if post.likeCount > 0 {
            Text(post.likeCount == 1 ? "1 me gusta" : "\(post.likeCount) me gusta")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandText)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Encabezado

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: ProfileRoute(userId: post.authorId)) {
                HStack(spacing: 10) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.authorName).font(.subheadline.weight(.bold)).foregroundStyle(Color.brandText)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if authStore.isSignedIn { menu }
        }
    }

    private var subtitle: String {
        let time = Fmt.relative(post.createdAt)
        return post.kind == "activity" ? "publicó una actividad · \(time)" : time
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.brandAccent.opacity(0.15))
            if let urlString = post.authorAvatar, !urlString.isEmpty, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { initials }
                    .clipShape(Circle())
            } else {
                initials
            }
        }
        .frame(width: 40, height: 40)
    }

    private var initials: some View {
        Text(String(post.authorName.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }

    private var menu: some View {
        Menu {
            if authStore.userId == post.authorId {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            } else {
                Button { onReport(post) } label: { Label("Reportar", systemImage: "flag") }
                if authStore.isAdmin {
                    Button(role: .destructive) { onHide(post) } label: {
                        Label("Ocultar publicación", systemImage: "eye.slash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
    }

    // MARK: - Fotos

    private var media: some View {
        Color.screenBackground
            .aspectRatio(0.85, contentMode: .fit)
            .overlay {
                TabView(selection: $page) {
                    ForEach(Array(post.imagePaths.enumerated()), id: \.offset) { offset, path in
                        CachedAsyncImage(url: ImageUploadService.publicURL(for: path)) {
                            ProgressView().tint(.brandAccent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Los toques de la foto viven aquí, no en todo el contenedor: así la
                // píldora de acciones (encima) no compite con el doble toque.
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTapLike() }
                .onTapGesture { onOpenImages(post, page) }
            }
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 14)
                    .scaleEffect(heartVisible ? 1 : 0.4)
                    .opacity(heartVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) { actionBar(onPhoto: true).padding(14) }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
    }

    // MARK: - Texto sin fotos

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(post.body ?? "")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.brandText)
            actionBar(onPhoto: false)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.brandAccent.opacity(0.16), Color.brandPrimary.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .padding(.horizontal, 16)
    }

    private var caption: some View {
        Text("\(Text(post.authorName).fontWeight(.bold)) \(post.body ?? "")")
            .font(.subheadline)
            .foregroundStyle(Color.brandText)
            .lineLimit(captionExpanded ? nil : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { captionExpanded.toggle() } }
    }

    // MARK: - Acciones

    /// Corazón, comentarios y, con varias fotos, los puntos de página. Sobre la
    /// foto va en una píldora de vidrio; sin foto va en plano.
    @ViewBuilder
    private func actionBar(onPhoto: Bool) -> some View {
        let content = HStack(spacing: 2) {
            Button(action: toggleLike) {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(post.likedByMe ? Color.red : (onPhoto ? .white : Color.brandText))
                    .symbolEffect(.bounce, value: post.likedByMe)
                    .tapTarget()
            }
            .buttonStyle(.plain)
            .disabled(!authStore.isSignedIn)

            commentIcon(onPhoto: onPhoto)

            if onPhoto, post.imagePaths.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<post.imagePaths.count, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(index == page ? 1 : 0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        if onPhoto {
            content
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassSurface(Capsule())
                .environment(\.colorScheme, .dark)
        } else {
            // El área táctil de 46 pt deja el ícono con aire a la izquierda; se compensa.
            content.padding(.leading, -11)
        }
    }

    @ViewBuilder
    private func commentIcon(onPhoto: Bool) -> some View {
        let icon = Image(systemName: "bubble.right")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(onPhoto ? .white : Color.brandText)
            .tapTarget()
        if showsCommentLink {
            NavigationLink(value: post) { icon }.buttonStyle(.plain)
        } else {
            icon
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
            }
        }
    }
}

private extension View {
    /// Área táctil cómoda (46 pt) para un ícono pequeño.
    func tapTarget() -> some View {
        frame(width: 46, height: 46).contentShape(Rectangle())
    }
}
