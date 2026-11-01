import SwiftUI
import AppKit
import AVKit

// AppKit-based clip preview avoids SwiftUI's AVKit bridge, which appeared in
// a previous crash report. Pause and release playback on sheet dismissal.
struct NativeClipPlayer: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.player = AVPlayer(url: url)
        context.coordinator.loadedURL = url
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        view.player?.pause()
        view.player = AVPlayer(url: url)
        context.coordinator.loadedURL = url
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
    }
}
