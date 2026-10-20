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

    @State var sport = ""
    @State var title = ""
    @State var description = ""
    @State var scheduledAt = Date().addingTimeInterval(3600)
    @State var zone = ""
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
                        TextField("Deporte", text: $sport)
                    }
                    TextField("Título", text: $title)
                    DatePicker(
                        "Fecha y hora", selection: $scheduledAt, in: Date()..., displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField("Zona / ubicación", text: $zone)
                    Picker("Nivel", selection: $level) {
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
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
        guard !sport.isEmpty, !title.isEmpty, !zone.isEmpty, let capacity, capacity >= 1 else {
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
                        estimatedCost: estimatedCost
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
        _level = State(initialValue: activity.level)
        _capacityText = State(initialValue: String(activity.capacity))
        _estimatedCostText = State(initialValue: activity.estimatedCost.map { String($0) } ?? "")
        _coordinationLink = State(initialValue: currentCoordinationLink ?? "")
    }
}
