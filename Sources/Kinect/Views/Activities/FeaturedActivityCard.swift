import CoreLocation
import SwiftUI

/// Tarjeta héroe de la actividad más próxima: degradado del deporte (sustituye
/// a una foto, que no existe en el backlog), título grande, quién organiza y
/// quiénes van, y la barra de cupo.
struct FeaturedActivityCard: View {
    let activity: Activity
    /// Distancia en metros desde mi ubicación (SCRUM-36); `nil` = no mostrar.
    var distance: CLLocationDistance?
    var social: ActivitySocial?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SportVisuals.gradient(for: activity.sport)

            Image(systemName: SportVisuals.symbol(for: activity.sport))
                .font(.system(size: 170, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12))
                .offset(x: 60, y: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Oscurece un poco abajo para que el texto blanco siempre se lea.
            LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    chip(Fmt.dayChip(activity.scheduledAt))
                    chip(activity.sport)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Text(activity.title)
                    .font(.displayL)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 12) {
                    Label(activity.zone, systemImage: "mappin.and.ellipse").lineLimit(1)
                    if let distance {
                        Label(DistanceFormat.text(distance), systemImage: "location")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))

                HStack(spacing: 8) {
                    if let social, !social.attendees.isEmpty {
                        AvatarStack(people: social.attendees, total: activity.participantCount, size: 28, ring: .white)
                    }
                    if let name = social?.organizer?.name.split(separator: " ").first {
                        Text("\(name) organiza")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.spotsFree(activity.spotsLeft))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                }

                CapacityBar(
                    filled: activity.participantCount,
                    capacity: activity.capacity,
                    tint: .white,
                    track: .white.opacity(0.28)
                )
            }
            .padding(20)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: DS.heroRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .metaCaps(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.22), in: Capsule())
    }
}
