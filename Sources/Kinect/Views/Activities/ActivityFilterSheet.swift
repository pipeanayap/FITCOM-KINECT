import SwiftUI

/// Filtrar por deporte, fecha, zona y nivel, combinables (US-06).
struct ActivityFilterSheet: View {
    @Binding var filter: ActivityFilter
    @Environment(\.dismiss) private var dismiss

    @State private var sport: String
    @State private var zone: String
    @State private var level: ActivityLevel?
    @State private var useDateRange: Bool
    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var maxDistanceKm: Double?

    init(filter: Binding<ActivityFilter>) {
        _filter = filter
        let current = filter.wrappedValue
        _sport = State(initialValue: current.sport ?? "")
        _zone = State(initialValue: current.zone ?? "")
        _level = State(initialValue: current.level)
        _useDateRange = State(initialValue: current.fromDate != nil || current.toDate != nil)
        _fromDate = State(initialValue: current.fromDate ?? Date())
        _maxDistanceKm = State(initialValue: current.maxDistanceKm)
        _toDate = State(initialValue: current.toDate ?? Date().addingTimeInterval(7 * 86400))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deporte y zona") {
                    Picker("Deporte", selection: $sport) {
                        Text("Cualquiera").tag("")
                        ForEach(SportVisuals.canonicalSports, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Zona", text: $zone)
                }

                Section("Distancia") {
                    Picker("Radio desde mi ubicación", selection: $maxDistanceKm) {
                        Text("Sin límite").tag(Double?.none)
                        ForEach([2.0, 5.0, 10.0, 25.0], id: \.self) { Text("\(Int($0)) km").tag(Double?.some($0)) }
                    }
                }

                Section("Nivel") {
                    Picker("Nivel", selection: $level) {
                        Text("Cualquiera").tag(ActivityLevel?.none)
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag(ActivityLevel?.some($0)) }
                    }
                }

                Section("Fecha") {
                    Toggle("Filtrar por intervalo de fechas", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("Desde", selection: $fromDate, displayedComponents: .date)
                        DatePicker("Hasta", selection: $toDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Filtros")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { apply() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Limpiar filtros") { clear() }
                }
            }
        }
        .tint(.brandAccent)
    }

    private func apply() {
        filter = ActivityFilter(
            sport: sport.isEmpty ? nil : sport,
            zone: zone.isEmpty ? nil : zone,
            level: level,
            fromDate: useDateRange ? fromDate.startOfDay : nil,
            toDate: useDateRange ? toDate.endOfDay : nil,
            maxDistanceKm: maxDistanceKm
        )
        dismiss()
    }

    private func clear() {
        filter = .empty
        dismiss()
    }
}

extension Date {
    fileprivate var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    fileprivate var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }
}
