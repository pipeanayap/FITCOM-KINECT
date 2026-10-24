import MapKit
import SwiftUI

/// Formulario para crear (US-03) o editar (US-11) una actividad. Comparte el
/// mismo diseño porque piden los mismos campos; sólo cambia qué se hace con
/// ellos al guardar.
struct ActivityFormView: View {
    enum SaveAction {
        case create((NewActivity) async throws -> Activity)
        case edit(currentParticipantCount: Int, save: (ActivityEdit) async throws -> Activity)
    }

    let organizerId: UUID
    let saveAction: SaveAction
    let onSaved: (Activity) -> Void

    @Environment(\.dismiss) private var dismiss

    @State var sport = SportVisuals.canonicalSports[0]
    @State var title = ""
    @State var description = ""
    @State var scheduledAt = Date().addingTimeInterval(3600)
    @State var zone = ""
    @State var latitude: Double?
    @State var longitude: Double?
    @State var placeId: UUID?
    @State var groupId: UUID?
    @State private var myGroups: [CommunityGroup] = []
    @State private var showPlacePicker = false
    @State var level: ActivityLevel = .cualquierNivel
    @State var capacityText = "4"
    @State var estimatedCostText = ""
    @State var coordinationLink = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Qué, cuándo y dónde") {
                    // El deporte no está entre los campos que US-11 permite
                    // editar; se fija al crear la actividad.
                    if isEditing {
                        LabeledContent("Deporte", value: sport.capitalized)
                    } else {
                        Picker("Deporte", selection: $sport) {
                            ForEach(SportVisuals.canonicalSports, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("Título", text: $title)
                    DatePicker(
                        "Fecha y hora", selection: $scheduledAt, in: Date()..., displayedComponents: [.date, .hourAndMinute]
                    )
                    Button {
                        showPlacePicker = true
                    } label: {
                        HStack {
                            Label(zone.isEmpty ? "Elegir ubicación" : zone, systemImage: "mappin.and.ellipse")
                                .foregroundStyle(zone.isEmpty ? Color.brandAccent : Color.brandText)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let latitude, let longitude {
                        MapPreview(
                            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            title: zone
                        )
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Picker("Nivel", selection: $level) {
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                    }
                    // Publicar dentro de un grupo propio (SCRUM-41); sólo al crear.
                    if !isEditing && !myGroups.isEmpty {
                        Picker("Grupo", selection: $groupId) {
                            Text("Ninguno").tag(UUID?.none)
                            ForEach(myGroups) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }

                Section("Cupo") {
                    TextField("Cupo total", text: $capacityText)
                        .keyboardType(.numberPad)
                    if case .edit(let currentParticipantCount, _) = saveAction, currentParticipantCount > 0 {
                        Text("Ya hay \(currentParticipantCount) persona(s) inscritas; el cupo no puede ser menor.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Opcional") {
                    TextField("Descripción", text: $description, axis: .vertical)
                    TextField("Costo estimado", text: $estimatedCostText)
                        .keyboardType(.decimalPad)
                }

                // (US-13) No es parte del formulario de creación (US-03 no lo
                // menciona); se ofrece sólo al editar, ya con la actividad publicada.
                if isEditing {
                    Section("Coordinación") {
                        TextField("Enlace externo (opcional)", text: $coordinationLink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? "Editar actividad" : "Nueva actividad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Guardar") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .tint(.brandAccent)
        .task { myGroups = (try? await GroupService.myGroups(userId: organizerId)) ?? [] }
        .sheet(isPresented: $showPlacePicker) {
            PlacePickerView { place in
                zone = place.name
                latitude = place.latitude
                longitude = place.longitude
                placeId = place.placeId
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = saveAction { return true }
        return false
    }

    private var capacity: Int? { Int(capacityText) }

    private var estimatedCost: Double? {
        estimatedCostText.isEmpty ? nil : Double(estimatedCostText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard !sport.isEmpty, !title.isEmpty, !zone.isEmpty, isEditing || latitude != nil, let capacity, capacity >= 1 else {
            return false
        }
        guard scheduledAt > Date() else { return false }
        if case .edit(let currentParticipantCount, _) = saveAction, capacity < currentParticipantCount {
            return false
        }
        if !estimatedCostText.isEmpty && estimatedCost == nil { return false }
        return true
    }

    private func save() async {
        guard let capacity else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let saved: Activity
            switch saveAction {
            case .create(let create):
                saved = try await create(
                    NewActivity(
                        organizerId: organizerId,
                        sport: sport,
                        title: title,
                        description: description.isEmpty ? nil : description,
                        scheduledAt: scheduledAt,
                        zone: zone,
                        level: level,
                        capacity: capacity,
                        estimatedCost: estimatedCost,
                        latitude: latitude,
                        longitude: longitude,
                        placeId: placeId,
                        groupId: groupId
                    )
                )
            case .edit(_, let edit):
                saved = try await edit(
                    ActivityEdit(
                        sport: sport,
                        title: title,
                        description: description.isEmpty ? nil : description,
                        scheduledAt: scheduledAt,
                        zone: zone,
                        level: level,
                        capacity: capacity,
                        estimatedCost: estimatedCost,
                        latitude: latitude,
                        longitude: longitude,
                        placeId: placeId,
                        groupId: groupId,
                        coordinationLink: coordinationLink.isEmpty ? nil : coordinationLink
                    )
                )
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la actividad. Revisa los datos e intenta de nuevo."
        }
    }
}

extension ActivityFormView {
    /// Precarga los campos al editar una actividad existente (US-11).
    /// `currentCoordinationLink` se consulta aparte (ver
    /// `ActivityService.coordinationLink`), porque la actividad ya no trae
    /// ese campo directamente (US-13).
    init(editing activity: Activity, currentCoordinationLink: String?, onSaved: @escaping (Activity) -> Void) {
        self.organizerId = activity.organizerId
        self.saveAction = .edit(currentParticipantCount: activity.participantCount) { edit in
            try await ActivityService.update(id: activity.id, with: edit)
        }
        self.onSaved = onSaved
        _sport = State(initialValue: activity.sport)
        _title = State(initialValue: activity.title)
        _description = State(initialValue: activity.description ?? "")
        _scheduledAt = State(initialValue: activity.scheduledAt)
        _zone = State(initialValue: activity.zone)
        _latitude = State(initialValue: activity.latitude)
        _longitude = State(initialValue: activity.longitude)
        _placeId = State(initialValue: activity.placeId)
        _groupId = State(initialValue: activity.groupId)
        _level = State(initialValue: activity.level)
        _capacityText = State(initialValue: String(activity.capacity))
        _estimatedCostText = State(initialValue: activity.estimatedCost.map { String($0) } ?? "")
        _coordinationLink = State(initialValue: currentCoordinationLink ?? "")
    }
}

extension ActivityFormView {
    /// Crear una actividad con un lugar curado ya elegido (SCRUM-40): precarga
    /// zona, coordenadas y, si coincide con la lista de deportes, el deporte.
    init(
        organizerId: UUID, place: Place, saveAction: SaveAction, onSaved: @escaping (Activity) -> Void
    ) {
        self.organizerId = organizerId
        self.saveAction = saveAction
        self.onSaved = onSaved
        _zone = State(initialValue: place.name)
        _latitude = State(initialValue: place.latitude)
        _longitude = State(initialValue: place.longitude)
        _placeId = State(initialValue: place.id)
        if let sport = place.sports.compactMap({ placeSport in
            SportVisuals.canonicalSports.first {
                $0.compare(placeSport, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }).first {
            _sport = State(initialValue: sport)
        }
    }
}

extension ActivityFormView {
    /// Crear una actividad dentro de un grupo ya elegido (SCRUM-41).
    init(
        organizerId: UUID, group: CommunityGroup, saveAction: SaveAction,
        onSaved: @escaping (Activity) -> Void
    ) {
        self.organizerId = organizerId
        self.saveAction = saveAction
        self.onSaved = onSaved
        _groupId = State(initialValue: group.id)
        _myGroups = State(initialValue: [group])
        if let sport = SportVisuals.canonicalSports.first(where: {
            $0.compare(group.sport ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            _sport = State(initialValue: sport)
        }
    }
}
