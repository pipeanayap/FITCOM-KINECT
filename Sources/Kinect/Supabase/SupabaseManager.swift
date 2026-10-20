import Foundation
import Supabase

/// Punto único de acceso al cliente de Supabase (auth, base de datos, etc.).
/// El codificador/decodificador convierte entre el `camelCase` de Swift y el
/// `snake_case` de las columnas en Postgres, y entiende las fechas ISO-8601
/// (con o sin fracción de segundo) que devuelve PostgREST.
enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: URL(string: Secrets.supabaseURL)!,
        supabaseKey: Secrets.supabaseAnonKey,
        options: .init(db: .init(encoder: jsonEncoder, decoder: jsonDecoder))
    )

    private static let withFractionalSeconds = Date.ISO8601FormatStyle()
        .year().month().day()
        .dateTimeSeparator(.standard)
        .time(includingFractionalSeconds: true)

    private static let withoutFractionalSeconds = Date.ISO8601FormatStyle()
        .year().month().day()
        .dateTimeSeparator(.standard)
        .time(includingFractionalSeconds: false)

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: withFractionalSeconds) {
                return date
            }
            if let date = try? Date(string, strategy: withoutFractionalSeconds) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Fecha inválida: \(string)"
            )
        }
        return decoder
    }()

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(withFractionalSeconds))
        }
        return encoder
    }()
}
