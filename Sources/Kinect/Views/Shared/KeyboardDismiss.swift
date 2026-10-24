import UIKit

/// Cierra el teclado al tocar fuera del campo de texto, en toda la app (también
/// dentro de hojas). Es un reconocedor de toques en la ventana que no cancela
/// ni bloquea los toques: botones y listas siguen funcionando igual. Tocar un
/// campo de texto no lo cierra.
@MainActor
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    private var installed = false

    /// La ventana puede tardar un instante en existir al arrancar; se reintenta.
    func installWhenReady() async {
        for _ in 0..<20 where !installed {
            install()
            if installed { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func install() {
        guard !installed,
              let window = UIApplication.shared.connectedScenes
                  .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// No cuenta como "fuera" un toque sobre un campo de texto (ni sobre algo dentro de uno).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextInput { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}
