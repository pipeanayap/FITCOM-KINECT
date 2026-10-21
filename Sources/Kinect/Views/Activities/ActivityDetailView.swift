import SwiftUI

/// Detalle completo de una actividad: info del organizador, participantes y
/// disponibilidad, unirse/salir, enlace de coordinación y reportar
/// (US-05, US-07, US-08, US-10, US-13, US-14). Edición y cancelación
/// (US-11, US-12) sólo si quien mira es el organizador. Encabezado a toda
/// anchura + barra de acción fija abajo, estilo "boleto de evento".
struct ActivityDetailView: View {
    let activityId: UUID

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

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
                // Sólo aquí se esconde la barra nativa: el encabezado a toda
                // anchura trae su propio botón de regresar. En carga/error
                // seguimos con la barra normal para poder salir de la pantalla.
                content(for: activity)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
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
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero(for: activity)

                    if let description = activity.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Color.brandText)
                            .cardStyle()
                    }

                    HStack(spacing: 10) {
                        infoChip(icon: "gauge.with.dots.needle.50percent", label: "Nivel", value: activity.level.label)
                        infoChip(icon: "calendar", label: "Fecha", value: activity.scheduledAt.formatted(.dateTime.day().month(.abbreviated)))
                        infoChip(icon: "clock", label: "Hora", value: activity.scheduledAt.formatted(.dateTime.hour().minute()))
                    }

                    infoRow(icon: "mappin.and.ellipse", text: activity.zone)
                        .cardStyle()

                    if let cost = activity.estimatedCost {
                        infoRow(icon: "dollarsign.circle.fill", text: "Costo estimado: \(cost.formatted(.currency(code: "MXN")))")
                            .cardStyle()
                    }

                    participantsCard(for: activity)

                    if let coordinationLink, !coordinationLink.isEmpty {
                        coordinationCard(link: coordinationLink)
                    }

                    if authStore.isSignedIn && authStore.userId != activity.organizerId {
                        Button {
                            showReportSheet = true
                        } label: {
                            Label("Reportar actividad", systemImage: "flag.fill")
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                    }

                    if let actionError {
                        Label(actionError, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.horizontal, 4)
                    }

                    // Deja espacio para que la barra fija de abajo no tape el último elemento.
                    Color.clear.frame(height: 70)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .background(Color.screenBackground)
            .refreshable { await load() }

            StickyActionBar { actionBarContent(for: activity) }
        }
    }

    @ViewBuilder
    private func hero(for activity: Activity) -> some View {
        ZStack(alignment: .topLeading) {
            SportVisuals.gradient(for: activity.sport)
            Image(systemName: SportVisuals.symbol(for: activity.sport))
                .font(.system(size: 130))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 80, y: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    Spacer()
                    StatusBadge(status: activity.computedStatus)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.sport.capitalized)
                        .font(.caption.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(activity.title)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let organizerName {
                        Label("Organiza \(organizerName)", systemImage: "person.crop.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 8)
    }

    private func infoChip(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color.brandAccent)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.brandText)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle(padding: 0)
    }

    private func infoRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.brandAccent)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func participantsCard(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Participantes (\(activity.participantCount)/\(activity.capacity))")
                .font(.headline)
                .foregroundStyle(Color.brandText)
            if participants.isEmpty {
                Text("Todavía nadie se ha unido.").foregroundStyle(.secondary)
            } else {
                ForEach(participants) { participant in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 32, height: 32)
                            if let urlString = participant.profile.avatarUrl, let url = URL(string: urlString), !urlString.isEmpty {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    participantInitials(participant)
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            } else {
                                participantInitials(participant)
                            }
                        }
                        Text(participant.profile.fullName)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func participantInitials(_ participant: Participant) -> some View {
        Text(initials(for: participant.profile.fullName))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }

    private func coordinationCard(link: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Coordinación", systemImage: "link").font(.headline).foregroundStyle(Color.brandText)
            Text("Esto te lleva fuera de FITCOM para coordinar los detalles.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let url = URL(string: link) {
                Link(link, destination: url)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.brandAccent)
            } else {
                Text(link)
            }
        }
        .cardStyle()
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    @ViewBuilder
    private func actionBarContent(for activity: Activity) -> some View {
        let isOrganizer = authStore.userId == activity.organizerId

        if isOrganizer {
            if activity.status != .cancelada {
                HStack(spacing: 10) {
                    Button("Editar") { showEditSheet = true }
                        .buttonStyle(.fitcomInk)
                    Button("Cancelar") { showCancelConfirmation = true }
                        .buttonStyle(.fitcomSecondary(tint: .red))
                    Spacer()
                }
            } else {
                calloutText("Esta actividad está cancelada.", icon: "xmark.circle.fill")
            }
        } else if !authStore.isSignedIn {
            calloutBar("Inicia sesión para unirte a esta actividad.", icon: "lock.fill")
        } else if myParticipation != nil, activity.status != .cancelada, activity.computedStatus != .finalizada {
            // (US-10) No se puede salir de una actividad ya cancelada o finalizada.
            HStack {
                Label("Ya estás inscrito", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                Spacer()
                Button("Salir") { showLeaveConfirmation = true }
                    .buttonStyle(.fitcomSecondary(tint: .red))
                    .disabled(isPerformingAction)
            }
        } else if myParticipation != nil {
            calloutBar("Ya participaste en esta actividad.", icon: "checkmark.circle.fill")
        } else if activity.canAcceptParticipants {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(max(activity.spotsLeft, 0)) lugares libres")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("de \(activity.capacity) totales")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await join() }
                } label: {
                    if isPerformingAction { ProgressView().tint(.white) } else { Text("Unirme") }
                }
                .buttonStyle(.fitcomPrimary(disabled: isPerformingAction, fullWidth: false))
                .disabled(isPerformingAction)
            }
        } else {
            calloutBar("Esta actividad ya no acepta participantes.", icon: "xmark.circle.fill")
        }
    }

    private func calloutText(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func calloutBar(_ text: String, icon: String) -> some View {
        HStack {
            calloutText(text, icon: icon)
            Spacer()
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
