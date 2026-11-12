import Supabase
import SwiftUI

/// Registro e inicio de sesión (US-01). Sin esto no se puede crear ni
/// unirse a actividades.
struct AuthView: View {
    /// Para qué se pide la sesión ("Inicia sesión para unirte…"); opcional.
    var reason: String?
    /// Abre directo en "Crear cuenta" (desde la bienvenida).
    var startInSignUp = false

    @Environment(AuthStore.self) private var authStore

    @State private var mode: Mode
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showPassword = false
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    private enum Mode: String, CaseIterable {
        case signIn = "Iniciar sesión"
        case signUp = "Crear cuenta"
    }

    init(reason: String? = nil, startInSignUp: Bool = false) {
        self.reason = reason
        self.startInSignUp = startInSignUp
        _mode = State(initialValue: startInSignUp ? .signUp : .signIn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Encabezado de marca: tinta con el resplandor coral de la bienvenida.
                    VStack(spacing: 12) {
                        BrandMark(size: 76)
                        Text(Brand.name)
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.white)
                        Text(Brand.tagline)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background {
                        ZStack {
                            Color.brandInk
                            Circle()
                                .fill(Color.brandAccent.opacity(0.5))
                                .frame(width: 260)
                                .blur(radius: 70)
                                .offset(x: 110, y: -60)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DS.heroRadius, style: .continuous))
                    }
                    .accessibilityElement(children: .combine)

                    if let reason {
                        Label(reason, systemImage: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.brandText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Picker("Modo", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 14) {
                        if mode == .signUp {
                            TextField("Nombre", text: $fullName)
                                .textContentType(.name)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .email }
                        }
                        TextField("Correo electrónico", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                        passwordField
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
                            .foregroundStyle(Color.brandAccentText)
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

    /// Contraseña con botón para verla u ocultarla (evita errores al escribirla).
    private var passwordField: some View {
        Group {
            if showPassword {
                TextField("Contraseña", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField("Contraseña", text: $password)
            }
        }
        .textContentType(mode == .signUp ? .newPassword : .password)
        .textFieldStyle(.roundedBorder)
        .focused($focus, equals: .password)
        .submitLabel(.go)
        .onSubmit { if canSubmit && !isLoading { Task { await submit() } } }
        .padding(.trailing, 40)
        .overlay(alignment: .trailing) {
            Button {
                showPassword.toggle()
                focus = .password
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.fitcomPressable)
            .accessibilityLabel(showPassword ? "Ocultar contraseña" : "Mostrar contraseña")
        }
    }

    /// Dice qué pasó en lugar de un mensaje único para todo.
    private func message(for error: Error) -> String {
        if ErrorText.isOffline(error) {
            return "Sin conexión. Revisa tu internet e intenta de nuevo."
        }
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials:
                return "Correo o contraseña incorrectos."
            case .emailNotConfirmed:
                return "Confirma tu correo antes de entrar: te enviamos un enlace."
            case .userAlreadyExists, .emailExists:
                return "Ya existe una cuenta con ese correo. Prueba iniciar sesión."
            case .weakPassword:
                return "La contraseña es muy débil. Usa una más larga y difícil de adivinar."
            default:
                break
            }
        }
        return "No se pudo completar la operación. Intenta de nuevo."
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
            if let authError = error as? AuthError {
                AppLog.auth.error("Auth falló: \(authError.errorCode.rawValue, privacy: .public)")
            } else {
                AppLog.auth.error("Auth falló: \(error.localizedDescription, privacy: .public)")
            }
            errorMessage = message(for: error)
        }
    }
}
