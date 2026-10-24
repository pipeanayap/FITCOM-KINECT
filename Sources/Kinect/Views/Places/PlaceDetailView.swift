import MapKit
import SwiftUI

/// Detalle de un lugar deportivo curado (SCRUM-40): datos, mapa, sus próximas
/// actividades y atajo para crear una actividad ahí. Esconde la barra de
/// pestañas como el detalle de actividad.
struct PlaceDetailView: View {
    let place: Place

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar

    @State private var activities: [Activity] = []
    @State private var showForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero

                if let description = place.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Color.brandText)
                        .cardStyle()
                }

                if !place.sports.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(place.sports, id: \.self) { sport in
                                Label(sport.capitalized, systemImage: SportVisuals.symbol(for: sport))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.cardBackground, in: Capsule())
                                    .foregroundStyle(Color.brandText)
                            }
                        }
                    }
                }

                locationCard

                SectionHeaderView(title: "Próximas actividades").padding(.top, 4)
                if activities.isEmpty {
                    Text("Todavía no hay actividades en este lugar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activities) { activity in
                        NavigationLink(value: activity.id) {
                            ActivityRowView(activity: activity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                createButton
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .background(Color.screenBackground)
        .statusBarCover()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .edgeSwipeBack {
            tabBar.isHidden = false
            dismiss()
        }
        .sheet(isPresented: $showForm) {
            if let userId = authStore.userId {
                ActivityFormView(
                    organizerId: userId,
                    place: place,
                    saveAction: .create { try await ActivityService.create($0) },
                    onSaved: { _ in Task { await load() } }
                )
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.brandPrimary, Color(red: 0.04, green: 0.30, blue: 0.24)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: place.categorySymbol)
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 70, y: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    tabBar.isHidden = false
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.18), in: Circle())
                }
                Spacer()
                Text(place.categoryLabel.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.75))
                Text(place.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
            .padding(20)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 8)
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let address = place.address, !address.isEmpty {
                Label {
                    Text(address)
                } icon: {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.brandAccent)
                }
                .font(.subheadline)
            }
            MapPreview(coordinate: place.coordinate, title: place.name)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                item.name = place.name
                item.openInMaps()
            } label: {
                Label("Abrir en Mapas", systemImage: "map.fill")
            }
            .buttonStyle(.fitcomSecondary(tint: .brandAccent))
        }
        .cardStyle()
    }

    @ViewBuilder
    private var createButton: some View {
        if authStore.isSignedIn {
            Button("Crear actividad aquí") { showForm = true }
                .buttonStyle(.fitcomPrimary)
        } else {
            Text("Inicia sesión para crear una actividad en este lugar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        activities = (try? await PlaceService.upcomingActivities(placeId: place.id)) ?? []
    }
}
