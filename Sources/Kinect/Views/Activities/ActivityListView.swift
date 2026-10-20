import SwiftUI

/// Explorar actividades disponibles, sin necesidad de sesión (US-04),
/// con filtros combinables (US-06).
struct ActivityListView: View {
    @State private var activities: [Activity] = []
    @State private var filter: ActivityFilter = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFilterSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage, retry: load)
                } else if activities.isEmpty {
                    EmptyStateView(
                        title: filter.isEmpty ? "Sin actividades por ahora" : "Nada con esos filtros",
                        message: filter.isEmpty
                            ? "Cuando alguien publique una actividad, aparecerá aquí."
                            : "Intenta con otros filtros o límpialos.",
                        systemImage: "figure.run.circle"
                    )
                } else {
                    List(activities) { activity in
                        NavigationLink(value: activity.id) {
                            ActivityRowView(activity: activity)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Explorar")
            .navigationDestination(for: UUID.self) { activityId in
                ActivityDetailView(activityId: activityId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Label("Filtros", systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                ActivityFilterSheet(filter: $filter)
            }
            .task { await load() }
            .onChange(of: filter) { Task { await load() } }
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            activities = try await ActivityService.list(filter: filter)
        } catch {
            errorMessage = "No se pudieron cargar las actividades."
        }
    }
}
