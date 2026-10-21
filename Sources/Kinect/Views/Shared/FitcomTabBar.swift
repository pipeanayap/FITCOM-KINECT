import SwiftUI

enum FitcomTab {
    case explore, mine, create
}

/// Barra de navegación flotante con un botón central elevado para "Crear",
/// en vez de la barra de pestañas estándar de iOS (TECH-04: consistencia
/// visual propia). Perfil no vive aquí: se abre desde el ícono de la
/// esquina superior derecha en la pantalla de Explorar, para dejar esta
/// barra con solo las 3 acciones principales.
struct FitcomTabBar: View {
    @Binding var selected: FitcomTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.explore, icon: "safari.fill", label: "Explorar")

            Button {
                selected = .create
            } label: {
                ZStack {
                    Circle().fill(Color.brandAccent)
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.brandAccent.opacity(0.4), radius: 10, x: 0, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -18)
            .padding(.horizontal, 4)

            tabButton(.mine, icon: "calendar", label: "Mis planes")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.brandInk)
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, 24)
    }

    private func tabButton(_ tab: FitcomTab, icon: String, label: String) -> some View {
        let isSelected = selected == tab
        return Button {
            selected = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.brandAccent : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
        }
    }
}
