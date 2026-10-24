import SwiftUI

extension View {
    /// Deslizar desde el borde izquierdo hacia la derecha para regresar.
    ///
    /// Las pantallas de detalle ocultan la barra de navegación nativa (tienen su
    /// propio botón de atrás) y con la barra oculta iOS desactiva el gesto de
    /// regresar; aquí se reemplaza por uno propio. Sólo cuenta si el dedo
    /// empieza pegado al borde, para no chocar con carruseles ni con el scroll.
    func edgeSwipeBack(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { value in
                    let startedAtEdge = value.startLocation.x < 32
                    let wentRight = value.translation.width > 80
                    let mostlyHorizontal = abs(value.translation.height) < value.translation.width * 0.7
                    if startedAtEdge && wentRight && mostlyHorizontal { action() }
                }
        )
    }
}
