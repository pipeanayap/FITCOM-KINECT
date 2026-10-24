import SwiftUI

// Identidad visual de FITCOM (TECH-04: "mantener consistencia visual").
// Fondo cálido tipo papel, tinta casi negra para texto y navegación propia,
// y un solo acento vibrante (coral) para todo lo que invita a actuar. El
// verde queda reservado exclusivamente para "disponible/abierta", así no
// compite con el coral y cada color sigue significando una sola cosa.

extension Color {
    /// Coral: botones principales, elementos activos, marca.
    static let brandAccent = Color(red: 1.00, green: 0.36, blue: 0.22)
    /// Verde: únicamente estados "abierta/disponible".
    static let brandPrimary = Color(red: 0.11, green: 0.60, blue: 0.47)
    /// Ámbar: "completa" y advertencias suaves.
    static let brandWarning = Color(red: 0.93, green: 0.58, blue: 0.08)
    /// Tinta casi negra: SIEMPRE oscura, para fondos que deben quedar oscuros
    /// en ambos modos (tab bar, botones de contorno oscuro). No usar para texto.
    static let brandInk = Color(red: 0.08, green: 0.08, blue: 0.10)

    /// Texto fuerte que se adapta: casi negro en claro, casi blanco en oscuro.
    /// A diferencia de `brandInk`, este SÍ debe usarse para texto sobre tarjetas,
    /// para que no desaparezca en modo oscuro.
    static let brandText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    })

    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Tarjetas

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

extension View {
    /// Con la barra de navegación oculta el contenido del scroll sube por
    /// debajo de la hora/batería; esto pinta esa franja con el fondo de la
    /// pantalla para que el contenido se corte limpio ahí.
    func statusBarCover() -> some View {
        overlay(alignment: .top) {
            Color.screenBackground.ignoresSafeArea(edges: .top).frame(height: 0)
        }
    }

    func cardStyle(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}

// MARK: - Botones

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                isDisabled ? Color.gray.opacity(0.35) : Color.brandAccent,
                in: Capsule()
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Botón oscuro sólido: para acciones secundarias importantes (p. ej. "Editar"),
/// inspirado en los chips oscuros de apps de eventos — contraste fuerte sin
/// competir con el coral, que se reserva para la acción principal.
struct InkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color.brandInk, in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .brandInk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
            .foregroundStyle(tint)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var fitcomPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func fitcomPrimary(disabled: Bool, fullWidth: Bool = true) -> PrimaryButtonStyle {
        PrimaryButtonStyle(isDisabled: disabled, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var fitcomSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func fitcomSecondary(tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var fitcomInk: InkButtonStyle { InkButtonStyle() }
}

// MARK: - Encabezado de sección

struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Color.brandText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chip de filtro rápido

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                // Seleccionado = naranja de la marca: se distingue igual en claro y oscuro
                // (con el negro de la marca se perdía contra el fondo oscuro).
                .background(isSelected ? Color.brandAccent : Color.cardBackground, in: Capsule())
                .foregroundStyle(isSelected ? .white : Color.brandText)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Barra de acción fija (estilo "ticket")

/// Barra fija al fondo de la pantalla con el estado de disponibilidad a la
/// izquierda y el botón principal a la derecha — como la barra de "Get
/// tickets" de una app de eventos, adaptada a "cupo + Unirme".
///
/// Esta vista siempre se llega empujando (`navigationDestination`) desde una
/// pantalla raíz, y SwiftUI no hereda el `safeAreaInset` reservado para la
/// `FitcomTabBar` flotante a través de ese salto de navegación — por eso el
/// padding inferior aquí incluye manualmente el alto de esa barra (58 del
/// botón + 20 de su padding vertical + 6 de margen inferior en RootView),
/// para que el botón principal no quede tapado por ella.
struct StickyActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    private static var floatingTabBarClearance: CGFloat { 0 }

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 14 + Self.floatingTabBarClearance)
            .background(
                Color.screenBackground
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -6)
            )
    }
}

// MARK: - Degradado de deporte (sustituye a una foto real: no tenemos
// fotografía de usuario en el backlog, así que el color + ícono grande del
// deporte hace del encabezado algo vistoso sin inventar una función nueva).

enum SportVisuals {
    private static let table: [String: (symbol: String, colors: [Color])] = [
        "futbol": ("soccerball", [Color(red: 0.07, green: 0.45, blue: 0.34), Color(red: 0.03, green: 0.25, blue: 0.20)]),
        "fútbol": ("soccerball", [Color(red: 0.07, green: 0.45, blue: 0.34), Color(red: 0.03, green: 0.25, blue: 0.20)]),
        "basquetbol": ("basketball.fill", [Color(red: 0.95, green: 0.45, blue: 0.13), Color(red: 0.65, green: 0.25, blue: 0.05)]),
        "básquetbol": ("basketball.fill", [Color(red: 0.95, green: 0.45, blue: 0.13), Color(red: 0.65, green: 0.25, blue: 0.05)]),
        "baloncesto": ("basketball.fill", [Color(red: 0.95, green: 0.45, blue: 0.13), Color(red: 0.65, green: 0.25, blue: 0.05)]),
        "voleibol": ("volleyball.fill", [Color(red: 0.93, green: 0.58, blue: 0.08), Color(red: 0.55, green: 0.33, blue: 0.02)]),
        "vóleibol": ("volleyball.fill", [Color(red: 0.93, green: 0.58, blue: 0.08), Color(red: 0.55, green: 0.33, blue: 0.02)]),
        "tenis": ("tennisball.fill", [Color(red: 0.42, green: 0.55, blue: 0.14), Color(red: 0.20, green: 0.28, blue: 0.06)]),
        "running": ("figure.run", [Color(red: 1.00, green: 0.36, blue: 0.22), Color(red: 0.55, green: 0.14, blue: 0.06)]),
        "correr": ("figure.run", [Color(red: 1.00, green: 0.36, blue: 0.22), Color(red: 0.55, green: 0.14, blue: 0.06)]),
        "ciclismo": ("figure.outdoor.cycle", [Color(red: 0.11, green: 0.45, blue: 0.60), Color(red: 0.05, green: 0.22, blue: 0.32)]),
        "natacion": ("figure.pool.swim", [Color(red: 0.11, green: 0.50, blue: 0.65), Color(red: 0.04, green: 0.24, blue: 0.34)]),
        "natación": ("figure.pool.swim", [Color(red: 0.11, green: 0.50, blue: 0.65), Color(red: 0.04, green: 0.24, blue: 0.34)]),
        "yoga": ("figure.yoga", [Color(red: 0.55, green: 0.40, blue: 0.65), Color(red: 0.28, green: 0.18, blue: 0.36)]),
        "padel": ("figure.tennis", [Color(red: 0.14, green: 0.45, blue: 0.40), Color(red: 0.06, green: 0.22, blue: 0.20)]),
        "pádel": ("figure.tennis", [Color(red: 0.14, green: 0.45, blue: 0.40), Color(red: 0.06, green: 0.22, blue: 0.20)]),
        "spinning": ("figure.indoor.cycle", [Color(red: 0.80, green: 0.15, blue: 0.35), Color(red: 0.42, green: 0.05, blue: 0.18)]),
        "crossfit": ("figure.strengthtraining.traditional", [Color(red: 0.25, green: 0.25, blue: 0.28), Color(red: 0.10, green: 0.10, blue: 0.12)]),
        "boxeo": ("figure.boxing", [Color(red: 0.70, green: 0.10, blue: 0.12), Color(red: 0.35, green: 0.04, blue: 0.05)]),
        "atletismo": ("figure.track.and.field", [Color(red: 0.95, green: 0.20, blue: 0.10), Color(red: 0.55, green: 0.10, blue: 0.04)]),
        "senderismo": ("figure.hiking", [Color(red: 0.30, green: 0.42, blue: 0.18), Color(red: 0.15, green: 0.22, blue: 0.08)]),
        "escalada": ("figure.climbing", [Color(red: 0.45, green: 0.32, blue: 0.20), Color(red: 0.22, green: 0.15, blue: 0.09)]),
        "badminton": ("figure.badminton", [Color(red: 0.15, green: 0.55, blue: 0.55), Color(red: 0.06, green: 0.28, blue: 0.28)]),
        "bádminton": ("figure.badminton", [Color(red: 0.15, green: 0.55, blue: 0.55), Color(red: 0.06, green: 0.28, blue: 0.28)]),
        "beisbol": ("figure.baseball", [Color(red: 0.13, green: 0.35, blue: 0.62), Color(red: 0.06, green: 0.17, blue: 0.32)]),
        "béisbol": ("figure.baseball", [Color(red: 0.13, green: 0.35, blue: 0.62), Color(red: 0.06, green: 0.17, blue: 0.32)]),
        "futbol americano": ("football.fill", [Color(red: 0.55, green: 0.33, blue: 0.10), Color(red: 0.28, green: 0.16, blue: 0.04)]),
        "fútbol americano": ("football.fill", [Color(red: 0.55, green: 0.33, blue: 0.10), Color(red: 0.28, green: 0.16, blue: 0.04)]),
        "artes marciales": ("figure.martial.arts", [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.03, green: 0.03, blue: 0.04)]),
        "danza": ("figure.dance", [Color(red: 0.75, green: 0.25, blue: 0.55), Color(red: 0.40, green: 0.10, blue: 0.28)]),
    ]

    private static let fallback: (symbol: String, colors: [Color]) =
        ("sportscourt.fill", [Color.brandAccent, Color.brandInk])

    /// Deportes predefinidos para elegir al crear una actividad y al filtrar
    /// (US-03, US-06) — así los filtros no se duplican por variantes de
    /// escritura ("futbol" vs "fútbol" vs errores de dedo).
    static let canonicalSports: [String] = [
        "Fútbol", "Básquetbol", "Voleibol", "Tenis", "Pádel", "Running", "Ciclismo",
        "Natación", "Yoga", "Spinning", "Crossfit", "Boxeo", "Atletismo", "Senderismo",
        "Escalada", "Bádminton", "Béisbol", "Fútbol americano", "Artes marciales", "Danza",
    ]

    static func symbol(for sport: String) -> String {
        (table[sport.lowercased()] ?? fallback).symbol
    }

    static func solidColor(for sport: String) -> Color {
        (table[sport.lowercased()] ?? fallback).colors[0]
    }

    static func gradient(for sport: String) -> LinearGradient {
        let colors = (table[sport.lowercased()] ?? fallback).colors
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
