import SwiftUI

/// Pestaña para publicar una actividad (US-03). Requiere sesión.
struct CreateActivityView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var showForm = false
    @State private var createdActivity: Activity?

    var body: some View {
        NavigationStack {
            Group {
                if authStore.isSignedIn {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Publica una actividad deportiva y encuentra gente para hacerla contigo.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Publicar actividad") { showForm = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    EmptyStateView(
                        title: "Inicia sesión para publicar",
                        message: "Necesitas una cuenta para crear una actividad.",
                        systemImage: "lock"
                    )
                }
            }
            .navigationTitle("Nueva actividad")
            .navigationDestination(item: $createdActivity) { activity in
                ActivityDetailView(activityId: activity.id)
            }
        }
        .sheet(isPresented: $showForm) {
            if let userId = authStore.userId {
                ActivityFormView(
                    organizerId: userId,
                    saveAction: .create { try await ActivityService.create($0) },
                    onSaved: { createdActivity = $0 }
                )
            }
        }
    }
}
