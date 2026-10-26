import CoreLocation
import SwiftUI

/// Selector de lugar real con autocompletado (SCRUM-35).
struct PlacePickerView: View {
    let onPick: (PickedPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearchService()
    @State private var location = LocationService.shared
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var wantsCurrent = false
    @State private var places: [Place] = []
    @State private var showManualMap = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Dirección o nombre del lugar", text: $search.query)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                        if !search.query.isEmpty {
                            Button {
                                search.query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Borrar búsqueda")
                        }
                    }
                } header: {
                    Text("Buscar lugar")
                } footer: {
                    Text("Escribe, por ejemplo, Deportiva del Estado o una dirección. Toca una opción para elegirla.")
                }

                Section {
                    Button {
                        wantsCurrent = true
                        location.requestLocation()
                        if let current = location.currentLocation { useCurrent(current) }
                    } label: {
                        Label("Usar mi ubicación actual", systemImage: "location.fill")
                    }
                    if location.isDenied {
                        Text("Activa el permiso de ubicación en Ajustes para usar esta opción.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showManualMap = true
                    } label: {
                        Label("Elegir en el mapa", systemImage: "map.fill")
                    }
                }

                if !matchingPlaces.isEmpty {
                    Section("Lugares FITCOM") {
                        ForEach(matchingPlaces) { place in
                            Button {
                                onPick(PickedPlace(
                                    name: place.name, latitude: place.latitude,
                                    longitude: place.longitude, placeId: place.id
                                ))
                                dismiss()
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name).foregroundStyle(Color.brandText)
                                        Text(place.categoryLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: place.categorySymbol).foregroundStyle(Color.brandPrimary)
                                }
                            }
                        }
                    }
                }

                if !search.suggestions.isEmpty {
                    Section("Resultados de búsqueda") {
                        ForEach(search.suggestions) { suggestion in
                            Button {
                                Task { await pick(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title).foregroundStyle(Color.brandText)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .overlay { if isResolving { ProgressView() } }
            .navigationTitle("Ubicación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .task { places = (try? await PlaceService.list()) ?? [] }
            .onAppear { search.bias(around: location.currentLocation) }
            .onChange(of: location.currentLocation) { _, new in
                search.bias(around: new)
                if wantsCurrent, let new { useCurrent(new) }
            }
            .navigationDestination(isPresented: $showManualMap) {
                ManualLocationPickerView(
                    initialCoordinate: location.currentLocation?.coordinate
                        ?? CLLocationCoordinate2D(latitude: 21.1236, longitude: -101.6820),
                    initialName: search.query.trimmingCharacters(in: .whitespacesAndNewlines)
                ) { place in
                    onPick(place)
                    dismiss()
                }
            }
        }
        .tint(.brandAccent)
    }

    /// Lugares curados que coinciden con lo escrito (todos si el campo está
    /// vacío), los más cercanos primero cuando hay ubicación.
    private var matchingPlaces: [Place] {
        let text = search.query.trimmingCharacters(in: .whitespaces)
        let matches = text.isEmpty ? places : places.filter { $0.name.localizedStandardContains(text) }
        guard let origin = location.currentLocation else { return matches }
        return matches.sorted { $0.distance(from: origin) < $1.distance(from: origin) }
    }

    private func pick(_ suggestion: PlaceSuggestion) async {
        errorMessage = nil
        isResolving = true
        defer { isResolving = false }
        do {
            onPick(try await search.resolve(suggestion))
            dismiss()
        } catch {
            errorMessage = "No se pudo encontrar ese lugar. Prueba con otro."
        }
    }

    private func useCurrent(_ current: CLLocation) {
        wantsCurrent = false
        isResolving = true
        Task {
            let place = await PlaceSearchService.place(at: current)
            isResolving = false
            onPick(place)
            dismiss()
        }
    }
}
