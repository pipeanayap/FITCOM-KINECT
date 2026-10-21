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
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.brandAccent.gradient).frame(width: 72, height: 72)
                            Image(systemName: "figure.run")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("FITCOM")
                            .font(.largeTitle.bold())
                        Text("Encuentra gente para moverte")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

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
                    .cardStyle()

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let confirmationMessage {
                        Label(confirmationMessage, systemImage: "envelope.badge.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.brandAccent)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                    .buttonStyle(.fitcomPrimary(disabled: !canSubmit || isLoading))
                    .disabled(!canSubmit || isLoading)
                }
                .padding()
            }
            .background(Color.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
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
