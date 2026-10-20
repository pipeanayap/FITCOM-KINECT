import SwiftUI

/// Registro e inicio de sesión (US-01). Sin esto no se puede crear ni
/// unirse a actividades.
struct AuthView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var mode: Mode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?

    private enum Mode: String, CaseIterable {
        case signIn = "Iniciar sesión"
        case signUp = "Crear cuenta"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Modo", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 14) {
                        if mode == .signUp {
                            TextField("Nombre", text: $fullName)
                                .textContentType(.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Correo electrónico", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("Contraseña", text: $password)
                            .textContentType(mode == .signUp ? .newPassword : .password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    if let confirmationMessage {
                        Text(confirmationMessage)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(mode.rawValue)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || isLoading)
                }
                .padding()
            }
            .navigationTitle("FITCOM")
            .onChange(of: mode) {
                errorMessage = nil
                confirmationMessage = nil
            }
        }
    }

    private var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        return mode == .signIn || !fullName.isEmpty
    }

    private func submit() async {
        errorMessage = nil
        confirmationMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .signIn:
                try await authStore.signIn(email: email, password: password)
            case .signUp:
                let signedInNow = try await authStore.signUp(
                    fullName: fullName, email: email, password: password
                )
                if !signedInNow {
                    confirmationMessage = "Revisa tu correo para confirmar tu cuenta antes de entrar."
                }
            }
        } catch {
            errorMessage = "No se pudo completar la operación. Revisa tus datos e intenta de nuevo."
        }
    }
}
