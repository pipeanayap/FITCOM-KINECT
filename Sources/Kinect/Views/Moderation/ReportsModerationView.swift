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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(reports) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(entry.activity.title).font(.headline)
                                    Spacer()
                                    Label(entry.report.reason.label, systemImage: "flag.fill")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.red)
                                }
                                Text("\(entry.activity.sport.capitalized) · \(entry.activity.zone)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if let description = entry.report.description, !description.isEmpty {
                                    Text(description).font(.subheadline)
                                }
                                if entry.activity.isHidden {
                                    Label("Actividad oculta", systemImage: "eye.slash")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Color.brandWarning)
                                }

                                HStack(spacing: 10) {
                                    Button(entry.activity.isHidden ? "Restablecer" : "Ocultar actividad") {
                                        Task { await toggleHidden(for: entry) }
                                    }
                                    .buttonStyle(.fitcomSecondary)

                                    Button("Marcar revisado") {
                                        Task { await markReviewed(entry.report.id) }
                                    }
                                    .buttonStyle(.fitcomSecondary)
                                }
                                .disabled(busyReportId == entry.id)
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
