import CoreLocation
import SwiftUI

/// Explorar actividades disponibles, sin necesidad de sesión (US-04),
/// con filtros combinables (US-06). Encabezado propio en vez de barra de
/// navegación nativa; la primera actividad se destaca como "próximamente"
/// y el resto queda abajo en tarjetas (mismo dato, más jerarquía visual).
struct ActivityListView: View {
    @Environment(AuthStore.self) private var authStore

    let onOpenProfile: () -> Void

    @State private var allActivities: [Activity] = []
    @State private var filter: ActivityFilter = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFilterSheet = false
    @State private var nearMe = false
    @State private var location = LocationService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage, retry: load)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            searchBar
                            if !availableSports.isEmpty {
                                sportChips
                            }
                            if (nearMe || filter.maxDistanceKm != nil) && location.isDenied {
                                Text("Activa el permiso de ubicación en Ajustes para ver actividades cerca de ti.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if activities.isEmpty {
                                EmptyStateView(
                                    title: filter.isEmpty ? "Sin actividades por ahora" : "Nada con esos filtros",
                                    message: filter.isEmpty
                                        ? "Cuando alguien publique una actividad, aparecerá aquí."
                                        : "Intenta con otros filtros o límpialos.",
                                    systemImage: "figure.run.circle"
                                )
                                .padding(.top, 20)
                            } else {
                                if let featured = activities.first {
                                    NavigationLink(value: featured.id) {
                                        FeaturedActivityCard(activity: featured, distance: distance(of: featured))
                                    }
                                    .buttonStyle(.plain)
                                }

                                if activities.count > 1 {
                                    SectionHeaderView(title: "Más actividades")
                                        .padding(.top, 4)
                                    ForEach(activities.dropFirst()) { activity in
                                        NavigationLink(value: activity.id) {
                                            ActivityRowView(activity: activity, distance: distance(of: activity))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .background(Color.screenBackground)
                    .refreshable { await load() }
                }
            }
            .background(Color.screenBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { activityId in
                ActivityDetailView(activityId: activityId)
            }
            .sheet(isPresented: $showFilterSheet) {
                ActivityFilterSheet(filter: $filter)
            }
            .task { await load() }
            .onChange(of: filter.maxDistanceKm) { _, new in
                if new != nil { location.requestLocation() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.brandText)
                Text("Encuentra con quién moverte hoy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenProfile) {
                ZStack {
                    Circle().fill(Color.brandAccent.opacity(0.15)).frame(width: 46, height: 46)
                    if let urlString = authStore.profile?.avatarUrl, let url = URL(string: urlString), !urlString.isEmpty {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            avatarInitials
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    } else {
                        avatarInitials
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var avatarInitials: some View {
        Text(initials)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.brandAccent)
    }

    private var searchBar: some View {
        Button {
            showFilterSheet = true
        } label: {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(filter.isEmpty ? "Buscar por deporte, zona, nivel…" : "Filtros activos")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(filter.isEmpty ? .secondary : Color.brandAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sportChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Cerca de mí", isSelected: nearMe) {
                    nearMe.toggle()
                    if nearMe { location.requestLocation() }
                }
                FilterChip(label: "Todos", isSelected: filter.sport == nil) {
                    filter.sport = nil
                }
                ForEach(availableSports, id: \.self) { sport in
                    FilterChip(label: sport, isSelected: filter.sport?.caseInsensitiveCompare(sport) == .orderedSame) {
                        filter.sport = (filter.sport?.caseInsensitiveCompare(sport) == .orderedSame) ? nil : sport
                    }
                }
            }
        }
    }

    /// Lista ya filtrada para mostrar (US-06): el filtrado es local, sobre los
    /// datos ya cargados, para que marcar un chip se sienta instantáneo en vez
    /// de recargar toda la pantalla con cada toque.
    private var activities: [Activity] {
        let filtered = allActivities.filter { activity in
            if let sport = filter.sport, activity.sport.caseInsensitiveCompare(sport) != .orderedSame { return false }
            if let zone = filter.zone, !zone.isEmpty, !activity.zone.localizedCaseInsensitiveContains(zone) { return false }
            if let level = filter.level, activity.level != level { return false }
            if let fromDate = filter.fromDate, activity.scheduledAt < fromDate { return false }
            if let toDate = filter.toDate, activity.scheduledAt > toDate { return false }
            if let maxKm = filter.maxDistanceKm, let meters = distance(of: activity), meters > maxKm * 1000 { return false }
            if filter.maxDistanceKm != nil, location.currentLocation != nil, activity.coordinate == nil { return false }
            return true
        }
        guard nearMe, location.currentLocation != nil else { return filtered }
        // Más cercanas primero (SCRUM-36); las que no tienen coordenadas, al final.
        return filtered.sorted { (distance(of: $0) ?? .infinity) < (distance(of: $1) ?? .infinity) }
    }

    /// Distancia sólo cuando el usuario pidió verla y ya hay ubicación.
    private func distance(of activity: Activity) -> CLLocationDistance? {
        guard nearMe || filter.maxDistanceKm != nil, let origin = location.currentLocation else { return nil }
        return activity.distance(from: origin)
    }

    /// Chips de deporte: siempre a partir de la lista completa (sin filtrar),
    /// para que no desaparezcan opciones al seleccionar un deporte.
    private var availableSports: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for activity in allActivities {
            if seen.insert(activity.sport.lowercased()).inserted {
                result.append(activity.sport.capitalized)
            }
        }
        return result
    }

    private var greeting: String {
        guard let name = authStore.profile?.fullName.split(separator: " ").first else {
            return "Hola 👋"
        }
        return "Hola, \(name)"
    }

    private var initials: String {
        guard let name = authStore.profile?.fullName, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            allActivities = try await ActivityService.list()
        } catch {
            errorMessage = "No se pudieron cargar las actividades."
        }
    }
}
