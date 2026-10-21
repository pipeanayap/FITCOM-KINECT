import SwiftUI

/// Métricas de uso del POC y resultados de las encuestas (US-17).
struct UsageMetricsView: View {
    @State private var metrics: UsageMetrics?
    @State private var feedback: [ActivityFeedback] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { await load() }
            } else if let metrics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeaderView(title: "Uso general")
                        LazyVGrid(columns: columns, spacing: 12) {
                            statTile("Creadas", metrics.activitiesCreated, icon: "plus.circle.fill", color: .brandAccent)
                            statTile("Con participantes", metrics.activitiesWithParticipants, icon: "person.2.fill", color: .brandAccent)
                            statTile("Inscripciones", metrics.totalJoins, icon: "checkmark.circle.fill", color: .brandAccent)
                            statTile("Llegaron al cupo", metrics.activitiesAtCapacity, icon: "chart.bar.fill", color: .brandWarning)
                            statTile("Canceladas", metrics.activitiesCancelled, icon: "xmark.circle.fill", color: .red)
                            statTile("Salidas", metrics.participationsLeft, icon: "arrow.uturn.left.circle.fill", color: .secondary)
                        }

                        SectionHeaderView(title: "Resultados de encuestas (\(feedback.count))")
                        if feedback.isEmpty {
                            Text("Todavía no hay respuestas.")
                                .foregroundStyle(.secondary)
                                .cardStyle()
                        } else {
                            let happened = feedback.filter(\.activityHappened).count
                            let metPeople = feedback.filter { $0.metPeople == true }.count
                            let ratings = feedback.compactMap(\.easeRating)
                            let avgRating = ratings.map(Double.init).reduce(0, +) / Double(max(ratings.count, 1))

                            VStack(spacing: 10) {
                                metricRow("Dicen que sí se realizó", "\(happened)")
                                Divider()
                                metricRow("Dicen que conocieron gente", "\(metPeople)")
                                Divider()
                                metricRow("Facilidad promedio", String(format: "%.1f/5", avgRating))
                            }
                            .cardStyle()
                        }
                    }
                    .padding()
                }
                .background(Color.screenBackground)
                .refreshable { await load() }
            }
        }
        .task { await load() }
    }

    private func statTile(_ label: String, _ value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text("\(value)").font(.title.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(Color.brandAccent)
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
