import SwiftUI

/// Actividades creadas y a las que me he unido (US-09). Desde aquí se
/// entra a editar/cancelar (US-11, US-12), salir (US-10) y calificar una
/// actividad ya finalizada (US-16).
struct MyActivitiesView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var organized: [Activity] = []
    @State private var joined: [MyParticipation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var feedbackTarget: Activity?

    var body: some View {
        NavigationStack {
            Group {
                if !authStore.isSignedIn {
                    EmptyStateView(
                        title: "Inicia sesión",
                        message: "Necesitas una cuenta para ver tus actividades.",
                        systemImage: "lock"
                    )
                } else if isLoading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { await load() }
                } else if organized.isEmpty && joined.isEmpty {
                    EmptyStateView(
                        title: "Todavía no tienes actividades",
                        message: "Crea una actividad o únete a alguna desde Explorar.",
                        systemImage: "calendar.badge.plus"
                    )
                } else {
                    List {
                        if !organized.isEmpty {
                            Section("Creadas por mí") {
                                ForEach(organized) { activity in
                                    NavigationLink(value: activity.id) {
                                        ActivityRowView(activity: activity)
                                    }
                                }
                            }
                        }
                        if !joined.isEmpty {
                            Section("A las que me uní") {
                                ForEach(joined) { entry in
                                    NavigationLink(value: entry.activity.id) {
                                        VStack(alignment: .leading) {
                                            ActivityRowView(activity: entry.activity)
                                            if entry.activity.computedStatus == .finalizada
                                                && entry.participation.status == .activa {
                                                Button("Calificar experiencia") {
                                                    feedbackTarget = entry.activity
                                                }
                                                .font(.footnote)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Mis actividades")
            .navigationDestination(for: UUID.self) { activityId in
                ActivityDetailView(activityId: activityId)
            }
            .sheet(item: $feedbackTarget) { activity in
                ActivityFeedbackView(activityId: activity.id)
            }
            .task { await load() }
            .onChange(of: authStore.isSignedIn) { Task { await load() } }
        }
    }

    private func load() async {
        guard let userId = authStore.userId else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        async let organizedResult = ActivityService.mine(organizerId: userId)
        async let joinedResult = ParticipationService.joined(userId: userId)
        do {
            organized = try await organizedResult
            // El organizador también queda registrado como participante de su
            // propia actividad (US-03); no la repetimos en esta sección.
            joined = try await joinedResult.filter { $0.activity.organizerId != userId }
        } catch {
            errorMessage = "No se pudieron cargar tus actividades."
        }
    }
}
