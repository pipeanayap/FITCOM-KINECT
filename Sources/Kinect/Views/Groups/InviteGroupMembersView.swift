import SwiftUI

/// Invitaciones del creador. La persona invitada decide si acepta el ingreso.
struct InviteGroupMembersView: View {
    let groupId: UUID
    let excludedIds: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var candidates: [GroupInviteCandidate] = []
    @State private var invitedIds: Set<UUID> = []
    @State private var isSearching = false
    @State private var invitingId: UUID?
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Buscar por usuario") {
                    TextField("@usuario", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(invitingId != nil)
                    if searchTerm.count < 2 {
                        Text("Escribe al menos 2 caracteres para buscar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if isSearching {
                    ProgressView()
                } else if hasSearched && candidates.isEmpty {
                    Text("No hay personas disponibles con ese usuario.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { person in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.fullName).font(.subheadline.weight(.semibold))
                                if let username = person.username {
                                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if invitedIds.contains(person.id) {
                                Text("Invitación enviada").font(.caption).foregroundStyle(.secondary)
                            } else if invitingId == person.id {
                                ProgressView()
                            } else {
                                Button("Invitar") { Task { await invite(person) } }
                                    .buttonStyle(.fitcomInk)
                                    .disabled(invitingId != nil)
                            }
                        }
                    }
                }
                if let searchError {
                    Text(searchError).font(.footnote).foregroundStyle(.red)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Invitar al grupo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { dismiss() }.disabled(invitingId != nil)
                }
            }
        }
        .tint(.brandAccent)
        .task(id: searchTerm) { await search(searchTerm) }
        .interactiveDismissDisabled(invitingId != nil)
    }

    private var searchTerm: String {
        username.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    @MainActor
    private func search(_ term: String) async {
        candidates = []
        hasSearched = false
        searchError = nil
        guard term.count >= 2 else {
            isSearching = false
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()
            let results = try await GroupService.inviteCandidates(username: term)
            try Task.checkCancellation()
            guard term == searchTerm else { return }
            candidates = results.filter { !excludedIds.contains($0.id) }
            hasSearched = true
            isSearching = false
        } catch {
            // Una respuesta anterior nunca debe sustituir la búsqueda actual.
            guard !Task.isCancelled, term == searchTerm else { return }
            isSearching = false
            searchError = "No se pudieron buscar personas. Intenta de nuevo."
        }
    }

    private func invite(_ person: GroupInviteCandidate) async {
        guard invitingId == nil else { return }
        invitingId = person.id
        errorMessage = nil
        defer { invitingId = nil }
        do {
            try await GroupService.sendRequest(groupId: groupId, userId: person.id, invitation: true)
            invitedIds.insert(person.id)
        } catch {
            errorMessage = GroupService.failureMessage(error, fallback: "No se pudo enviar la invitación. Intenta de nuevo.")
        }
    }
}
