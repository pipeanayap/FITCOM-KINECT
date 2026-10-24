import SwiftUI

/// Fila de historias de Inicio (SCRUM-49): "Tu historia" y las personas con
/// historias activas. Aro naranja→ámbar si hay algo sin ver, gris si ya se vio.
struct StoriesRowView: View {
    let myName: String
    let myAvatar: String?
    let hasMyStories: Bool
    let groups: [StoryGroup]
    let onOpenMine: () -> Void
    let onAdd: () -> Void
    let onOpen: (StoryGroup) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                mine
                ForEach(groups) { group in
                    Button { onOpen(group) } label: {
                        bubble(name: group.authorName, avatar: group.authorAvatar, ring: group.allViewed ? .viewed : .unseen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private enum Ring { case none, unseen, viewed }

    private var mine: some View {
        Button(action: hasMyStories ? onOpenMine : onAdd) {
            bubble(name: "Tu historia", avatar: myAvatar, ring: hasMyStories ? .unseen : .none, initialsFrom: myName)
                .overlay(alignment: .bottomTrailing) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.brandAccent, in: Circle())
                            .overlay(Circle().stroke(Color.screenBackground, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 2, y: -16)
                }
        }
        .buttonStyle(.plain)
    }

    private func bubble(name: String, avatar: String?, ring: Ring, initialsFrom: String? = nil) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        ring == .unseen
                            ? AnyShapeStyle(LinearGradient(colors: [Color.brandAccent, Color.brandWarning], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(ring == .viewed ? Color.secondary.opacity(0.35) : Color.clear),
                        lineWidth: 3
                    )
                Circle().fill(Color.brandAccent.opacity(0.15)).padding(5)
                if let avatar, !avatar.isEmpty, let url = URL(string: avatar) {
                    CachedAsyncImage(url: url) { initials(initialsFrom ?? name) }
                        .clipShape(Circle())
                        .padding(5)
                } else {
                    initials(initialsFrom ?? name)
                }
            }
            .frame(width: 68, height: 68)
            Text(name)
                .font(.caption)
                .foregroundStyle(Color.brandText)
                .lineLimit(1)
                .frame(width: 72)
        }
    }

    private func initials(_ name: String) -> some View {
        Text(String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }
}
