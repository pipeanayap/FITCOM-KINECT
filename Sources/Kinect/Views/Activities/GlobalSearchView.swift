import SwiftUI

/// Búsqueda global de Explorar, a pantalla completa como la de Instagram:
/// al tocar la barra el resto se cubre y aquí salen personas, actividades,
/// grupos y lugares. Va dentro del `NavigationStack` de Explorar, así que los
/// resultados abren su detalle y al volver la búsqueda sigue como se dejó.
struct GlobalSearchView: View {
    let activities: [Activity]
    let places: [Place]
    let onClose: () -> Void

    private enum Scope: String, CaseIterable, Identifiable {
        case all = "Todo"
        case people = "Personas"
        case activities = "Actividades"
        case groups = "Grupos"
        case places = "Lugares"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var people: [PersonResult] = []
    @State private var groups: [CommunityGroup] = []
    @State private var isLoading = false
    @State private var failed = false
    @FocusState private var focused: Bool

    /// En "Todo" cada sección muestra pocos resultados; en su pestaña, todos.
    private var cap: Int { scope == .all ? 5 : .max }
    private var term: String { SearchService.clean(query) }
    private var hasTerm: Bool { term.count >= 2 }

    private var matchedActivities: [Activity] {
        guard hasTerm else { return [] }
        return activities.filter { activity in
            [activity.title, activity.sport, activity.zone, activity.description ?? ""]
                .contains { $0.localizedStandardContains(term) }
        }
    }

    private var matchedPlaces: [Place] {
        guard hasTerm else { return [] }
        return places.filter { place in
            [place.name, place.address ?? "", place.categoryLabel, place.sports.joined(separator: " ")]
                .contains { $0.localizedStandardContains(term) }
        }
    }

    private var hasAnyResult: Bool {
        !people.isEmpty || !groups.isEmpty || !matchedActivities.isEmpty || !matchedPlaces.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            scopeChips
            content
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { focused = true }
        .task(id: query) { await search() }
    }

    // MARK: - Barra y pestañas

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar personas, actividades, grupos…", text: $query)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Color.cardBackground, in: Capsule())

            Button("Cancelar") {
                focused = false
                onClose()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.brandAccent)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases) { item in
                    FilterChip(label: item.rawValue, isSelected: scope == item) { scope = item }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Resultados

    @ViewBuilder
    private var content: some View {
        if !hasTerm {
            hint(systemImage: "magnifyingglass",
                 title: "Busca en FITCOM",
                 message: "Personas, actividades, grupos y lugares. Escribe al menos 2 letras.")
        } else if failed && !hasAnyResult {
            hint(systemImage: "wifi.exclamationmark",
                 title: "No se pudo buscar",
                 message: "Revisa tu conexión e intenta de nuevo.")
        } else if !hasAnyResult && !isLoading {
            hint(systemImage: "magnifyingglass",
                 title: "Sin resultados",
                 message: "No encontramos nada para “\(term)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if scope == .all || scope == .people { peopleSection }
                    if scope == .all || scope == .activities { activitiesSection }
                    if scope == .all || scope == .groups { groupsSection }
                    if scope == .all || scope == .places { placesSection }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if !people.isEmpty {
            SectionHeaderView(title: "Personas")
            ForEach(people.prefix(cap)) { person in
                NavigationLink(value: ProfileRoute(userId: person.id)) { personRow(person) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var activitiesSection: some View {
        if !matchedActivities.isEmpty {
            SectionHeaderView(title: "Actividades").padding(.top, 4)
            ForEach(matchedActivities.prefix(cap)) { activity in
                NavigationLink(value: activity.id) { ActivityRowView(activity: activity) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var groupsSection: some View {
        if !groups.isEmpty {
            SectionHeaderView(title: "Grupos").padding(.top, 4)
            ForEach(groups.prefix(cap)) { group in
                NavigationLink(value: GroupRoute(id: group.id)) { GroupRowView(group: group) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var placesSection: some View {
        if !matchedPlaces.isEmpty {
            SectionHeaderView(title: "Lugares").padding(.top, 4)
            ForEach(matchedPlaces.prefix(cap)) { place in
                NavigationLink(value: place) { placeRow(place) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func personRow(_ person: PersonResult) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: person.avatarUrl.flatMap { URL(string: $0) }) {
                ZStack {
                    Circle().fill(Color.brandAccent.opacity(0.15))
                    Text(initials(person.fullName))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.brandAccent)
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(person.fullName).font(.headline).foregroundStyle(Color.brandText).lineLimit(1)
                Text("@\(person.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func placeRow(_ place: Place) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.brandPrimary.opacity(0.15))
                Image(systemName: place.categorySymbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(.headline).foregroundStyle(Color.brandText).lineLimit(1)
                Text([place.categoryLabel, place.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func hint(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline).foregroundStyle(Color.brandText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }

    // MARK: - Búsqueda en el servidor

    /// Espera a que se deje de escribir y consulta personas y grupos a la vez.
    /// `.task(id:)` cancela la tarea anterior con cada letra, así que una
    /// respuesta lenta nunca pisa a una más reciente.
    private func search() async {
        guard hasTerm else {
            people = []
            groups = []
            failed = false
            isLoading = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }
        async let foundPeople = try? SearchService.people(query)
        async let foundGroups = try? SearchService.groups(query)
        let (p, g) = await (foundPeople, foundGroups)
        guard !Task.isCancelled else { return }
        failed = p == nil && g == nil
        people = p ?? []
        groups = g ?? []
    }
}
