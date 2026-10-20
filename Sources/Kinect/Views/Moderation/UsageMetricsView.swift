import SwiftUI

/// Métricas de uso del POC y resultados de las encuestas (US-17).
struct UsageMetricsView: View {
    @State private var metrics: UsageMetrics?
    @State private var feedback: [ActivityFeedback] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { await load() }
            } else if let metrics {
                List {
                    Section("Uso general") {
                        metricRow("Actividades creadas", metrics.activitiesCreated)
                        metricRow("Actividades con participantes", metrics.activitiesWithParticipants)
                        metricRow("Inscripciones totales", metrics.totalJoins)
                        metricRow("Actividades que llegaron al cupo", metrics.activitiesAtCapacity)
                        metricRow("Actividades canceladas", metrics.activitiesCancelled)
                        metricRow("Salidas de participantes", metrics.participationsLeft)
                    }

                    Section("Resultados de encuestas (\(feedback.count))") {
                        if feedback.isEmpty {
                            Text("Todavía no hay respuestas.").foregroundStyle(.secondary)
                        } else {
                            let happened = feedback.filter(\.activityHappened).count
                            let metPeople = feedback.filter { $0.metPeople == true }.count
                            let avgRating = feedback.compactMap(\.easeRating).map(Double.init).reduce(0, +)
                                / Double(max(feedback.compactMap(\.easeRating).count, 1))
                            metricRow("Dicen que sí se realizó", happened)
                            metricRow("Dicen que conocieron gente", metPeople)
                            Text("Facilidad promedio: \(avgRating, specifier: "%.1f")/5")
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .task { await load() }
    }

    private func metricRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)").fontWeight(.semibold)
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let summary = MetricsService.summary()
            async let allFeedback = FeedbackService.all()
            metrics = try await summary
            feedback = try await allFeedback
        } catch {
            errorMessage = "No se pudieron cargar las métricas."
        }
    }
}
