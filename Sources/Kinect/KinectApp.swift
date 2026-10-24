import SwiftUI

@main
struct KinectApp: App {
    @State private var authStore = AuthStore()

    init() {
        // Fotos del feed: 50 MB en memoria y 200 MB en disco (ver CachedAsyncImage).
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authStore)
                .task { await KeyboardDismisser.shared.installWhenReady() }
        }
    }
}
