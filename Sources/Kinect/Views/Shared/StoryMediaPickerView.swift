import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Selector exclusivo de historias: no cambia los selectores de avatares o posts.
struct StoryMediaPickerView: UIViewControllerRepresentable {
    let onFinish: @MainActor (Result<StoryMedia?, Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: @MainActor (Result<StoryMedia?, Error>) -> Void
        init(onFinish: @escaping @MainActor (Result<StoryMedia?, Error>) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { onFinish(.success(nil)); return }
            Task { @MainActor in
                do {
                    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        let url: URL = try await withCheckedThrowingContinuation { continuation in
                            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                                do {
                                    guard let url else { throw error ?? StoryMediaError.selectionFailed }
                                    // La URL del proveedor sólo es válida durante este callback.
                                    continuation.resume(returning: try StoryMediaService.copyTemporaryVideo(url))
                                } catch { continuation.resume(throwing: error) }
                            }
                        }
                        onFinish(.success(.video(url)))
                    } else {
                        let data: Data = try await withCheckedThrowingContinuation { continuation in
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                                if let data { continuation.resume(returning: data) }
                                else { continuation.resume(throwing: error ?? StoryMediaError.selectionFailed) }
                            }
                        }
                        guard let image = UIImage(data: data) else { throw StoryMediaError.selectionFailed }
                        onFinish(.success(.image(image)))
                    }
                } catch { onFinish(.failure(error)) }
            }
        }
    }
}

struct StoryCameraView: UIViewControllerRepresentable {
    let video: Bool
    let onFinish: @MainActor (Result<StoryMedia?, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [video ? UTType.movie.identifier : UTType.image.identifier]
        // Un segundo de margen para que el archivo final siga siendo menor de 50 s.
        picker.videoMaximumDuration = 49
        picker.videoQuality = .typeMedium
        picker.cameraCaptureMode = video ? .video : .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: @MainActor (Result<StoryMedia?, Error>) -> Void
        init(onFinish: @escaping @MainActor (Result<StoryMedia?, Error>) -> Void) { self.onFinish = onFinish }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(.success(nil)) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            do {
                if let url = info[.mediaURL] as? URL {
                    onFinish(.success(.video(try StoryMediaService.copyTemporaryVideo(url))))
                } else if let image = info[.originalImage] as? UIImage {
                    onFinish(.success(.image(image)))
                } else { throw StoryMediaError.selectionFailed }
            } catch { onFinish(.failure(error)) }
        }
    }
}
