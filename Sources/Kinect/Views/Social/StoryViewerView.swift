import SwiftUI

struct StoryViewerItem: Identifiable {
    let id = UUID()
    let groups: [StoryGroup]
    let startIndex: Int
}

/// Visor de historias a pantalla completa (SCRUM-49): barras de progreso,
/// avance automático (5 s), toque a la izquierda/derecha para retroceder o
/// avanzar, deslizar hacia abajo para cerrar. El autor ve cuántos la vieron.
struct StoryViewerView: View {
    let groups: [StoryGroup]
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var groupIndex: Int
    @State private var storyIndex: Int
    @State private var progress: Double = 0
    @State private var dragOffset: CGFloat = 0

    private let duration = 5.0

    init(item: StoryViewerItem, onChanged: @escaping () -> Void) {
        groups = item.groups
        self.onChanged = onChanged
        _groupIndex = State(initialValue: item.startIndex)
        _storyIndex = State(initialValue: item.groups[item.startIndex].firstUnviewedIndex)
    }

    private var group: StoryGroup { groups[groupIndex] }
    private var story: Story { group.stories[min(storyIndex, group.stories.count - 1)] }
    private var isMine: Bool { story.authorId == authStore.userId }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FittedRemoteImage(url: ImageUploadService.publicURL(for: story.imagePath))
                .id(story.id)

            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { previous() }
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
            }

            VStack(spacing: 12) {
                progressBars
                header
                Spacer()
                footer
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { if $0.translation.height > 0 { dragOffset = $0.translation.height } }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                    }
                }
        )
        .task(id: story.id) { await run() }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array(group.stories.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .scaleEffect(x: index < storyIndex ? 1 : (index == storyIndex ? progress : 0), anchor: .leading)
                    }
                    .clipShape(Capsule())
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.brandAccent.opacity(0.3))
                if let avatar = group.authorAvatar, !avatar.isEmpty, let url = URL(string: avatar) {
                    CachedAsyncImage(url: url) { EmptyView() }.clipShape(Circle())
                } else {
                    Text(String(group.authorName.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 0) {
                Text(isMine ? "Tu historia" : group.authorName).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(Fmt.relative(story.createdAt)).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()

            if isMine {
                Menu {
                    Button(role: .destructive) { Task { await deleteStory() } } label: {
                        Label("Eliminar historia", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if let caption = story.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .environment(\.colorScheme, .dark)
            }
            if isMine {
                Label(story.viewCount == 1 ? "1 persona la vio" : "\(story.viewCount) personas la vieron", systemImage: "eye")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassSurface(Capsule())
                    .environment(\.colorScheme, .dark)
            }
        }
    }

    // MARK: - Avance

    private func run() async {
        progress = 0
        if let me = authStore.userId, story.authorId != me {
            await StoryService.markViewed(storyId: story.id, viewerId: me)
        }
        let steps = 100
        for _ in 0..<steps {
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) / steps))
            if Task.isCancelled { return }
            progress += 1.0 / Double(steps)
        }
        next()
    }

    private func next() {
        if storyIndex + 1 < group.stories.count {
            storyIndex += 1
        } else if groupIndex + 1 < groups.count {
            groupIndex += 1
            storyIndex = groups[groupIndex].firstUnviewedIndex
        } else {
            dismiss()
        }
    }

    private func previous() {
        if storyIndex > 0 {
            storyIndex -= 1
        } else if groupIndex > 0 {
            groupIndex -= 1
            storyIndex = 0
        } else {
            progress = 0
        }
    }

    private func deleteStory() async {
        try? await StoryService.delete(story)
        onChanged()
        dismiss()
    }
}
