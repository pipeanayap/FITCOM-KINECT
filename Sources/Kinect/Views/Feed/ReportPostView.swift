import SwiftUI

/// Reportar una publicación inapropiada (SCRUM-46). Mismo flujo que
/// `ReportActivityView`: un reporte por persona y publicación.
struct ReportPostView: View {
    let postId: UUID

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .contenidoInapropiado
    @State private var description = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            Form {
                if didSend {
                    Section {
                        Label("Reporte enviado. Gracias por avisarnos.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section("Motivo") {
                        Picker("Motivo", selection: $reason) {
                            ForEach(ReportReason.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Section("Descripción (opcional)") {
                        TextField("Cuéntanos qué pasó", text: $description, axis: .vertical)
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Reportar publicación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(didSend ? "Cerrar" : "Cancelar") { dismiss() } }
                if !didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending { ProgressView() } else { Button("Enviar") { Task { await send() } } }
                    }
                }
            }
        }
        .tint(.brandAccent)
    }

    private func send() async {
        guard let userId = authStore.userId else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            try await PostService.report(
                postId: postId, reporterId: userId, reason: reason,
                description: description.isEmpty ? nil : description
            )
            didSend = true
        } catch {
            errorMessage = "No se pudo enviar. Quizá ya reportaste esta publicación."
        }
    }
}
