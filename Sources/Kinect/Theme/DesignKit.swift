import SwiftUI

// Lenguaje visual "social + energía": tipografía pesada y redondeada para lo
// que importa, etiquetas en mayúsculas con tracking para los datos, las
// personas al frente (avatares apilados) y barras de cupo que se llenan.
// Todo usa estilos de texto de Dynamic Type, así que escala con la
// configuración del teléfono.

// MARK: - Marca

/// Nombre de la app en un solo lugar: cuando se decida el nombre definitivo,
/// se cambia aquí (y en los textos de permisos de `Info.plist`).
enum Brand {
    static let name = "FITCOM"
    static let tagline = "Encuentra con quién moverte"
}

// MARK: - Tipografía

extension Font {
    /// Saludos y títulos de pantalla.
    static let displayXL = Font.system(.largeTitle, design: .rounded, weight: .heavy)
    /// Título de una tarjeta héroe.
    static let displayL = Font.system(.title, design: .rounded, weight: .heavy)
    static let displayM = Font.system(.title2, design: .rounded, weight: .bold)
    /// Título de una fila o tarjeta normal.
    static let cardTitle = Font.system(.headline, design: .rounded, weight: .bold)
    /// Datos cortos en mayúsculas ("HOY 19:00", "FÚTBOL").
    static let metaCaps = Font.system(.caption2, design: .rounded, weight: .heavy)
}

extension View {
    /// Etiqueta de dato en mayúsculas con tracking.
    func metaCaps(_ color: Color = .secondary) -> some View {
        font(.metaCaps)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Medidas

enum DS {
    static let cardRadius: CGFloat = 24
    static let heroRadius: CGFloat = 30
    static let screenPadding: CGFloat = 16
}

// MARK: - Personas

/// Persona que se muestra en un avatar apilado.
struct Attendee: Hashable {
    var name: String
    var avatarUrl: String?
}

/// Avatares superpuestos con un anillo del color del fondo y "+N" si hay más.
/// Es lo que vuelve social a una tarjeta: se ve quién va.
struct AvatarStack: View {
    let people: [Attendee]
    /// Cuántas personas hay en total (puede ser más que las que se dibujan).
    let total: Int
    var size: CGFloat = 26
    /// Color del fondo sobre el que está, para el anillo que separa los avatares.
    var ring: Color = .cardBackground
    var maxShown = 4

    var body: some View {
        let shown = Array(people.prefix(maxShown))
        HStack(spacing: -size * 0.3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, person in
                AvatarView(url: person.avatarUrl, name: person.name, size: size)
                    .overlay(Circle().stroke(ring, lineWidth: 2))
            }
            if total > shown.count {
                Text("+\(total - shown.count)")
                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.brandInk, in: Circle())
                    .overlay(Circle().stroke(ring, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total == 1 ? "1 persona va" : "\(total) personas van")
    }
}

// MARK: - Cupo

/// Barra de cupo: se llena con lo inscrito. En ámbar cuando quedan pocos lugares.
struct CapacityBar: View {
    let filled: Int
    let capacity: Int
    var tint: Color = .brandAccent
    var track: Color = Color.primary.opacity(0.12)
    var height: CGFloat = 6

    private var fraction: Double {
        guard capacity > 0 else { return 0 }
        return min(max(Double(filled) / Double(capacity), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * fraction, fraction > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: filled)
        .accessibilityHidden(true)
    }
}

// MARK: - Fechas para tarjetas

extension Fmt {
    /// "Hoy · 19:00", "Mañana · 8:00", "sáb 31 oct · 19:00".
    static func dayChip(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoy · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Mañana · \(time)" }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        return "\(day) · \(time)"
    }
}
