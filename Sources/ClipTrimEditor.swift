import SwiftUI
import AppKit
import AVKit
import AVFoundation

@MainActor
final class ClipTrimSession: ObservableObject {
    let url: URL
    let player: AVPlayer

    @Published var duration = 0.0
    @Published var start = 0.0
    @Published var end = 0.0
    @Published var playhead = 0.0
    @Published var isPlaying = false
    @Published var thumbnails: [NSImage] = []
    @Published var isExporting = false
    @Published var lastExport: URL?
    @Published var errorMessage: String?
    @Published var loading = true

    private var timeObserver: Any?
    private var loaded = false
    private let minimumSelection = 0.25

    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            let asset = AVURLAsset(url: url)
            let time = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite && seconds >= minimumSelection else {
                throw ClipTrimError.invalidRange
            }
            duration = seconds
            end = seconds
            player.actionAtItemEnd = .pause
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
                queue: .main
            ) { [weak self] current in
                guard let self else { return }
                let value = CMTimeGetSeconds(current)
                guard value.isFinite else { return }
                self.playhead = value
                if self.player.rate > 0 && value >= self.end - 0.07 {
                    self.player.pause()
                    self.isPlaying = false
                    self.seek(to: self.start)
                }
            }
            loading = false

            let total = seconds
            thumbnails = await Task.detached(priority: .utility) { [url] in
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 210, height: 122)
                var pictures: [NSImage] = []
                for index in 0..<10 {
                    let second = min(total - 0.05, total * (Double(index) + 0.5) / 10)
                    if let frame = try? generator.copyCGImage(
                        at: CMTime(seconds: second, preferredTimescale: 600),
                        actualTime: nil
                    ) {
                        pictures.append(NSImage(cgImage: frame,
                                                size: NSSize(width: 210, height: 122)))
                    }
                }
                return pictures
            }.value
        } catch {
            loading = false
            errorMessage = "Unable to open clip: \(error.localizedDescription)"
        }
    }

    func updateStart(_ value: Double) {
        guard duration > 0 else { return }
        pause()
        start = max(0, min(value, end - minimumSelection))
        seek(to: start)
    }

    func updateEnd(_ value: Double) {
        guard duration > 0 else { return }
        pause()
        end = min(duration, max(value, start + minimumSelection))
        seek(to: end)
    }

    func seek(to rawValue: Double) {
        let value = min(end, max(start, rawValue))
        guard value.isFinite else { return }
        playhead = value
        player.seek(to: CMTime(seconds: value, preferredTimescale: 60000),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        guard duration > 0 else { return }
        if isPlaying { pause(); return }
        if playhead >= end - 0.10 || playhead < start {
            seek(to: start)
        }
        isPlaying = true
        player.play()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func reset() {
        guard duration > 0 else { return }
        pause()
        start = 0
        end = duration
        seek(to: 0)
    }

    func export(onSaved: @escaping (URL) -> Void) {
        guard !isExporting, duration > 0 else { return }
        pause()
        isExporting = true
        errorMessage = nil
        lastExport = nil
        let source = url
        let initial = start
        let final = end
        Task { [weak self] in
            do {
                let result = try await ClipTrimExporter.export(
                    source: source,
                    start: initial,
                    end: final,
                    outputDirectory: source.deletingLastPathComponent())
                self?.lastExport = result
                self?.isExporting = false
                onSaved(result)
            } catch {
                self?.isExporting = false
                self?.errorMessage = "Couldn't save trimmed clip: \(error.localizedDescription)"
            }
        }
    }

    func dispose() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    var selectionLength: Double { max(0, end - start) }
}

struct TrimPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.videoGravity = .resizeAspect
        view.controlsStyle = .none
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

struct ClipTrimEditor: View {
    let clip: ClipItem
    let onClose: () -> Void
    let onSaved: (URL) -> Void

    @StateObject private var session: ClipTrimSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tint = Color(red: 0.55, green: 0.79, blue: 1)

    init(clip: ClipItem,
         onClose: @escaping () -> Void,
         onSaved: @escaping (URL) -> Void) {
        self.clip = clip
        self.onClose = onClose
        self.onSaved = onSaved
        _session = StateObject(wrappedValue: ClipTrimSession(url: clip.url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 13) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(tint)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trim clip")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(clip.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.57))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                } label: {
                    Label("Original", systemImage: "folder")
                }
                .buttonStyle(TactileGlassActionStyle())
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(TactileGlassActionStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(session.isExporting)
                .help("Close editor")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.43))
                TrimPlayerView(player: session.player)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                if session.loading {
                    ProgressView("Loading clip…")
                        .padding(18)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(height: 355)

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SELECT MOMENT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.46))
                        Text("Drag the left and right handles to choose what stays.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Text("\(timecode(session.selectionLength)) selected")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint)
                }
                trimTimeline
                HStack {
                    Text(timecode(session.start))
                    Spacer()
                    Text(timecode(session.playhead))
                        .foregroundStyle(tint)
                    Spacer()
                    Text(timecode(session.end))
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
            }
            .padding(18)
            .background(.white.opacity(0.065),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1))

            HStack(spacing: 10) {
                Button {
                    session.togglePlayback()
                    CLIPFeedback.tap()
                } label: {
                    Label(session.isPlaying ? "Pause preview" : "Play selected",
                          systemImage: session.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(TactileGlassActionStyle())
                .disabled(session.duration == 0 || session.isExporting)

                Button {
                    session.reset()
                    CLIPFeedback.tap()
                } label: {
                    Label("Reset handles", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TactileGlassActionStyle())
                .disabled(session.duration == 0 || session.isExporting)

                Spacer()

                Button {
                    session.export(onSaved: onSaved)
                } label: {
                    HStack(spacing: 7) {
                        if session.isExporting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(session.isExporting ? "Exporting…" : "Save trimmed copy")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(TactileGlassActionStyle(prominent: true))
                .disabled(session.duration == 0 ||
                          session.isExporting || session.selectionLength < 0.25)
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if let file = session.lastExport {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Trimmed clip saved. Original unchanged.")
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    }
                    .buttonStyle(TactileTextButtonStyle())
                }
                .font(.system(size: 11))
            } else {
                Text("Your original video will not be changed. Exports appear in your CLIP library.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
        .padding(22)
        .frame(width: 850)
        .background(Color(red: 0.075, green: 0.10, blue: 0.16))
        .preferredColorScheme(.dark)
        .task { await session.load() }
        .onDisappear { session.dispose() }
    }

    private var trimTimeline: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let total = max(0.01, session.duration)
            let left = CGFloat(session.start / total) * width
            let right = CGFloat(session.end / total) * width
            let cursor = CGFloat(session.playhead / total) * width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.14, green: 0.19, blue: 0.27))
                HStack(spacing: 1) {
                    ForEach(0..<10, id: \.self) { idx in
                        Group {
                            if !session.thumbnails.isEmpty {
                                let image = session.thumbnails[
                                    min(session.thumbnails.count - 1,
                                        idx * session.thumbnails.count / 10)]
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(
                                    LinearGradient(colors: [
                                        tint.opacity(0.24),
                                        Color(red: 0.17, green: 0.14, blue: 0.29)
                                    ], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .frame(width: max(1, (width - 9) / 10), height: 80)
                        .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Rectangle()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: max(0, left))
                Rectangle()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: max(0, width - right))
                    .offset(x: right)

                Rectangle()
                    .fill(tint.opacity(0.10))
                    .frame(width: max(0, right - left))
                    .overlay(Rectangle()
                        .strokeBorder(tint.opacity(0.86), lineWidth: 2))
                    .offset(x: left)

                // The playhead remains visible while scrubbing or previewing.
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: 65)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(x: cursor - 1)
                    .allowsHitTesting(false)

                handle(isStart: true, width: width)
                    .position(x: min(max(left, 17), width - 17), y: 40)
                handle(isStart: false, width: width)
                    .position(x: min(max(right, 17), width - 17), y: 40)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
            .coordinateSpace(name: "clipTrimTimeline")
            .onTapGesture(coordinateSpace: .named("clipTrimTimeline")) { location in
                let value = min(total, max(0, Double(location.x / width) * total))
                session.seek(to: value)
            }
        }
        .frame(height: 80)
        .accessibilityLabel("Clip trim timeline")
    }

    private func handle(isStart: Bool, width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    colors: [Color(red: 0.77, green: 0.91, blue: 1),
                             tint, Color(red: 0.28, green: 0.56, blue: 0.92)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 17, height: 80)
                .shadow(color: .black.opacity(0.4), radius: 6)
            HStack(spacing: 2) {
                Capsule().fill(.white.opacity(0.86)).frame(width: 1.5, height: 19)
                Capsule().fill(.white.opacity(0.86)).frame(width: 1.5, height: 19)
            }
        }
        .frame(width: 34, height: 80)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("clipTrimTimeline"))
                .onChanged { gesture in
                    guard !session.isExporting, session.duration > 0 else { return }
                    // GeometryReader width isn't directly available in this helper;
                    // read the width from the timeline's shared environment below.
                    let value = min(1, max(0, Double(gesture.location.x / max(1, width))))
                        * session.duration
                    if isStart { session.updateStart(value) }
                    else { session.updateEnd(value) }
                }
                .onEnded { _ in CLIPFeedback.detent() }
        )
        .accessibilityLabel(isStart ? "Trim start handle" : "Trim end handle")
        .accessibilityHint("Drag horizontally to adjust the selected footage.")
    }

    private func timecode(_ seconds: Double) -> String {
        let n = max(0, seconds.isFinite ? seconds : 0)
        return String(format: "%02d:%04.1f", Int(n / 60), n.truncatingRemainder(dividingBy: 60))
    }
}
