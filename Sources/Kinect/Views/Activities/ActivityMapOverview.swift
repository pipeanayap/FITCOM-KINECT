import SwiftUI

/// Resumen sobre el mapa. La inscripción se confirma en el detalle completo.
struct ActivityMapOverview: View {
    let activity: Activity
    let refreshToken: Int
    let onClose: () -> Void
    let onOpenDetails: () -> Void

    @Environment(AuthStore.self) private var authStore
    @State private var isEnrolled: Bool?

    private static let dateStyle: Date.FormatStyle = .dateTime
        .day().month(.abbreviated).hour().minute().locale(Fmt.locale)

    private var isOrganizer: Bool { authStore.userId == activity.organizerId }

    private var actionTitle: String {
        guard !isOrganizer, activity.canAcceptParticipants else { return "Ver detalles" }
        if authStore.isSignedIn, isEnrolled != false { return "Ver detalles" }
        return "Unirme a la actividad"
    }

    // También vuelve a consultar al regresar del detalle, donde puede haber
    // cambiado la inscripción, y al cambiar de cuenta.
    private var participationKey: String {
        "\(activity.id)-\(authStore.userId?.uuidString ?? "guest")-\(refreshToken)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(activity.sport.capitalized, systemImage: SportVisuals.symbol(for: activity.sport))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                Spacer()
                StatusBadge(status: activity.computedStatus)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar resumen")
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.title)
                        .font(.headline)
                        .foregroundStyle(Color.brandText)
                    if let description = activity.description, !description.isEmpty {
                        Text(description)
                            .lineLimit(2)
                    }
                    Label(activity.scheduledAt.formatted(Self.dateStyle), systemImage: "calendar")
                    Label(activity.zone, systemImage: "mappin.and.ellipse")
                    Label(activity.level.label, systemImage: "gauge.with.dots.needle.50percent")
                    Label("\(max(activity.spotsLeft, 0)) lugares libres de \(activity.capacity)", systemImage: "person.2.fill")
                    if let cost = activity.estimatedCost {
                        Label("Costo estimado: \(cost.formatted(.currency(code: "MXN")))", systemImage: "dollarsign.circle")
                    }
                    if isOrganizer {
                        Label("Tú organizas esta actividad", systemImage: "person.crop.circle")
                            .foregroundStyle(Color.brandAccent)
                    } else if isEnrolled == true {
                        Label("Ya te has inscrito a esta actividad", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.brandAccent)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onOpenDetails) {
                Text(actionTitle)
            }
            .buttonStyle(.fitcomPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .task(id: participationKey) {
            isEnrolled = nil
            guard let userId = authStore.userId else { return }
            do {
                let participation = try await ParticipationService.myParticipation(
                    activityId: activity.id, userId: userId
                )
                guard !Task.isCancelled else { return }
                isEnrolled = participation != nil
            } catch {
                // Si no se puede verificar, el detalle permite reintentar antes
                // de ofrecer una inscripción que podría estar duplicada.
            }
        }
    }
}
