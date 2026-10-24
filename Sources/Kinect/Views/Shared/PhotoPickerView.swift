import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Selector de fotos con PHPickerViewController. `PhotosPicker` de SwiftUI vive
/// en un módulo overlay que el build de xtool no incluye (igual que `Map`).
/// No necesita permiso de la fototeca.
struct PhotoPickerView: UIViewControllerRepresentable {
    let limit: Int
    /// Se llama con las fotos elegidas (vacío si se canceló).
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = limit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let providers = results.map(\.itemProvider)
            let onFinish = onFinish
            Task { @MainActor in
                var images: [UIImage] = []
                for provider in providers {
                    let data: Data? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                            continuation.resume(returning: data)
                        }
                    }
                    if let data, let image = UIImage(data: data) { images.append(image) }
                }
                onFinish(images)
            }
        }
    }
}
