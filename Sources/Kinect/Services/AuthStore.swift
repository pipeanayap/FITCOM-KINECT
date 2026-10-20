import Foundation
import Supabase

/// Sesión y perfil del usuario actual (US-01). Las pantallas de la app
/// observan esto para saber si hay sesión y, si la hay, quién es.
@Observable
@MainActor
final class AuthStore {
    private(set) var session: Session?
    private(set) var profile: Profile?
    private(set) var isLoading = true

    var isSignedIn: Bool { session != nil }
    var isAdmin: Bool { profile?.isAdmin ?? false }
    var userId: UUID? { session?.user.id }

    // Vive mientras vive la app (se guarda en la raíz de la jerarquía de
    // vistas), así que no hace falta cancelar esta tarea en un deinit.
    private var authTask: Task<Void, Never>?

    init() {
        authTask = Task { [weak self] in
            guard let self else { return }
            for await (_, session) in SupabaseManager.client.auth.authStateChanges {
                await self.handle(session: session)
            }
        }
    }

    private func handle(session: Session?) async {
        self.session = session
        isLoading = false
        await refreshProfile()
    }

    func refreshProfile() async {
        guard let userId = session?.user.id else {
            profile = nil
            return
        }
        profile = try? await ProfileService.fetch(id: userId)
    }

    /// - Returns: `true` si quedó con sesión iniciada de una vez; `false` si el
    ///   proyecto requiere confirmar el correo antes de poder entrar.
    @discardableResult
    func signUp(fullName: String, email: String, password: String) async throws -> Bool {
        let response = try await SupabaseManager.client.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(fullName)]
        )
        return response.session != nil
    }

    func signIn(email: String, password: String) async throws {
        try await SupabaseManager.client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await SupabaseManager.client.auth.signOut()
    }
}
