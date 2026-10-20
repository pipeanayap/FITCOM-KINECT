import SwiftUI

/// Fila de actividad: deporte, fecha, hora, zona, nivel y disponibilidad (US-04).
struct ActivityRowView: View {
    let activity: Activity

    private static let dateStyle: Date.FormatStyle = .dateTime.day().month().hour().minute()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(activity.sport.capitalized).font(.headline)
                Spacer()
                StatusBadge(status: activity.computedStatus)
            }
            Text(activity.title)
            HStack(spacing: 12) {
                Label(activity.scheduledAt.formatted(Self.dateStyle), systemImage: "calendar")
                Label(activity.zone, systemImage: "mappin.and.ellipse")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(activity.level.label, systemImage: "figure.run")
                Label(
                    "\(activity.participantCount)/\(activity.capacity) (\(max(activity.spotsLeft, 0)) libres)",
                    systemImage: "person.2"
                )
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: ActivityStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .abierta: .green
        case .completa: .orange
        case .cancelada: .red
        case .finalizada: .secondary
        }
    }
}
