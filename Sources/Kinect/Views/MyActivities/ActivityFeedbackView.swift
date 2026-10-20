import SwiftUI

/// Encuesta opcional después de una actividad (US-16).
struct ActivityFeedbackView: View {
    let activityId: UUID

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var activityHappened = true
    @State private var metPeople = true
    @State private var easeRating = 4
    @State private var comment = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            Form {
                if didSend {
                    Section {
                        Label("¡Gracias por tu respuesta!", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section {
                        Toggle("¿La actividad se realizó?", isOn: $activityHappened)
                        if activityHappened {
                            Toggle("¿Lograste participar con otras personas?", isOn: $metPeople)
                        }
                    }
                    Section("¿Qué tan fácil fue encontrar y coordinar la actividad?") {
                        Picker("Calificación", selection: $easeRating) {
                            ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Comentario (opcional)") {
                        TextField("Cuéntanos más", text: $comment, axis: .vertical)
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Tu experiencia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSend ? "Cerrar" : "Cancelar") { dismiss() }
                }
                if !didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("Enviar") { Task { await send() } }
                        }
                    }
                }
            }
        }
    }

    private func send() async {
        guard let userId = authStore.userId else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            try await FeedbackService.submit(
                NewActivityFeedback(
                    activityId: activityId,
                    userId: userId,
                    activityHappened: activityHappened,
                    metPeople: activityHappened ? metPeople : nil,
                    easeRating: easeRating,
                    comment: comment.isEmpty ? nil : comment
                )
            )
            didSend = true
        } catch {
            errorMessage = "No se pudo enviar tu respuesta. Puede que ya hayas calificado esta actividad."
        }
    }
}
