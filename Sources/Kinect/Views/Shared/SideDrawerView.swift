import SwiftUI

/// Panel lateral que se abre al tocar la burbuja de perfil (estilo Twitter/X):
/// tu foto, nombre y conteos, y el menú. Por ahora: Perfil y Configuración;
/// el resto de opciones se irán agregando aquí.
struct SideDrawerView: View {
    static let width: CGFloat = 310

    let onProfile: () -> Void
    let onSettings: () -> Void
    let onSignIn: () -> Void

    @Environment(AuthStore.self) private var authStore
    @State private var stats: ProfileStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if authStore.isSignedIn {
                identity
                Divider().padding(.vertical, 18)
                menuRow("Perfil", icon: "person", action: onProfile)
            } else {
                signedOut
            }
            Spacer()
            if authStore.isSignedIn {
                Divider().padding(.bottom, 8)
                smallRow("Configuración y cuenta", icon: "gearshape", action: onSettings)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task(id: authStore.userId) { await loadStats() }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onProfile) {
                ZStack {
                    Circle().fill(
                        LinearGradient(colors: [Color.brandAccent, Color.brandWarning], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    if let urlString = authStore.profile?.avatarUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                        CachedAsyncImage(url: url) { initials }.clipShape(Circle()).padding(3)
                    } else {
                        Circle().fill(Color(uiColor: .systemBackground)).padding(3)
                        initials
                    }
                }
                .frame(width: 66, height: 66)
            }
            .buttonStyle(.plain)

            Text(authStore.profile?.fullName ?? "")
                .font(.title3.bold())
                .foregroundStyle(Color.brandText)
                .lineLimit(2)

            if let zone = authStore.profile?.zone, !zone.isEmpty {
                Label(zone, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                count(stats?.followingCount, "Siguiendo")
                count(stats?.followersCount, "Seguidores")
            }
            .padding(.top, 2)
        }
    }

    private var initials: some View {
        Text(String((authStore.profile?.fullName ?? "?").split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
            .font(.title3.bold())
            .foregroundStyle(Color.brandAccent)
    }

    private func count(_ value: Int?, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(value.map(String.init) ?? "–").font(.subheadline.bold()).foregroundStyle(Color.brandText)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle().fill(Color.brandAccent.opacity(0.15))
                Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(Color.brandAccent)
            }
            .frame(width: 66, height: 66)
            Text("Únete a la comunidad").font(.title3.bold()).foregroundStyle(Color.brandText)
            Text("Inicia sesión para publicar, seguir a otras personas y unirte a actividades.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Iniciar sesión", action: onSignIn)
                .buttonStyle(.fitcomPrimary)
        }
    }

    private func menuRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 22, weight: .regular)).frame(width: 30)
                Text(title).font(.title2.bold())
                Spacer()
            }
            .foregroundStyle(Color.brandText)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func smallRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 30)
                Text(title).font(.headline.weight(.regular))
                Spacer()
            }
            .foregroundStyle(Color.brandText)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadStats() async {
        guard let userId = authStore.userId else { stats = nil; return }
        stats = try? await FollowService.stats(userId: userId)
    }
}
