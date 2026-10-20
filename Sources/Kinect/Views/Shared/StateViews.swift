import SwiftUI

/// Estados de carga, error y ausencia de resultados (TECH-04), para no
/// repetir el mismo `if/else` en cada pantalla con una lista o un detalle.

struct LoadingStateView: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    var message = "Algo salió mal. Intenta de nuevo."
    var retry: (() async -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Reintentar") { Task { await retry() } }
            }
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
