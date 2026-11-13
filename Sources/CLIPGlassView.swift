import SwiftUI
import AppKit
import AVFoundation
import AVKit

private enum CLIPArtwork {
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "CLIPLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }()
}

private enum CLIPStyle {
    // Neutral graphite palette, with one restrained blue-grey accent.
    static let accent = Color(red: 0.67, green: 0.78, blue: 0.87)
    static let text = Color.white.opacity(0.93)
    static let muted = Color.white.opacity(0.55)
    static let border = Color.white.opacity(0.085)
    static let background = Color(red: 0.075, green: 0.082, blue: 0.095)
    static let panel = Color(red: 0.115, green: 0.123, blue: 0.14)
}

private struct GlassWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct WindowChromeStyler: NSViewRepresentable {
    final class WindowObserver: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.hasShadow = true
            }
        }
    }
    func makeNSView(context: Context) -> NSView { WindowObserver() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct FloatingGlass: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(CLIPStyle.panel, in: RoundedRectangle(cornerRadius: min(radius, 13)))
            .overlay {
                RoundedRectangle(cornerRadius: min(radius, 13))
                    .strokeBorder(CLIPStyle.border, lineWidth: 1)
            }
    }
}

private struct QuietSurface: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(CLIPStyle.panel, in: RoundedRectangle(cornerRadius: min(radius, 13)))
            .overlay {
                RoundedRectangle(cornerRadius: min(radius, 13))
                    .strokeBorder(CLIPStyle.border, lineWidth: 1)
            }
    }
}

private enum CLIPPage: String, CaseIterable {
    case library = "Library"
    case settings = "Settings"
    var symbol: String {
        switch self {
        case .library: "square.stack.3d.up"
        case .settings: "slider.horizontal.3"
        }
    }
}

private struct ClipPreview: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(red: 0.18, green: 0.19, blue: 0.21))
                Image(systemName: "play.rectangle")
                    .font(.system(size: 31, weight: .regular))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 37, height: 37)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .task(id: url) {
            thumbnail = await Task.detached(priority: .utility) {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 360)
                guard let image = try? generator.copyCGImage(
                    at: CMTime(seconds: 0.5, preferredTimescale: 600),
                    actualTime: nil) else { return nil as NSImage? }
                return NSImage(cgImage: image, size: NSSize(width: 640, height: 360))
            }.value
        }
    }
}

struct CLIPView: View {
    @ObservedObject var model: CLIPModel
    @State private var page: CLIPPage = .library
    @State private var selectedClip: ClipItem?
    @State private var clipToDelete: ClipItem?
    @State private var isSelectingClips = false
    @State private var selectedClipIDs: Set<String> = []
    @State private var showBulkDeleteConfirmation = false
    @State private var showSavedToast = false
    @State private var toastGeneration = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("durationSeconds") private var seconds = 30
    @AppStorage("microphone") private var microphone = false
    @AppStorage("systemAudio") private var systemAudio = true
    @AppStorage("resolution") private var resolution = "1080p"
    @AppStorage("framesPerSecond") private var fps = 60
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            ambientBackground
            HStack(alignment: .top, spacing: 25) {
                sidebar
                VStack(alignment: .leading, spacing: 19) {
                    header
                    Group {
                        if page == .library { library }
                        else { settings }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    footer
                }
                .padding(.top, 46)
                .padding(.trailing, 24)
                .padding(.bottom, 17)
            }
        }
        .background(WindowChromeStyler().frame(width: 0, height: 0))
        .overlay(alignment: .bottomTrailing) {
            if showSavedToast {
                Label("Clip saved to your Mac", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CLIPStyle.text)
                    .padding(.horizontal, 17).padding(.vertical, 12)
                    .modifier(FloatingGlass(radius: 17))
                    .padding(.trailing, 31).padding(.bottom, 37)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .preferredColorScheme(.dark)
        .tint(CLIPStyle.accent)
        .sheet(item: $selectedClip) { clip in
            ClipTrimEditor(clip: clip,
                onClose: { selectedClip = nil },
                onSaved: { _ in model.refreshClips() })
        }
        .confirmationDialog("Move this clip to Trash?", isPresented: Binding(
            get: { clipToDelete != nil },
            set: { if !$0 { clipToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let clipToDelete { model.delete(clipToDelete) }
                clipToDelete = nil
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        } message: {
            Text("You can restore the video from Finder's Trash.")
        }
        .confirmationDialog("Move \(selectedClipIDs.count) selected clips to Trash?",
                            isPresented: $showBulkDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Move \(selectedClipIDs.count) to Trash", role: .destructive) {
                model.deleteClips(ids: selectedClipIDs)
                selectedClipIDs.removeAll()
                isSelectingClips = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore these clips from Finder's Trash.")
        }
        .onAppear { model.bootstrap() }
        .onChange(of: seconds) { _, newValue in
            model.setReplayDuration(newValue)
        }
        .onChange(of: model.lastSaved) { _, newFile in
            guard !newFile.isEmpty else { return }
            let generation = UUID()
            toastGeneration = generation
            withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.83)) {
                showSavedToast = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.8))
                guard toastGeneration == generation else { return }
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
                    showSavedToast = false
                }
            }
        }
    }

    private var ambientBackground: some View {
        CLIPStyle.background
            .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: CLIPArtwork.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 31, height: 31)
                    .accessibilityHidden(true)
                Text("CLIP")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(CLIPStyle.text)
            }
            .padding(.bottom, 29)

            ForEach(CLIPPage.allCases, id: \.self) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .regular))
                            .frame(width: 19)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(page == item ? CLIPStyle.text : CLIPStyle.muted)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(page == item ? Color.white.opacity(0.095) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(TactileSidebarButtonStyle())
                .padding(.bottom, 3)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 11) {
                Text("SAVE SHORTCUT")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(CLIPStyle.muted)
                HStack(spacing: 5) {
                    keycap("⌘")
                    keycap("⇧")
                    keycap("S")
                }
                Text("Last \(durationLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(CLIPStyle.muted)
            }
            .padding(.bottom, 24)

            HStack(spacing: 7) {
                Circle()
                    .fill(model.running ? Color(red: 0.47, green: 0.75, blue: 0.59)
                                        : Color.white.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(model.running ? "Recording" : "Paused")
                    .font(.system(size: 11))
                    .foregroundStyle(CLIPStyle.muted)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 48)
        .padding(.bottom, 23)
        .frame(width: 192)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.026))
        .overlay(alignment: .trailing) {
            Rectangle().fill(CLIPStyle.border).frame(width: 1)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium, design: .monospaced))
            .frame(width: 28, height: 27)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(CLIPStyle.border))
    }

    private var durationLabel: String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page == .library ? "Library" : "Settings")
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(CLIPStyle.text)
                Text(page == .library ? "Capture and manage replays." : "Recording and app preferences.")
                    .font(.system(size: 12))
                    .foregroundStyle(CLIPStyle.muted)
            }
            Spacer(minLength: 4)
            HStack(spacing: 7) {
                Circle()
                    .fill(model.running ? Color(red: 0.47, green: 0.75, blue: 0.59) : CLIPStyle.muted)
                    .frame(width: 6, height: 6)
                Text(model.running ? "Recording" : "Paused")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CLIPStyle.muted)
            }
            .padding(.trailing, 8)
            Button {
                if model.running { Task { await model.stop() } }
                else { Task { await model.start() } }
            } label: {
                Label(model.running ? "Pause" : "Start",
                      systemImage: model.running ? "pause.fill" : "record.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(TactileGlassActionStyle())
            .disabled(model.busy)
        }
        .frame(height: 58)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            HStack(spacing: 9) {
                Text("Recent clips")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(model.clips.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(CLIPStyle.muted)
                Spacer()
                if isSelectingClips {
                    Button(selectedClipIDs.count == model.clips.count ? "Deselect all" : "Select all") {
                        if selectedClipIDs.count == model.clips.count {
                            selectedClipIDs.removeAll()
                        } else {
                            selectedClipIDs = Set(model.clips.map(\.id))
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(TactileGlassActionStyle())
                    Button {
                        showBulkDeleteConfirmation = true
                    } label: {
                        Label("Trash \(selectedClipIDs.count)", systemImage: "trash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(TactileGlassActionStyle(prominent: true))
                    .disabled(selectedClipIDs.isEmpty)
                }
                Button {
                    model.refreshClips()
                    selectedClipIDs.formIntersection(Set(model.clips.map(\.id)))
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TactileGlassActionStyle())
                .help("Refresh library")
                .accessibilityLabel("Refresh saved clips")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelectingClips.toggle()
                        selectedClipIDs.removeAll()
                    }
                } label: {
                    Image(systemName: isSelectingClips ? "xmark" : "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(TactileGlassActionStyle())
                .disabled(model.clips.isEmpty)
                .help(isSelectingClips ? "Exit clip selection" : "Select clips to move to Trash")
                .accessibilityLabel(isSelectingClips ? "Exit selection mode" : "Select clips for deletion")
                if !isSelectingClips {
                    Button {
                        model.revealFolder()
                    } label: {
                        Label("Open folder", systemImage: "folder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(TactileGlassActionStyle())
                }
            }
            if model.clips.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 35, weight: .ultraLight))
                        .foregroundStyle(CLIPStyle.muted)
                    Text("No clips yet")
                        .font(.system(size: 15, weight: .medium))
                    Text("Press ⌘⇧S while recording to save a replay.")
                        .font(.system(size: 12))
                        .foregroundStyle(CLIPStyle.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 204)
                .modifier(QuietSurface())
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 380), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(model.clips) { clip in
                            Button {
                                if isSelectingClips {
                                    if selectedClipIDs.contains(clip.id) {
                                        selectedClipIDs.remove(clip.id)
                                    } else {
                                        selectedClipIDs.insert(clip.id)
                                    }
                                } else {
                                    selectedClip = clip
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    ClipPreview(url: clip.url)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            if isSelectingClips {
                                                Image(systemName: selectedClipIDs.contains(clip.id)
                                                      ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 23))
                                                    .foregroundStyle(selectedClipIDs.contains(clip.id)
                                                                     ? CLIPStyle.accent : .white.opacity(0.9))
                                                    .shadow(color: .black.opacity(0.6), radius: 4)
                                                    .padding(14)
                                            }
                                        }
                                        .padding(7)
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(clip.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                                .foregroundStyle(CLIPStyle.text)
                                            Text(clip.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 10))
                                                .foregroundStyle(CLIPStyle.muted)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: isSelectingClips
                                              ? (selectedClipIDs.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                              : "arrow.up.forward")
                                            .font(.system(size: isSelectingClips ? 16 : 10))
                                            .foregroundStyle(selectedClipIDs.contains(clip.id) && isSelectingClips
                                                             ? CLIPStyle.accent : CLIPStyle.muted)
                                    }
                                    .padding(.horizontal, 13)
                                    .padding(.bottom, 13)
                                    .padding(.top, 4)
                                }
                                .modifier(QuietSurface(radius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(selectedClipIDs.contains(clip.id) && isSelectingClips
                                                  ? CLIPStyle.accent.opacity(0.86) : .clear,
                                                  lineWidth: 1.8))
                            }
                            .buttonStyle(TactileClipCardStyle())
                            .contextMenu {
                                Button("Open clip editor") { selectedClip = clip }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                                }
                                Divider()
                                Button("Delete", role: .destructive) { clipToDelete = clip }
                            }
                        }
                    }
                    .padding(2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Replay capture")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(CLIPStyle.text)
                    Text("Save the last \(durationLabel) from your screen.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(CLIPStyle.muted)
                }
                Spacer()
                Button { model.saveReplay() } label: {
                    HStack(spacing: 7) {
                        if model.isSaving {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(model.isSaving ? "Saving…" : "Save replay")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(TactileGlassActionStyle(prominent: true))
                .disabled(!model.running || model.isSaving)
                .help("Save the selected replay length · ⌘⇧S")
            }
            HStack(spacing: 10) {
                Text("Replay length")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CLIPStyle.muted)
                Spacer(minLength: 8)
                ForEach([15, 30, 60, 120, 180, 300, 600], id: \.self) { length in
                    Button {
                        seconds = length
                    } label: {
                        Text(length < 60 ? "\(length)s" : "\(length / 60)m")
                            .font(.system(size: 11, weight: seconds == length ? .semibold : .medium))
                            .foregroundStyle(seconds == length ? CLIPStyle.text : CLIPStyle.muted)
                            .frame(minWidth: 29)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 8)
                            .background(seconds == length ? Color.white.opacity(0.13) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(TactileSegmentButtonStyle())
                    .accessibilityLabel("Replay \(length < 60 ? "\(length) seconds" : "\(length / 60) minutes")")
                }
            }
            .padding(5)
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 9) {
                Circle()
                    .fill(model.running ? Color(red: 0.47, green: 0.75, blue: 0.59) : CLIPStyle.muted)
                    .frame(width: 6, height: 6)
                Text(model.running
                    ? (model.bufferedSeconds >= model.replayTargetSeconds
                        ? "Replay ready"
                        : "Buffering · \(model.bufferedSeconds) of \(model.replayTargetSeconds) seconds")
                    : "Capture paused")
                    .font(.system(size: 11))
                    .foregroundStyle(CLIPStyle.muted)
                Spacer()
                Text("⌘⇧S")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CLIPStyle.muted)
            }
            .accessibilityLabel(model.running
                ? "\(model.bufferedSeconds) of \(model.replayTargetSeconds) replay seconds available"
                : "Recording paused")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(QuietSurface())
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                settingsCard("Instant replay", symbol: "clock.arrow.circlepath", note: "Choose how far back your clips go.") {
                    Text("Save the last")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CLIPStyle.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 65), spacing: 8)], spacing: 8) {
                        ForEach([15, 30, 60, 120, 180, 300, 600], id: \.self) { length in
                            Button {
                                seconds = length
                            } label: {
                                Text(length < 60 ? "\(length)s" : "\(length / 60)m")
                                    .font(.system(size: 12, weight: length == seconds ? .semibold : .medium))
                                    .foregroundStyle(length == seconds ? Color.white : CLIPStyle.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(length == seconds
                                        ? Color.white.opacity(0.13)
                                        : .white.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(CLIPStyle.border))
                            }.buttonStyle(TactileSegmentButtonStyle())
                        }
                    }
                }

                HStack(alignment: .top, spacing: 15) {
                    settingsCard("Audio", symbol: "waveform", note: "Record sound with your clips.") {
                        Toggle("Game / system audio", isOn: $systemAudio)
                        Divider().overlay(.white.opacity(0.07))
                        Toggle("Microphone", isOn: $microphone)
                        Text("Mic permission is only used when enabled.")
                            .font(.system(size: 11))
                            .foregroundStyle(CLIPStyle.muted)
                    }
                    settingsCard("Video quality", symbol: "video", note: "Balance sharpness and performance.") {
                        HStack {
                            Text("Resolution")
                            Spacer()
                            Picker("Resolution", selection: $resolution) {
                                Text("720p").tag("720p")
                                Text("1080p").tag("1080p")
                                Text("1440p").tag("1440p")
                                Text("Native").tag("Native")
                            }.labelsHidden().frame(width: 116)
                        }
                        HStack {
                            Text("Frame rate")
                            Spacer()
                            Picker("Frame rate", selection: $fps) {
                                Text("30 FPS").tag(30)
                                Text("60 FPS").tag(60)
                            }.labelsHidden().frame(width: 116)
                        }
                    }
                }
                .font(.system(size: 12.5))

                settingsCard("Application", symbol: "switch.2", note: "General preferences.") {
                    Toggle("Clip saved notifications", isOn: $showNotifications)
                    Divider().overlay(.white.opacity(0.07))
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            model.updateLaunchAtLogin(enabled)
                        }
                    Divider().overlay(.white.opacity(0.07))
                    Toggle("Subtle trackpad feedback", isOn: $hapticsEnabled)
                    Divider().overlay(.white.opacity(0.07))
                    HStack {
                        Text("Saved to").foregroundStyle(CLIPStyle.muted)
                        Spacer()
                        Button("~/Movies/CLIP") { model.revealFolder() }
                            .buttonStyle(TactileTextButtonStyle())
                    }
                    .font(.system(size: 12))
                }

                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apply changes")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Restarts capture with your new settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(CLIPStyle.muted)
                    }
                    Spacer()
                    Button("Screen recording permissions") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(TactileTextButtonStyle())
                    Button("Apply settings") { model.restart() }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(TactileGlassActionStyle(prominent: true))
                        .disabled(model.busy)
                }
                .padding(17)
                .modifier(QuietSurface(radius: 17))
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
    }

    private func settingsCard<Content: View>(_ title: String, symbol: String, note: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(CLIPStyle.muted)
                    .frame(width: 25, height: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(note).font(.system(size: 11)).foregroundStyle(CLIPStyle.muted)
                }
                Spacer()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(QuietSurface())
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(CLIPStyle.muted)
            Text(model.message)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "lock")
            Text("Stored locally")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(CLIPStyle.muted)
        .padding(.horizontal, 5)
        .frame(height: 22)
    }
}
