import SwiftUI
import UIKit

/// Imagen remota con caché en memoria y en disco (SCRUM-43). `AsyncImage` no
/// guarda nada en disco, y el feed volvería a descargar las fotos con cada scroll.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageMemoryCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let loaded = UIImage(data: data) else { return }
        ImageMemoryCache.shared.setObject(loaded, forKey: url as NSURL)
        image = loaded
    }
}

enum ImageMemoryCache {
    // NSCache es seguro entre hilos; Swift 6 sólo no lo sabe.
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 150
        return cache
    }()
}
