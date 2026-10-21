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
                    VStack(spacing: 20) {
                        ZStack {
                            Circle().fill(Color.brandAccent.gradient).frame(width: 96, height: 96)
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(spacing: 6) {
                            Text("¿Qué quieres hacer hoy?").font(.title3.bold())
                            Text("Publica una actividad deportiva y encuentra gente para hacerla contigo.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        Button("Publicar actividad") { showForm = true }
                            .buttonStyle(.fitcomPrimary)
                            .frame(maxWidth: 260)
                    }
                    .padding(32)
                } else {
                    EmptyStateView(
                        title: "Inicia sesión para publicar",
                        message: "Necesitas una cuenta para crear una actividad.",
                        systemImage: "lock"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.screenBackground)
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
