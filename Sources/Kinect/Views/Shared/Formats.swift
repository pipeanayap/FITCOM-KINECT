import Foundation

/// Fechas y horas siempre en español de México, aunque el teléfono esté en otro
/// idioma (la app está en español; sin esto salían mezcladas, p. ej.
/// "Sat 31 Oct" y "1 minute ago").
enum Fmt {
    static let locale = Locale(identifier: "es_MX")

    /// "1 lugar libre" / "3 lugares libres" (nunca negativo).
    static func spotsFree(_ count: Int) -> String {
        let n = max(count, 0)
        return n == 1 ? "1 lugar libre" : "\(n) lugares libres"
    }

    /// Versión corta para tarjetas: "1 libre" / "3 libres".
    static func freeShort(_ count: Int) -> String {
        let n = max(count, 0)
        return n == 1 ? "1 libre" : "\(n) libres"
    }

    /// "hace 5 minutos", "ayer", "hace 2 horas".
    static func relative(_ date: Date) -> String {
        date.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: locale))
    }
}
