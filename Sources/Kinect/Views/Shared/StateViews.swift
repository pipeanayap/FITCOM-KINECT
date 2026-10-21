import SwiftUI

/// Estados de carga, error y ausencia de resultados (TECH-04), para no
/// repetir el mismo `if/else` en cada pantalla con una lista o un detalle.

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(.brandAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground)
    }
}

struct ErrorStateView: View {
    var message = "Algo salió mal. Intenta de nuevo."
    var retry: (() async -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.red.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
            }
            Text("No se pudo cargar").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Reintentar") { Task { await retry() } }
                    .buttonStyle(.fitcomSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground)
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.brandAccent.opacity(0.12)).frame(width: 84, height: 84)
                Image(systemName: systemImage)
                    .font(.system(size: 34))
                    .foregroundStyle(Color.brandAccent)
            }
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.screenBackground)
    }
}
