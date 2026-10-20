import SwiftUI

/// Reportes pendientes y acciones de moderación (US-15).
struct ReportsModerationView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var reports: [ReportWithActivity] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyReportId: UUID?

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { await load() }
            } else if reports.isEmpty {
                EmptyStateView(
                    title: "Sin reportes pendientes",
                    message: "Cuando alguien reporte una actividad, aparecerá aquí.",
                    systemImage: "checkmark.shield"
                )
            } else {
                List(reports) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.activity.title).font(.headline)
                        Text("\(entry.activity.sport.capitalized) · \(entry.activity.zone)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(entry.report.reason.label).fontWeight(.semibold)
                        if let description = entry.report.description, !description.isEmpty {
                            Text(description).font(.footnote)
                        }
                        if entry.activity.isHidden {
                            Label("Actividad oculta", systemImage: "eye.slash").font(.footnote)
                        }

                        HStack {
                            Button(entry.activity.isHidden ? "Restablecer" : "Ocultar actividad") {
                                Task { await toggleHidden(for: entry) }
                            }
                            .buttonStyle(.bordered)

                            Button("Marcar revisado") {
                                Task { await markReviewed(entry.report.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(busyReportId == entry.id)
                    }
                    .padding(.vertical, 4)
                }
                .refreshable { await load() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            reports = try await ModerationService.pendingReports()
        } catch {
            errorMessage = "No se pudieron cargar los reportes."
        }
    }

    private func toggleHidden(for entry: ReportWithActivity) async {
        guard let adminId = authStore.userId else { return }
        busyReportId = entry.id
        defer { busyReportId = nil }
        do {
            if entry.activity.isHidden {
                try await ModerationService.restore(activityId: entry.activity.id, adminId: adminId)
            } else {
                try await ModerationService.hide(activityId: entry.activity.id, adminId: adminId)
            }
            await load()
        } catch {
            // Se deja reintentar: la lista no se actualiza y el botón vuelve a estar activo.
        }
    }

    private func markReviewed(_ reportId: UUID) async {
        busyReportId = reportId
        defer { busyReportId = nil }
        do {
            try await ModerationService.markReviewed(reportId: reportId)
            await load()
        } catch {
            // igual que arriba: se puede reintentar.
        }
    }
}
