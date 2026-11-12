import Foundation
import os

/// Registro de la app (consola de Xcode / Console.app). Los mensajes dinámicos
/// se tratan como privados por defecto; marca `privacy: .public` sólo en datos
/// que no sean personales.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Kinect"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let activities = Logger(subsystem: subsystem, category: "activities")
    static let groups = Logger(subsystem: subsystem, category: "groups")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let search = Logger(subsystem: subsystem, category: "search")
}

/// Texto para mostrar al usuario según el tipo de fallo, en lugar de un
/// mensaje único para todo.
enum ErrorText {
    /// `true` si el fallo es de red (sin internet, tiempo agotado, conexión perdida).
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    /// Si no hay red lo dice; si no, usa el mensaje propio de la pantalla.
    static func describe(_ error: Error, fallback: String) -> String {
        isOffline(error) ? "Sin conexión. Revisa tu internet e intenta de nuevo." : fallback
    }
}
