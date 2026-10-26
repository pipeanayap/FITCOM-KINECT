@preconcurrency import AVFoundation
import Foundation
import Supabase
import UIKit

enum StoryMedia {
    case image(UIImage)
    /// Copia temporal propiedad de la app, nunca el archivo original de la galería.
    case video(URL)
}

enum StoryMediaError: LocalizedError {
    case invalidVideo, tooLong, tooLarge, preparationFailed, selectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidVideo: "No se pudo leer el video. Elige otro archivo."
        case .tooLong: "El video debe durar menos de 50 segundos."
        case .tooLarge: "El video es demasiado grande. Elige uno más corto."
        case .preparationFailed: "No se pudo preparar el archivo. Intenta con otro."
        case .selectionFailed: "No se pudo cargar el archivo seleccionado. Intenta de nuevo."
        }
    }
}

enum StoryMediaService {
    static let videoBucket = "story-videos"
    static let maxVideoBytes = 50 * 1024 * 1024

    static func copyTemporaryVideo(_ source: URL) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("story-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func validateVideo(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw StoryMediaError.invalidVideo }
        let seconds = (try await asset.load(.duration)).seconds
        guard seconds.isFinite, seconds > 0 else { throw StoryMediaError.invalidVideo }
        guard seconds < 50 else { throw StoryMediaError.tooLong }
        return seconds
    }

    /// Normaliza a MP4 comprimido, sin recortar ni aceptar videos de 50 s o más.
    static func prepareVideo(_ url: URL) async throws -> (url: URL, duration: Double) {
        _ = try await validateVideo(url)
        let asset = AVURLAsset(url: url)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality),
              exporter.supportedFileTypes.contains(.mp4) else { throw StoryMediaError.preparationFailed }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("story-\(UUID().uuidString).mp4")
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        do {
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw StoryMediaError.preparationFailed }
            let duration = try await validateVideo(output)
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= maxVideoBytes else { throw StoryMediaError.tooLarge }
            return (output, duration)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    static func uploadVideo(_ url: URL, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).mp4"
        try await SupabaseManager.client.storage.from(videoBucket)
            .upload(path, fileURL: url, options: FileOptions(contentType: "video/mp4"))
        return path
    }

    static func publicURL(for story: Story) -> URL? {
        if story.isVideo {
            return try? SupabaseManager.client.storage.from(videoBucket).getPublicURL(path: story.imagePath)
        }
        return ImageUploadService.publicURL(for: story.imagePath)
    }

    static func deleteVideo(path: String) async {
        _ = try? await SupabaseManager.client.storage.from(videoBucket).remove(paths: [path])
    }
}
