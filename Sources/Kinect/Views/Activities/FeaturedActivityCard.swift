import CoreLocation
import SwiftUI

/// Tarjeta destacada para la actividad más próxima: mismo dato que ya trae
/// el listado (US-04), sólo con más peso visual. Sustituye la fotografía
/// real (que no existe en el backlog) por un degradado del color del
/// deporte y su ícono en grande.
struct FeaturedActivityCard: View {
    let activity: Activity
    /// Distancia en metros desde mi ubicación (SCRUM-36); `nil` = no mostrar.
    var distance: CLLocationDistance?

    private static let dateStyle: Date.FormatStyle = .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SportVisuals.gradient(for: activity.sport)

            Image(systemName: SportVisuals.symbol(for: activity.sport))
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 70, y: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 10) {
                Text("PRÓXIMAMENTE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.75))
                Text(activity.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 14) {
                    Label(activity.scheduledAt.formatted(Self.dateStyle), systemImage: "calendar")
                    Label(activity.zone, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    if let distance {
                        Label(DistanceFormat.text(distance), systemImage: "location")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

                HStack {
                    Label("\(max(activity.spotsLeft, 0)) lugares libres", systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: Capsule())
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}
