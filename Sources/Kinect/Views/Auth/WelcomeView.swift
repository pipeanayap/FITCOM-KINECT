import SwiftUI

/// Primera pantalla que ve alguien nuevo: qué es la app en una frase y tres
/// razones para entrar. Se muestra una sola vez; se puede explorar sin cuenta.
struct WelcomeView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var authMode: AuthStart?

    private enum AuthStart: Identifiable {
        case signUp, signIn
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            Color.brandInk.ignoresSafeArea()
            glow

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark(size: 44)
                    Text(Brand.name)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(.white)
                }
                .reveal(appeared, order: 0, reduceMotion: reduceMotion)

                Spacer(minLength: 24)

                Text("Encuentra con quién moverte.")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .reveal(appeared, order: 1, reduceMotion: reduceMotion)

                Text("Actividades, grupos y gente que comparte tu deporte, cerca de ti.")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 12)
                    .reveal(appeared, order: 2, reduceMotion: reduceMotion)

                VStack(alignment: .leading, spacing: 16) {
                    point("calendar.badge.plus", "Únete o crea tu reta", "Publica una actividad y junta gente en minutos.")
                    point("person.3.fill", "Entra a grupos", "Una comunidad por deporte, con su propio chat.")
                    point("location.fill", "Encuentra lo cercano", "Lo que pasa hoy cerca de ti, en el mapa.")
                }
                .padding(.top, 28)
                .reveal(appeared, order: 3, reduceMotion: reduceMotion)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Button("Crear cuenta") { authMode = .signUp }
                        .buttonStyle(.fitcomPrimary(disabled: false))
                    Button("Ya tengo cuenta") { authMode = .signIn }
                        .buttonStyle(.fitcomSecondary(tint: .white))
                        .frame(maxWidth: .infinity)
                    Button("Explorar sin cuenta") { onFinish() }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)
                        .frame(minHeight: 44)
                }
                .reveal(appeared, order: 4, reduceMotion: reduceMotion)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $authMode) { start in
            AuthView(startInSignUp: start == .signUp)
        }
        .task { appeared = true }
    }

    /// Resplandor coral detrás del contenido: da profundidad sin competir con el texto.
    private var glow: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Color.brandAccent.opacity(0.55))
                    .frame(width: proxy.size.width * 1.1)
                    .blur(radius: 90)
                    .offset(x: proxy.size.width * 0.35, y: -proxy.size.height * 0.28)
                Circle()
                    .fill(Color(red: 0.55, green: 0.14, blue: 0.06).opacity(0.5))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.4, y: proxy.size.height * 0.45)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.brandAccent.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Entrada escalonada (sólo esta pantalla, que se ve una vez): sube 14 pt y
    /// aparece, 60 ms después de la anterior. Con "Reducir movimiento" no se mueve.
    func reveal(_ shown: Bool, order: Int, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(.easeOut(duration: 0.4).delay(Double(order) * 0.06), value: shown)
    }
}
