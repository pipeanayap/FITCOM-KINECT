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

    var body: some View {
        NavigationStack {
            List {
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

                Section {
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

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .overlay { if isResolving { ProgressView() } }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Busca un parque, cancha o dirección")
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
