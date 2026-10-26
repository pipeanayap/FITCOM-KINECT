import SwiftUI

/// Las pestañas con pantalla propia. "Crear" no es una: abre un menú de
/// opciones (ver ``CreateMenuView``).
enum FitcomTab {
    case home, explore, groups, mine
}

/// Las pantallas de detalle esconden la barra (como Instagram al abrir un
/// perfil o una publicación) y la devuelven al regresar.
@MainActor
@Observable
final class TabBarState {
    private var requestedHidden = false
    var activeTab: FitcomTab = .home
    var exploreAtRoot = true

    // Las pantallas de detalle pueden seguir montadas en pestañas inactivas.
    // Sus callbacks no deben ocultar la barra sobre la raíz de Explorar.
    var isHidden: Bool {
        get { requestedHidden && !(activeTab == .explore && exploreAtRoot) }
        set { requestedHidden = newValue }
    }
    /// Borde superior en coordenadas de pantalla, incluido el botón Crear.
    var topEdge: CGFloat?
    /// Una pantalla pide cambiar de pestaña (p. ej. "Únete a tu primer grupo");
    /// RootView lo atiende y lo limpia.
    var requestedTab: FitcomTab?
}

/// Barra de navegación flotante de vidrio (estilo iOS 26 "Liquid Glass"):
/// cuatro pestañas con ícono y texto, y al centro el botón Crear, elevado y
/// también de vidrio, que abre el menú de creación (TECH-04: consistencia
/// visual propia). Perfil no vive aquí: se abre desde el ícono de la esquina
/// superior derecha.
struct FitcomTabBar: View {
    @Binding var selected: FitcomTab
    @Binding var isCreateOpen: Bool

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 2) {
                tabButton(.home, icon: "house.fill", label: "Inicio")
                tabButton(.explore, icon: "safari.fill", label: "Explorar")
                // Hueco para el botón elevado, que se dibuja encima.
                Color.clear.frame(width: 66, height: 1)
                tabButton(.groups, icon: "person.3.fill", label: "Grupos")
                tabButton(.mine, icon: "calendar", label: "Planes")
            }
            .padding(5)
            .glassSurface(Capsule())
            .padding(.top, 22) // el botón sobresale por encima de la cápsula

            createButton
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
    }

    private var createButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { isCreateOpen.toggle() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isCreateOpen ? 45 : 0))
                .frame(width: 58, height: 58)
                .glassSurface(Circle(), tint: Color.brandAccent.opacity(0.85), interactive: true)
                // Todo el círculo cuenta como botón, no sólo el trazo de la cruz.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCreateOpen ? "Cerrar menú" : "Crear")
    }

    private func tabButton(_ tab: FitcomTab, icon: String, label: String) -> some View {
        let isSelected = selected == tab
        return Button {
            isCreateOpen = false
            selected = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.white : .white.opacity(0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(isSelected ? 0.18 : 0)))
        }
        .accessibilityLabel(label)
    }
}

extension View {
    /// Vidrio nativo en iOS 26+; en versiones anteriores, material desenfocado
    /// (o color sólido si lleva `tint`).
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            background {
                if let tint {
                    shape.fill(tint)
                } else {
                    shape.fill(.ultraThinMaterial).overlay(shape.fill(Color.black.opacity(0.10)))
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 6)
        }
    }
}

/// Menú de creación que sale sobre el botón central (en vez de una pantalla).
struct CreateMenuView: View {
    enum Option { case activity, post, story, group }

    let onSelect: (Option) -> Void

    var body: some View {
        VStack(spacing: 2) {
            row(.activity, icon: "calendar.badge.plus", title: "Actividad", subtitle: "Organiza algo y junta gente")
            row(.post, icon: "photo.on.rectangle.angled", title: "Publicación", subtitle: "Comparte texto y fotos")
            row(.story, icon: "circle.dashed.inset.filled", title: "Historia", subtitle: "Una foto que dura 24 horas")
            row(.group, icon: "person.3.fill", title: "Grupo", subtitle: "Crea una comunidad")
        }
        .padding(8)
        .frame(width: 290)
        .glassSurface(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func row(_ option: Option, icon: String, title: String, subtitle: String) -> some View {
        Button { onSelect(option) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.brandAccent.opacity(0.9), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
