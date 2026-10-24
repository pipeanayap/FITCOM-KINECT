import SwiftUI

/// Tarjeta de actividad dentro de un post, con el botón Unirme (SCRUM-45).
/// Las reglas de cupo y duplicados son las mismas que en el detalle: las
/// valida la base de datos al insertar la participación.
struct FeedActivityCard: View {
    let activity: Activity
    let isJoined: Bool
    let isMine: Bool
    let isSignedIn: Bool
    let isBusy: Bool
    let onJoin: () -> Void

    private static let dateStyle: Date.FormatStyle = .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Fmt.locale)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: activity.id) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(SportVisuals.gradient(for: activity.sport))
                        Image(systemName: SportVisuals.symbol(for: activity.sport))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(activity.title).font(.headline).foregroundStyle(Color.brandText).lineLimit(1)
                        Text(activity.scheduledAt.formatted(Self.dateStyle))
                            .font(.caption).foregroundStyle(.secondary)
                        Label(activity.zone, systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            HStack {
                Label(
                    "\(activity.participantCount)/\(activity.capacity) · \(max(activity.spotsLeft, 0)) libres",
                    systemImage: "person.2.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.brandAccent)
                Spacer()
                action
            }
        }
        .padding(14)
        .background(Color.screenBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var action: some View {
        if isMine {
            Text("Tu actividad").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        } else if isJoined {
            Label("Inscrito", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandPrimary)
        } else if activity.canAcceptParticipants && isSignedIn {
            Button("Unirme", action: onJoin)
                .buttonStyle(.fitcomPrimary(disabled: isBusy, fullWidth: false))
                .disabled(isBusy)
        } else if !activity.canAcceptParticipants {
            StatusBadge(status: activity.computedStatus)
        }
    }
}
