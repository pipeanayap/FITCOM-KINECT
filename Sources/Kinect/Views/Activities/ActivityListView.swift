import CoreLocation
import SwiftUI

/// Explorar actividades disponibles, sin necesidad de sesión (US-04),
/// con búsqueda, accesos rápidos y filtros combinables (US-06).
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
    @State private var thisWeek = false
    @State private var path = NavigationPath()
    @State private var showMap = false
    @State private var selectedMapActivityId: UUID?
    @State private var places: [Place] = []
    /// Caras de quienes organizan y van, por actividad (se cargan después del listado).
    @State private var social: [UUID: ActivitySocial] = [:]
    /// Cuántas actividades de la lista larga se pintan; "Mostrar más" sube el tope.
    @State private var visibleCount = 30
    @State private var location = LocationService.shared

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    loadingSkeleton
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage, retry: load)
                } else if showMap {
                    mapMode
                } else {
                    ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            searchRow

                            if let featured = upcomingActivities.first {
                                NavigationLink(value: featured.id) {
                                    FeaturedActivityCard(activity: featured, distance: distance(of: featured), social: social[featured.id])
                                }
                                .buttonStyle(.fitcomPressable)
                            }

                            quickActions

                            if thisWeek {
                                Text("Mostrando actividades de los próximos 7 días.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if (nearMe || filter.maxDistanceKm != nil) && location.isDenied {
                                Text("Activa el permiso de ubicación en Ajustes para ver actividades cerca de ti.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if !upcomingActivities.isEmpty {
                                HStack {
                                    SectionHeaderView(title: "Próximas actividades")
                                    Spacer()
                                    Button("Ver todas") {
                                        withAnimation { scroll.scrollTo("activity-list", anchor: .top) }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.brandAccentText)
                                }
                                upcomingCarousel
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeaderView(title: "Explorar por deporte")
                                sportChips
                            }
                            .id("activity-list")

                            if activities.isEmpty {
                                EmptyStateView(
                                    title: hasActiveFilters ? "Nada con esos filtros" : "Sin actividades por ahora",
                                    message: !hasActiveFilters
                                        ? "Cuando alguien publique una actividad, aparecerá aquí."
                                        : "Intenta con otros filtros o límpialos.",
                                    systemImage: "figure.run.circle",
                                    actionTitle: hasActiveFilters ? nil : "Crear actividad",
                                    action: hasActiveFilters ? nil : { tabBar.requestedCreate = .activity }
                                )
                                .padding(.top, 20)
                                if hasActiveFilters {
                                    Button("Limpiar filtros") {
                                        filter = .empty
                                        thisWeek = false
                                        nearMe = false
                                    }
                                    .buttonStyle(.fitcomSecondary(tint: .brandAccent))
                                    .frame(maxWidth: .infinity)
                                }
                            } else {
                                SectionHeaderView(title: nearMe && location.currentLocation != nil ? "Actividades cercanas" : "Todas las actividades")
                                LazyVStack(spacing: 12) {
                                    ForEach(activities.prefix(visibleCount)) { activity in
                                        NavigationLink(value: activity.id) {
                                            ActivityRowView(activity: activity, distance: distance(of: activity), social: social[activity.id])
                                        }
                                        .buttonStyle(.fitcomPressable)
                                    }
                                }
                                if activities.count > visibleCount {
                                    Button("Mostrar más (\(activities.count - visibleCount))") {
                                        visibleCount += 30
                                    }
                                    .buttonStyle(.fitcomSecondary(tint: .brandAccent))
                                    .frame(maxWidth: .infinity)
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
            }
            .animation(.easeOut(duration: 0.18), value: isLoading)
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
            .onChange(of: tabBar.requestedActivityId) { _, id in
                guard let id else { return }
                tabBar.requestedActivityId = nil
                path.append(id)
            }
            .onChange(of: filter.maxDistanceKm) { _, new in
                if new != nil { location.requestLocation() }
            }
            .onChange(of: filter) { visibleCount = 30 }
            .onChange(of: thisWeek) { visibleCount = 30 }
            .onChange(of: nearMe) { visibleCount = 30 }
        }
    }

    /// Mientras carga por primera vez: encabezado real y tarjetas esqueleto, para
    /// que la pantalla ya tenga su forma y el contenido entre con un fundido.
    private var loadingSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchRow
                SkeletonList(count: 4)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollDisabled(true)
        .background(Color.screenBackground)
        .statusBarCover()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.displayXL)
                    .foregroundStyle(Color.brandText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(Brand.tagline) hoy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenProfile) {
                AvatarView(url: authStore.profile?.avatarUrl, name: authStore.profile?.fullName ?? "", size: 46)
            }
            .accessibilityLabel("Abrir menú de perfil")
            .buttonStyle(.fitcomPressable)
        }
        .padding(.top, 4)
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
            .buttonStyle(.fitcomPressable)
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
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.fitcomPressable)
        .accessibilityLabel("Buscar personas, actividades, grupos y lugares")
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction("Cerca de mí", icon: "location.fill", selected: nearMe) {
                nearMe.toggle()
                if nearMe { location.requestLocation() }
            }
            quickAction("Esta semana", icon: "calendar", selected: thisWeek) {
                thisWeek.toggle()
            }
            quickAction("Ver mapa", icon: "map.fill", selected: false) {
                withAnimation(.easeInOut(duration: 0.2)) { showMap = true }
            }
        }
    }

    private func quickAction(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? .white : Color.brandAccent)
                    .frame(width: 40, height: 40)
                    .background(selected ? Color.brandAccent : Color.brandAccent.opacity(0.12), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.fitcomPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(title == "Esta semana" ? "Filtra los próximos siete días" : "")
    }

    private var upcomingCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(upcomingActivities.prefix(8))) { activity in
                    NavigationLink(value: activity.id) {
                        UpcomingActivityCard(activity: activity, social: social[activity.id])
                    }
                    .buttonStyle(.fitcomPressable)
                }
            }
            .padding(.vertical, 2)
        }
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
        .buttonStyle(.fitcomPressable)
        .accessibilityLabel(filter.isEmpty ? "Filtros" : "Filtros activos")
    }

    private var sportChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let filtered = allActivities.filter { activity in
            if thisWeek && activity.scheduledAt > weekEnd { return false }
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
        let distances = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, distance(of: $0) ?? .infinity) })
        return filtered.sorted { (distances[$0.id] ?? .infinity) < (distances[$1.id] ?? .infinity) }
    }

    private var upcomingActivities: [Activity] {
        activities.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var hasActiveFilters: Bool {
        !filter.isEmpty || thisWeek
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

    private func load() async {
        errorMessage = nil
        isLoading = allActivities.isEmpty
        defer { isLoading = false }
        do {
            allActivities = try await ActivityService.list()
            // Las caras llegan después, sin hacer esperar al listado.
            let loaded = allActivities
            Task { social = await ActivitySocialService.load(for: Array(loaded.prefix(60))) }
            do {
                places = try await PlaceService.list()
            } catch {
                AppLog.activities.error("Cargar lugares falló: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            AppLog.activities.error("Cargar actividades falló: \(error.localizedDescription, privacy: .public)")
            errorMessage = ErrorText.describe(error, fallback: "No se pudieron cargar las actividades.")
        }
    }
}

/// Tarjeta compacta para recorrer próximas actividades sin salir de Explorar.
private struct UpcomingActivityCard: View {
    let activity: Activity
    var social: ActivitySocial?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                SportVisuals.gradient(for: activity.sport)
                Image(systemName: SportVisuals.symbol(for: activity.sport))
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .rotationEffect(.degrees(-10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                Text(Fmt.dayChip(activity.scheduledAt))
                    .metaCaps(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.22), in: Capsule())
                    .padding(10)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(activity.title)
                .font(.cardTitle)
                .foregroundStyle(Color.brandText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)

            HStack(spacing: 6) {
                if let social, !social.attendees.isEmpty {
                    AvatarStack(people: social.attendees, total: activity.participantCount, size: 22)
                }
                Spacer(minLength: 0)
                Text(Fmt.freeShort(activity.spotsLeft))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandAccentText)
            }
            CapacityBar(filled: activity.participantCount, capacity: activity.capacity)
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }
}
