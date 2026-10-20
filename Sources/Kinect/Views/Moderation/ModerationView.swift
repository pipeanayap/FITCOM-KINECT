import SwiftUI

/// Acceso exclusivo para administradores: revisar reportes y moderar
/// actividades (US-15), y consultar las métricas de uso del POC (US-17).
/// `RootView` ya evita mostrar esta pestaña a quien no es admin; aun así
/// cada acción depende de las políticas de RLS, no sólo de ocultar el botón.
struct ModerationView: View {
    private enum Section: String, CaseIterable {
        case reportes = "Reportes"
        case metricas = "Métricas"
    }

    @State private var section: Section = .reportes

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Sección", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch section {
                case .reportes: ReportsModerationView()
                case .metricas: UsageMetricsView()
                }
            }
            .navigationTitle("Moderación")
        }
    }
}
