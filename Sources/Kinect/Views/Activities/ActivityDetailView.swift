import SwiftUI

/// Detalle completo de una actividad: info del organizador, participantes y
/// disponibilidad, unirse/salir, enlace de coordinación y reportar
/// (US-05, US-07, US-08, US-10, US-13, US-14). Edición y cancelación
/// (US-11, US-12) sólo si quien mira es el organizador.
struct ActivityDetailView: View {
    let activityId: UUID

    @Environment(AuthStore.self) private var authStore

    @State private var activity: Activity?
    @State private var organizerName: String?
    @State private var participants: [Participant] = []
    @State private var myParticipation: Participation?
    @State private var coordinationLink: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isPerformingAction = false

    @State private var showEditSheet = false
    @State private var showCancelConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var showReportSheet = false

    private static let dateStyle: Date.FormatStyle = .dateTime.weekday(.wide).day().month().hour().minute()

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { await load() }
            } else if let activity {
                content(for: activity)
            }
        }
        .navigationTitle(activity?.title ?? "Actividad")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showEditSheet) {
            if let activity {
                ActivityFormView(editing: activity, currentCoordinationLink: coordinationLink) { updated in
                    self.activity = updated
                    Task { await loadCoordinationLink() }
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let activity {
                ReportActivityView(activityId: activity.id)
            }
        }
        .confirmationDialog(
            "¿Cancelar esta actividad?", isPresented: $showCancelConfirmation, titleVisibility: .visible
        ) {
            Button("Cancelar actividad", role: .destructive) { Task { await cancelActivity() } }
        } message: {
            Text("Dejará de aceptar participantes y se marcará como cancelada para todos.")
        }
        .confirmationDialog(
            "¿Salir de esta actividad?", isPresented: $showLeaveConfirmation, titleVisibility: .visible
        ) {
            Button("Salir", role: .destructive) { Task { await leaveActivity() } }
        } message: {
            Text("Tu lugar quedará libre para otra persona.")
        }
    }

    @ViewBuilder
    private func content(for activity: Activity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(activity.sport.capitalized).font(.title3).bold()
                    Spacer()
                    StatusBadge(status: activity.computedStatus)
                }

                if let organizerName {
                    Label("Organiza \(organizerName)", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
                }

                if let description = activity.description, !description.isEmpty {
                    Text(description)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(activity.scheduledAt.formatted(Self.dateStyle), systemImage: "calendar")
                    Label(activity.zone, systemImage: "mappin.and.ellipse")
                    Label(activity.level.label, systemImage: "figure.run")
                    if let cost = activity.estimatedCost {
                        Label(cost.formatted(.currency(code: "MXN")), systemImage: "dollarsign.circle")
                    }
                }
                .font(.subheadline)

                Divider()

                Text("Participantes (\(activity.participantCount)/\(activity.capacity))")
                    .font(.headline)
                if participants.isEmpty {
                    Text("Todavía nadie se ha unido.").foregroundStyle(.secondary)
                } else {
                    ForEach(participants) { participant in
                        Text(participant.profile.fullName)
                    }
                }

                if let coordinationLink, !coordinationLink.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coordinación").font(.headline)
                        Text("Esto te lleva fuera de FITCOM para coordinar los detalles.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let url = URL(string: coordinationLink) {
                            Link(coordinationLink, destination: url)
                        } else {
                            Text(coordinationLink)
                        }
                    }
                }

                Divider()

                actionsSection(for: activity)

                if let actionError {
                    Text(actionError).foregroundStyle(.red).font(.footnote)
                }
            }
            .padding()
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func actionsSection(for activity: Activity) -> some View {
        let isOrganizer = authStore.userId == activity.organizerId

        if isOrganizer {
            if activity.status != .cancelada {
                HStack {
                    Button("Editar") { showEditSheet = true }
                        .buttonStyle(.bordered)
                    Button("Cancelar actividad", role: .destructive) { showCancelConfirmation = true }
                        .buttonStyle(.bordered)
                }
            }
        } else if !authStore.isSignedIn {
            Text("Inicia sesión para unirte a esta actividad.")
                .foregroundStyle(.secondary)
        } else if myParticipation != nil, activity.status != .cancelada, activity.computedStatus != .finalizada {
            // (US-10) No se puede salir de una actividad ya cancelada o finalizada.
            Button("Salir de la actividad", role: .destructive) { showLeaveConfirmation = true }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
        } else if myParticipation != nil {
            Text("Ya participaste en esta actividad.")
                .foregroundStyle(.secondary)
        } else if activity.canAcceptParticipants {
            Button {
                Task { await join() }
            } label: {
                if isPerformingAction { ProgressView() } else { Text("Unirme") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPerformingAction)
        } else {
            Text("Esta actividad ya no acepta participantes.")
                .foregroundStyle(.secondary)
        }

        if authStore.isSignedIn && !isOrganizer {
            Button("Reportar actividad") { showReportSheet = true }
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let activity = try await ActivityService.detail(id: activityId)
            self.activity = activity
            async let organizer = ProfileService.fetch(id: activity.organizerId)
            async let participantsList = ParticipationService.participants(activityId: activityId)
            organizerName = try? await organizer.fullName
            participants = (try? await participantsList) ?? []
            if let userId = authStore.userId {
                myParticipation = try? await ParticipationService.myParticipation(
                    activityId: activityId, userId: userId
                )
            }
            await loadCoordinationLink()
        } catch {
            errorMessage = "No se pudo cargar la actividad."
        }
    }

    private func loadCoordinationLink() async {
        coordinationLink = try? await ActivityService.coordinationLink(activityId: activityId)
    }

    private func join() async {
        guard let userId = authStore.userId else { return }
        actionError = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await ParticipationService.join(activityId: activityId, userId: userId)
            await load()
        } catch {
            actionError = "No se pudo completar la inscripción (puede que ya no haya cupo)."
        }
    }

    private func leaveActivity() async {
        guard let participationId = myParticipation?.id else { return }
        actionError = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await ParticipationService.leave(participationId: participationId)
            await load()
        } catch {
            actionError = "No se pudo salir de la actividad."
        }
    }

    private func cancelActivity() async {
        actionError = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await ActivityService.cancel(id: activityId)
            await load()
        } catch {
            actionError = "No se pudo cancelar la actividad."
        }
    }
}
