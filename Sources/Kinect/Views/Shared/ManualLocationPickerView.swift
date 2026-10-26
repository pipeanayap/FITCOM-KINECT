import CoreLocation
import MapKit
import SwiftUI

/// Permite fijar una dirección aunque MapKit no la encuentre en la búsqueda.
struct ManualLocationPickerView: View {
    let initialCoordinate: CLLocationCoordinate2D
    let initialName: String
    let onPick: (PickedPlace) -> Void

    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var placeName: String
    @State private var isResolving = false

    init(initialCoordinate: CLLocationCoordinate2D, initialName: String,
         onPick: @escaping (PickedPlace) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.initialName = initialName
        self.onPick = onPick
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _placeName = State(initialValue: initialName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DraggableLocationMap(initialCoordinate: initialCoordinate, coordinate: $selectedCoordinate)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.brandAccent)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .offset(y: -20)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Mapa para elegir ubicación")

            VStack(alignment: .leading, spacing: 12) {
                Text("Mueve el mapa hasta que el pin quede sobre el lugar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Nombre o dirección (opcional)", text: $placeName)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await confirmLocation() }
                } label: {
                    if isResolving { ProgressView().tint(.white) }
                    else { Text("Usar esta ubicación") }
                }
                .buttonStyle(.fitcomPrimary(disabled: isResolving))
                .disabled(isResolving)
            }
            .padding()
            .background(Color.screenBackground)
        }
        .navigationTitle("Elegir en el mapa")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func confirmLocation() async {
        isResolving = true
        defer { isResolving = false }
        let coordinate = selectedCoordinate
        let typedName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = typedName.isEmpty
            ? await PlaceSearchService.place(
                at: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                fallbackName: "Ubicación seleccionada en el mapa"
            ).name
            : typedName
        onPick(PickedPlace(name: resolved, latitude: coordinate.latitude,
                           longitude: coordinate.longitude))
    }
}

/// El pin permanece en el centro mientras el usuario arrastra o acerca el mapa.
private struct DraggableLocationMap: UIViewRepresentable {
    let initialCoordinate: CLLocationCoordinate2D
    @Binding var coordinate: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator { Coordinator(coordinate: $coordinate) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.setRegion(MKCoordinateRegion(center: initialCoordinate,
                                         latitudinalMeters: 1500, longitudinalMeters: 1500),
                      animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var coordinate: Binding<CLLocationCoordinate2D>

        init(coordinate: Binding<CLLocationCoordinate2D>) { self.coordinate = coordinate }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            coordinate.wrappedValue = mapView.centerCoordinate
        }
    }
}
