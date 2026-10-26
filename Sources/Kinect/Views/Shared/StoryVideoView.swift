@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// AVPlayerLayer evita depender del overlay SwiftUI de AVKit en xtool.
private final class StoryPlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct StoryPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> StoryPlayerSurface {
        let view = StoryPlayerSurface()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: StoryPlayerSurface, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: StoryPlayerSurface, coordinator: ()) { view.playerLayer.player = nil }
}

struct StoryVideoView: View {
    let url: URL
    var isPlaying = true
    var onProgress: (Double) -> Void = { _ in }
    var onFinished: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player { StoryPlayerLayer(player: player) }
            else if !failed { ProgressView().tint(.white) }
            if failed {
                Text("No se pudo reproducir el video.")
                    .font(.subheadline).foregroundStyle(.white)
            }
        }
        .task(id: url) { await start() }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isPlaying { player?.play() } else { player?.pause() }
        }
        .onChange(of: isPlaying) { _, play in
            if play && scenePhase == .active { player?.play() } else { player?.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === player?.currentItem else { return }
            onProgress(1)
            onFinished()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem, item === player?.currentItem else { return }
            failed = true
            player?.pause()
        }
    }

    @MainActor
    private func start() async {
        stop()
        failed = false
        onProgress(0)
        do {
            let asset = AVURLAsset(url: url)
            let duration = (try await asset.load(.duration)).seconds
            guard duration.isFinite, duration > 0, try await asset.load(.isPlayable) else {
                throw StoryMediaError.invalidVideo
            }
            try Task.checkCancellation()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            let current = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = current
            timeObserver = current.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { time in
                Task { @MainActor in
                    guard player === current else { return }
                    onProgress(min(1, max(0, time.seconds / duration)))
                }
            }
            if scenePhase == .active && isPlaying { current.play() }
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }

    @MainActor
    private func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
