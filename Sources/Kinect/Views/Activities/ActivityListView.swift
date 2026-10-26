import CoreLocation
import SwiftUI

/// Explorar actividades disponibles, sin necesidad de sesión (US-04),
/// con filtros combinables (US-06). Encabezado propio en vez de barra de
/// navegación nativa; la primera actividad se destaca como "próximamente"
/// y el resto queda abajo en tarjetas (mismo dato, más jerarquía visual).
struct ActivityListView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(TabBarState.self) private var tabBar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onOpenProfile: () -> Void
    let refreshToken: Int

    @State private var allActivities: [Activity] = []
    @State private var filter: ActivityFilter = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFilterSheet = false
    @State private var showSearch = false
    @State private var nearMe = false
    @State private var path = NavigationPath()
    @State private var showMap = false
    @State private var selectedMapActivityId: UUID?
    @State private var places: [Place] = []
    @State private var location = LocationService.shared

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    LoadingStateView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage, retry: load)
                } else if showMap {
                    mapMode
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            searchRow
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
                    .statusBarCover()
                    .refreshable { await load() }
                }
            }
            .background(Color.screenBackground)
            .overlay {
                if showSearch {
                    GlobalSearchView(activities: allActivities, places: places) {
                        withAnimation(.easeInOut(duration: 0.2)) { showSearch = false }
                    }
                    .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { activityId in
                ActivityDetailView(activityId: activityId)
            }
            .navigationDestination(for: Place.self) { place in
                PlaceDetailView(place: place)
            }
            .navigationDestination(for: ProfileRoute.self) { PublicProfileView(userId: $0.userId) }
            .navigationDestination(for: GroupRoute.self) { GroupLoaderView(id: $0.id) }
            .sheet(isPresented: $showFilterSheet) {
                ActivityFilterSheet(filter: $filter)
            }
            .task(id: refreshToken) { await load() }
            .onAppear {
                tabBar.exploreAtRoot = path.isEmpty
                if path.isEmpty && tabBar.activeTab == .explore { tabBar.isHidden = false }
            }
            .onChange(of: path.count) { old, new in
                tabBar.exploreAtRoot = new == 0
                if tabBar.activeTab == .explore { tabBar.isHidden = new > 0 }
                if new < old { Task { await load() } }
            }
            .onChange(of: showSearch) { _, searching in
                tabBar.searchActive = searching
            }
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

    /// Barra de búsqueda + botón de filtros + conmutador Lista / Mapa (SCRUM-40).
    private var searchRow: some View {
        HStack(spacing: 10) {
            searchBar
            filterButton
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMap.toggle() }
            } label: {
                Image(systemName: showMap ? "list.bullet" : "map.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(showMap ? .white : Color.brandAccent)
                    .frame(width: 46, height: 46)
                    .background(showMap ? Color.brandAccent : Color.cardBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showMap ? "Ver lista" : "Ver mapa")
        }
    }

    private var mapMode: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchRow
            GeometryReader { geometry in
                let bottomClearance = overviewBottomClearance(in: geometry)
                let overviewHeight = min(360, max(0, geometry.size.height - bottomClearance - 10) * 0.65)
                MultiPinMapView(pins: mapPins, onSelect: openPin)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .topLeading) { mapLegend }
                    .overlay(alignment: .bottom) {
                        ZStack(alignment: .bottom) {
                            if let activity = activities.first(where: { $0.id == selectedMapActivityId }) {
                                ActivityMapOverview(
                                    activity: activity,
                                    refreshToken: path.count,
                                    onClose: { selectedMapActivityId = nil },
                                    onOpenDetails: { path.append(activity.id) }
                                )
                                .frame(height: overviewHeight)
                                .padding(.horizontal, 10)
                                .padding(.bottom, bottomClearance)
                                .transition(overviewTransition)
                                .id(activity.id)
                                .zIndex(1)
                            }
                        }
                        .animation(
                            reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0.12),
                            value: selectedMapActivityId
                        )
                    }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.screenBackground)
        .statusBarCover()
    }

    private func overviewBottomClearance(in geometry: GeometryProxy) -> CGFloat {
        guard !tabBar.isHidden else { return 10 }
        // NavigationStack/MapKit pueden extender el mapa por debajo del inset
        // de RootView. Compara posiciones reales para reservar sólo el solape.
        guard let topEdge = tabBar.topEdge else { return 90 }
        return max(10, geometry.frame(in: .global).maxY - topEdge + 12)
    }

    private var overviewTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .offset(y: 24)
            .combined(with: .scale(scale: 0.97, anchor: .bottom))
            .combined(with: .opacity)
    }

    private var mapLegend: some View {
        HStack(spacing: 12) {
            legendDot(Color.brandPrimary, "Lugares")
            legendDot(Color.brandAccent, "Actividades")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    /// Lugares curados + actividades (ya filtradas) que tienen coordenadas.
    private var mapPins: [MapPin] {
        let placePins = places.map {
            MapPin(id: "place-\($0.id)", refId: $0.id, kind: .place, coordinate: $0.coordinate,
                   title: $0.name, symbol: $0.categorySymbol)
        }
        let activityPins = activities.compactMap { activity in
            activity.coordinate.map {
                MapPin(id: "activity-\(activity.id)", refId: activity.id, kind: .activity, coordinate: $0,
                       title: activity.title, symbol: SportVisuals.symbol(for: activity.sport))
            }
        }
        return placePins + activityPins
    }

    private func openPin(_ pin: MapPin) {
        switch pin.kind {
        case .activity:
            selectedMapActivityId = pin.refId
        case .place:
            selectedMapActivityId = nil
            if let place = places.first(where: { $0.id == pin.refId }) { path.append(place) }
        }
    }

    /// Al tocar la barra se abre la búsqueda global a pantalla completa
    /// (`GlobalSearchView`); los filtros viven en su propio botón.
    private var searchBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showSearch = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("Buscar")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buscar personas, actividades, grupos y lugares")
    }

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filter.isEmpty ? Color.brandAccent : .white)
                .frame(width: 46, height: 46)
                .background(filter.isEmpty ? Color.cardBackground : Color.brandAccent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.isEmpty ? "Filtros" : "Filtros activos")
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
        isLoading = allActivities.isEmpty
        defer { isLoading = false }
        do {
            allActivities = try await ActivityService.list()
            places = (try? await PlaceService.list()) ?? places
        } catch {
            errorMessage = "No se pudieron cargar las actividades."
        }
    }
}
