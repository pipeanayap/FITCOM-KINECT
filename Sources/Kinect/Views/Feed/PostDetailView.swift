import SwiftUI

private struct ViewerItem: Identifiable {
    let id = UUID()
    let post: Post
    let index: Int
}

/// Publicación completa con sus comentarios (SCRUM-44). Esconde la barra de
/// pestañas como el detalle de actividad.
struct PostDetailView: View {
    @State var post: Post

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var comments: [PostComment] = []
    @State private var activity: Activity?
    @State private var isJoined = false
    @State private var isJoining = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var reportTarget: Post?
    @State private var viewer: ViewerItem?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PostCardView(
                        post: $post,
                        activity: activity,
                        isJoined: isJoined,
                        isJoining: isJoining,
                        onJoin: { join($0) },
                        onDelete: { delete($0) },
                        onHide: { hide($0) },
                        onReport: { reportTarget = $0 },
                        onOpenImages: { viewer = ViewerItem(post: $0, index: $1) },
                        showsCommentLink: false
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }

                        SectionHeaderView(title: "Comentarios")
                        if comments.isEmpty {
                            Text("Sé el primero en comentar.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(comments) { comment in
                                    commentRow(comment)
                                    if comment.id != comments.last?.id { Divider() }
                                }
                            }
                            .cardStyle(padding: 12)
                        }
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .background(Color.screenBackground)
            .scrollDismissesKeyboard(.interactively)

            if authStore.isSignedIn { composer }
        }
        .background(Color.screenBackground)
        .statusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { ActivityDetailView(activityId: $0) }
        .sheet(item: $reportTarget) { ReportPostView(postId: $0.id) }
        .fullScreenCover(item: $viewer) { item in
            // Aquí los comentarios ya están a la vista: el botón sólo cierra el visor.
            ImageViewerView(post: item.post, index: item.index, onChange: { post = $0 }, onOpenComments: { _ in })
        }
        .task { await load() }
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                tabBar.isHidden = false
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.brandText)
                    .frame(width: 36, height: 36)
                    .background(Color.cardBackground, in: Circle())
            }
            Text("Publicación").font(.headline).foregroundStyle(Color.brandText)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func commentRow(_ comment: PostComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: ProfileRoute(userId: comment.authorId)) {
            ZStack {
                Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 34, height: 34)
                Text(String((comment.profiles?.fullName ?? "?").split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.brandAccent)
            }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.profiles?.fullName ?? "Usuario").font(.subheadline.weight(.semibold))
                    Text(Fmt.relative(comment.createdAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.body).font(.subheadline).foregroundStyle(Color.brandText)
            }
            Spacer(minLength: 0)
            if comment.authorId == authStore.userId || authStore.isAdmin {
                Button {
                    Task { await deleteComment(comment) }
                } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Escribe un comentario…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.cardBackground, in: Capsule())
            if isSending {
                ProgressView().tint(.brandAccent)
            } else {
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend ? Color.brandAccent : Color.secondary.opacity(0.4), in: Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.screenBackground)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty && draft.count <= 500 }

    private func load() async {
        if let fresh = try? await PostService.detail(id: post.id) { post = fresh }
        comments = (try? await PostService.comments(postId: post.id)) ?? []
        if let id = post.activityId {
            activity = try? await ActivityService.detail(id: id)
            if let userId = authStore.userId {
                isJoined = (try? await ParticipationService.myParticipation(activityId: id, userId: userId)) != nil
            }
        }
    }

    private func send() async {
        guard let userId = authStore.userId, canSend else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            try await PostService.addComment(postId: post.id, authorId: userId, body: draft.trimmingCharacters(in: .whitespaces))
            draft = ""
            comments = (try? await PostService.comments(postId: post.id)) ?? comments
            if let fresh = try? await PostService.detail(id: post.id) { post = fresh }
        } catch {
            errorMessage = "No se pudo enviar el comentario."
        }
    }

    private func deleteComment(_ comment: PostComment) async {
        do {
            try await PostService.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
            post.commentCount = max(post.commentCount - 1, 0)
        } catch {
            errorMessage = "No se pudo borrar el comentario."
        }
    }

    private func join(_ activity: Activity) {
        guard let userId = authStore.userId, !isJoining else { return }
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                try await ParticipationService.join(activityId: activity.id, userId: userId)
                isJoined = true
            } catch {
                errorMessage = "No te pudiste unir: la actividad está llena o ya no está disponible."
            }
            self.activity = try? await ActivityService.detail(id: activity.id)
        }
    }

    private func delete(_ post: Post) {
        Task {
            do {
                try await PostService.delete(post)
                tabBar.isHidden = false
                dismiss()
            } catch {
                errorMessage = "No se pudo eliminar la publicación."
            }
        }
    }

    private func hide(_ post: Post) {
        Task {
            do {
                try await PostService.setHidden(postId: post.id, hidden: true)
                tabBar.isHidden = false
                dismiss()
            } catch {
                errorMessage = "No se pudo ocultar la publicación."
            }
        }
    }
}
