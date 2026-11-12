import CoreLocation
import SwiftUI

/// Tarjeta de actividad: deporte, cuándo, dónde, quién va y cuánto cupo queda
/// (US-04). Lleva las caras de quienes van (si ya se cargaron) y una barra
/// de cupo que se llena.
struct ActivityRowView: View {
    let activity: Activity
    /// Distancia en metros desde mi ubicación (SCRUM-36); `nil` = no mostrar.
    var distance: CLLocationDistance?
    var social: ActivitySocial?

    private var almostFull: Bool { activity.spotsLeft > 0 && activity.spotsLeft <= 2 }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sportTile

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.dayChip(activity.scheduledAt))
                        .metaCaps(Color.brandAccentText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // "Abierta" es lo normal y ya lo dice la barra de cupo: sólo se marca lo demás.
                    if activity.computedStatus != .abierta {
                        StatusBadge(status: activity.computedStatus)
                    }
                }

                Text(activity.title)
                    .font(.cardTitle)
                    .foregroundStyle(Color.brandText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Si no caben en una línea (zona larga, texto grande), pasan a una columna.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { whereAndLevel }
                    VStack(alignment: .leading, spacing: 3) { whereAndLevel }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        if let social, !social.attendees.isEmpty {
                            AvatarStack(people: social.attendees, total: activity.participantCount, size: 24)
                        }
                        Text("\(activity.participantCount)/\(activity.capacity)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(Fmt.freeShort(activity.spotsLeft))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(almostFull ? Color.brandWarningText : Color.brandAccentText)
                    }
                    CapacityBar(
                        filled: activity.participantCount,
                        capacity: activity.capacity,
                        tint: almostFull ? .brandWarning : .brandAccent
                    )
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var sportTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SportVisuals.gradient(for: activity.sport))
            Image(systemName: SportVisuals.symbol(for: activity.sport))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var whereAndLevel: some View {
        Label(activity.zone, systemImage: "mappin.and.ellipse")
            .lineLimit(1)
        Label(activity.level.label, systemImage: "gauge.with.dots.needle.50percent")
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        if let distance {
            Label(DistanceFormat.text(distance), systemImage: "location")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct StatusBadge: View {
    let status: ActivityStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(textColor)
    }

    private var color: Color {
        switch status {
        case .abierta: .brandPrimary
        case .completa: .brandWarning
        case .cancelada: .red
        case .finalizada: .secondary
        }
    }

    /// Texto más oscuro que el fondo del badge para que se lea (contraste >= 4.5:1).
    private var textColor: Color {
        switch status {
        case .abierta: .brandPrimaryText
        case .completa: .brandWarningText
        case .cancelada: .brandDangerText
        case .finalizada: .secondary
        }
    }
}
