import MapKit
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
    @State private var organizerAvatar: String?
    @State private var participants: [Participant] = []
    @State private var myParticipation: Participation?
    @State private var coordinationLink: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isPerformingAction = false
    /// Si te pidieron iniciar sesión para unirte, al volver ya con sesión se completa la inscripción.
    @State private var joinAfterSignIn = false
    @State private var joinedToken = 0
    @State private var leftToken = 0

    @State private var showEditSheet = false
    @State private var showCancelConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var showReportSheet = false
    @State private var groupName: String?
    @Environment(TabBarState.self) private var tabBar

    private static let dateStyle: Date.FormatStyle = .dateTime.weekday(.wide).day().month().hour().minute().locale(Fmt.locale)

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
        .task(id: authStore.userId) { await load() }
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
        }
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
        .onChange(of: authStore.isSignedIn) { _, signedIn in
            // Iniciaste sesión desde "Unirme": se completa la inscripción sin pedirte otro toque.
            guard signedIn, joinAfterSignIn else { return }
            joinAfterSignIn = false
            Task {
                await load()
                if myParticipation == nil, activity?.canAcceptParticipants == true { await join() }
            }
        }
        .sensoryFeedback(.success, trigger: joinedToken)
        .sensoryFeedback(.impact(weight: .light), trigger: leftToken)
        .animation(.easeOut(duration: 0.2), value: myParticipation?.id)
        .confirmationDialog(
            "¿Cancelar esta actividad?", isPresented: $showCancelConfirmation, titleVisibility: .visible
        ) {
            Button("Cancelar actividad", role: .destructive) { Task { await cancelActivity() } }
        } message: {
            Text("Dejará de aceptar participantes y se marcará como cancelada para todos.")
        }
        .confirmationDialog(
            "¿Cancelar tu inscripción?", isPresented: $showLeaveConfirmation, titleVisibility: .visible
        ) {
            Button("Cancelar inscripción", role: .destructive) { Task { await leaveActivity() } }
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
                        infoChip(icon: "calendar", label: "Fecha", value: activity.scheduledAt.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale)))
                        infoChip(icon: "clock", label: "Hora", value: activity.scheduledAt.formatted(.dateTime.hour().minute().locale(Fmt.locale)))
                    }

                    locationCard(for: activity)

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
            .statusBarCover()
            .refreshable { await load() }

            if !canManage(activity) || activity.status == .cancelada {
                StickyActionBar { actionBarContent(for: activity) }
            }
        }
    }

    @ViewBuilder
    private func hero(for activity: Activity) -> some View {
        ZStack(alignment: .topLeading) {
            SportVisuals.gradient(for: activity.sport)
            Image(systemName: SportVisuals.symbol(for: activity.sport))
                .font(.system(size: 190, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12))
                .offset(x: 70, y: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // La barra vuelve al empezar el regreso, no cuando termina la animación.
                    Button { tabBar.isHidden = false; dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.22), in: Circle())
                    }
                    .buttonStyle(.fitcomPressable)
                    .accessibilityLabel("Volver")
                    Spacer()
                    if activity.computedStatus != .abierta { StatusBadge(status: activity.computedStatus) }
                    if canManage(activity) {
                        // Editar/cancelar van en un menú para no tocarlos por error.
                        Menu {
                            Button { showEditSheet = true } label: {
                                Label("Editar actividad", systemImage: "pencil")
                            }
                            Button(role: .destructive) { showCancelConfirmation = true } label: {
                                Label("Cancelar actividad", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.22), in: Circle())
                        }
                        .accessibilityLabel("Más opciones")
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        heroChip(Fmt.dayChip(activity.scheduledAt))
                        heroChip(activity.sport)
                    }
                    Text(activity.title)
                        .font(.displayXL)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    if let organizerName {
                        HStack(spacing: 8) {
                            AvatarView(url: organizerAvatar, name: organizerName, size: 28)
                            Text("Organiza \(organizerName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                        }
                    }
                    if let groupName {
                        Label("Grupo \(groupName)", systemImage: "person.3.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    CapacityBar(
                        filled: activity.participantCount,
                        capacity: activity.capacity,
                        tint: .white,
                        track: .white.opacity(0.28),
                        height: 8
                    )
                    .padding(.top, 4)
                    HStack {
                        if !participants.isEmpty {
                            AvatarStack(
                                people: participants.map { Attendee(name: $0.profile.fullName, avatarUrl: $0.profile.avatarUrl) },
                                total: activity.participantCount, size: 28, ring: .white
                            )
                        }
                        Spacer()
                        Text("\(activity.participantCount)/\(activity.capacity) · \(Fmt.freeShort(activity.spotsLeft))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: DS.heroRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private func heroChip(_ text: String) -> some View {
        Text(text)
            .metaCaps(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.22), in: Capsule())
    }

    private func infoChip(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.brandAccent)
            Text(value)
                .font(.cardTitle)
                .foregroundStyle(Color.brandText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label).metaCaps()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
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

    /// Lugar de la actividad con mapa y salto a la app Mapas (SCRUM-37).
    /// Las actividades anteriores a SCRUM-35 no tienen coordenadas: sólo texto.
    @ViewBuilder
    private func locationCard(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(icon: "mappin.and.ellipse", text: activity.zone)
            if let coordinate = activity.coordinate {
                MapPreview(coordinate: coordinate, title: activity.zone)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = activity.zone
                    item.openInMaps()
                } label: {
                    Label("Abrir en Mapas", systemImage: "map.fill")
                }
                .buttonStyle(.fitcomSecondary(tint: .brandAccent))
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func participantsCard(for activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quién va")
                .font(.displayM)
                .foregroundStyle(Color.brandText)
            if participants.isEmpty {
                Text("Todavía nadie se ha unido. Sé la primera persona.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(participants) { participant in
                            VStack(spacing: 6) {
                                AvatarView(url: participant.profile.avatarUrl, name: participant.profile.fullName, size: 56)
                                Text(participant.profile.fullName.split(separator: " ").first.map(String.init) ?? participant.profile.fullName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.brandText)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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

    /// Organizador de una actividad todavía no cancelada (US-11, US-12).
    private func canManage(_ activity: Activity) -> Bool {
        authStore.userId == activity.organizerId && activity.status != .cancelada
    }

    @ViewBuilder
    private func actionBarContent(for activity: Activity) -> some View {
        let isOrganizer = authStore.userId == activity.organizerId

        if isOrganizer {
            if activity.status != .cancelada {
                // Editar y cancelar viven en el menú ⋯ del encabezado.
                EmptyView()
            } else {
                calloutText("Esta actividad está cancelada.", icon: "xmark.circle.fill")
            }
        } else if !authStore.isSignedIn {
            VStack(alignment: .leading, spacing: 10) {
                calloutBar("Inicia sesión para unirte a esta actividad.", icon: "lock.fill")
                Button("Iniciar sesión") {
                    joinAfterSignIn = true
                    tabBar.requestedAuthReason = "Inicia sesión para unirte a esta actividad."
                }
                .buttonStyle(.fitcomPrimary(disabled: false, fullWidth: false))
            }
        } else if myParticipation != nil, activity.status != .cancelada, activity.computedStatus != .finalizada {
            // (US-10) No se puede salir de una actividad ya cancelada o finalizada.
            VStack(alignment: .leading, spacing: 10) {
                Label("Ya te has inscrito a esta actividad", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                Button("Cancelar inscripción") { showLeaveConfirmation = true }
                    .buttonStyle(.fitcomSecondary(tint: .red))
                    .disabled(isPerformingAction)
            }
        } else if myParticipation != nil {
            calloutBar("Ya participaste en esta actividad.", icon: "checkmark.circle.fill")
        } else if activity.canAcceptParticipants {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.spotsFree(activity.spotsLeft))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: activity.spotsLeft)
                    CapacityBar(filled: activity.participantCount, capacity: activity.capacity)
                        .frame(width: 130)
                        .padding(.top, 2)
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
        isLoading = activity == nil
        defer { isLoading = false }
        do {
            let activity = try await ActivityService.detail(id: activityId)
            self.activity = activity
            if let groupId = activity.groupId {
                groupName = try? await GroupService.detail(id: groupId).name
            }
            async let organizer = ProfileService.fetch(id: activity.organizerId)
            async let participantsList = ParticipationService.participants(activityId: activityId)
            let organizerProfile = try? await organizer
            organizerName = organizerProfile?.fullName
            organizerAvatar = organizerProfile?.avatarUrl
            participants = (try? await participantsList) ?? []
            if let userId = authStore.userId {
                myParticipation = try await ParticipationService.myParticipation(
                    activityId: activityId, userId: userId
                )
            } else {
                myParticipation = nil
            }
            await loadCoordinationLink()
        } catch {
            errorMessage = ErrorText.describe(error, fallback: "No se pudo cargar la actividad.")
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
            joinedToken += 1
        } catch {
            AppLog.activities.error("Unirse falló: \(error.localizedDescription, privacy: .public)")
            await load()
            if let current = activity, !current.canAcceptParticipants {
                actionError = "Esta actividad ya no tiene lugares disponibles."
            } else {
                actionError = ErrorText.describe(error, fallback: "No se pudo completar la inscripción. Intenta de nuevo.")
            }
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
            leftToken += 1
        } catch {
            actionError = ErrorText.describe(error, fallback: "No se pudo salir de la actividad.")
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
