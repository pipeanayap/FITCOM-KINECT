import CoreLocation
import SwiftUI

/// Tarjeta de actividad: deporte, fecha, hora, zona, nivel y disponibilidad (US-04).
struct ActivityRowView: View {
    let activity: Activity
    /// Distancia en metros desde mi ubicación (SCRUM-36); `nil` = no mostrar.
    var distance: CLLocationDistance?

    private static let dateStyle: Date.FormatStyle = .dateTime.day().month(.abbreviated).hour().minute()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(SportVisuals.gradient(for: activity.sport))
                Image(systemName: SportVisuals.symbol(for: activity.sport))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(.headline)
                            .foregroundStyle(Color.brandText)
                            .lineLimit(1)
                        Text(activity.sport.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: activity.computedStatus)
                }

                HStack(spacing: 14) {
                    Label(activity.scheduledAt.formatted(Self.dateStyle), systemImage: "calendar")
                    Label(activity.zone, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    if let distance {
                        Label(DistanceFormat.text(distance), systemImage: "location")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Label(activity.level.label, systemImage: "gauge.with.dots.needle.50percent")
                    Label(
                        "\(activity.participantCount)/\(activity.capacity) · \(max(activity.spotsLeft, 0)) libres",
                        systemImage: "person.2.fill"
                    )
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.brandAccent)
            }
        }
        .cardStyle()
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
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .abierta: .brandPrimary
        case .completa: .brandWarning
        case .cancelada: .red
        case .finalizada: .secondary
        }
    }
}
