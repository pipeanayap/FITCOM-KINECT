import SwiftUI

/// La marca de la app: dos círculos que se encuentran (coral y blanco) con un
/// "+" en el cruce, igual que el icono. Es la idea de la app dibujada: gente
/// que se junta a moverse.
struct BrandMark: View {
    var size: CGFloat = 72
    /// Color del fondo sobre el que va, para el cruce de los círculos.
    var background: Color = .brandInk

    var body: some View {
        let d = size * 0.62
        let shift = size * 0.19
        ZStack {
            Circle().fill(Color.brandAccent).frame(width: d, height: d).offset(x: -shift)
            Circle().fill(Color.white).frame(width: d, height: d).offset(x: shift)
            // El cruce se pinta con el color de fondo, como en el icono.
            Circle().fill(background).frame(width: d, height: d).offset(x: -shift)
                .mask(Circle().frame(width: d, height: d).offset(x: shift))
            Image(systemName: "plus")
                .font(.system(size: size * 0.17, weight: .heavy))
                .foregroundStyle(Color.brandAccent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
