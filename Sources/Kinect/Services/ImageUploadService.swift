import Foundation
import Supabase
import UIKit

/// Preparar y subir fotos a Supabase Storage (SCRUM-43). La transformación de
/// imágenes en el servidor es del plan Pro, así que se reduce y comprime en
/// el teléfono antes de subir. Reutilizable para avatares e historias.
enum ImageUploadService {
    static let bucket = "post-images"

    /// Reduce el lado largo a `maxSide` px y codifica a JPEG (~150–300 KB).
    static func prepare(_ image: UIImage, maxSide: CGFloat = 1080, quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Sube a `<user_id>/<uuid>.jpg` (la política de Storage sólo deja escribir
    /// en la carpeta propia, en minúsculas como `auth.uid()`). Devuelve la ruta.
    static func upload(_ data: Data, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await SupabaseManager.client.storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    static func publicURL(for path: String) -> URL? {
        try? SupabaseManager.client.storage.from(bucket).getPublicURL(path: path)
    }

    /// Borrado de mejor esfuerzo (al eliminar un post); no debe romper el flujo.
    static func delete(paths: [String]) async {
        guard !paths.isEmpty else { return }
        _ = try? await SupabaseManager.client.storage.from(bucket).remove(paths: paths)
    }
}
