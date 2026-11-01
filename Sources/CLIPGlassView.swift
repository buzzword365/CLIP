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
    static let accent = Color(red: 0.53, green: 0.76, blue: 1.0)
    static let lavender = Color(red: 0.70, green: 0.64, blue: 1.0)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.54)
    static let border = Color.white.opacity(0.11)
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
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(.regularMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(CLIPStyle.border, lineWidth: 1))
        }
    }
}

private struct QuietSurface: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Color(red: 0.085, green: 0.105, blue: 0.15).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [
                    .white.opacity(0.16), .white.opacity(0.025), .white.opacity(0.065)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
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
                    .fill(LinearGradient(colors: [
                        Color(red: 0.17, green: 0.24, blue: 0.34),
                        Color(red: 0.10, green: 0.11, blue: 0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.rectangle")
                    .font(.system(size: 31, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 39, height: 39)
                .background(.black.opacity(0.44), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.19)))
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
            HStack(alignment: .top, spacing: 18) {
                sidebar
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Group {
                        if page == .library { library }
                        else { settings }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    footer
                }
                .padding(.trailing, 16)
            }
            .padding(.top, 51)
            .padding(.leading, 16)
            .padding(.bottom, 16)
        }
        .background(WindowChromeStyler().frame(width: 0, height: 0))
        .overlay(alignment: .bottomTrailing) {
            if showSavedToast {
                Label("Clip saved to your Mac", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.67, green: 0.98, blue: 0.82))
                    .padding(.horizontal, 17).padding(.vertical, 12)
                    .modifier(FloatingGlass(radius: 17))
                    .padding(.trailing, 31).padding(.bottom, 37)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 960, minHeight: 660)
        .preferredColorScheme(.dark)
        .tint(CLIPStyle.accent)
        .sheet(item: $selectedClip) { clip in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.name).font(.title3.weight(.semibold))
                        Text(clip.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(CLIPStyle.muted)
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([clip.url])
                    }
                    .buttonStyle(TactileGlassActionStyle())
                    Button {
                        selectedClip = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(TactileGlassActionStyle())
                    .keyboardShortcut(.cancelAction)
                    .help("Close preview")
                    .accessibilityLabel("Close clip preview")
                }
                NativeClipPlayer(url: clip.url)
                    .frame(minWidth: 660, minHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(22)
            .frame(minWidth: 720, minHeight: 470)
            .background(.regularMaterial)
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
        GeometryReader { size in
            ZStack {
                if reduceTransparency {
                    Color(red: 0.09, green: 0.12, blue: 0.17)
                } else {
                    GlassWindowBackdrop()
                    Color(red: 0.045, green: 0.066, blue: 0.108).opacity(0.65)
                    RadialGradient(colors: [
                        CLIPStyle.accent.opacity(0.19), .clear
                    ], center: .center, startRadius: 15, endRadius: 420)
                    .frame(width: 670, height: 670)
                    .position(x: size.size.width * 0.80, y: 12)
                    RadialGradient(colors: [
                        CLIPStyle.lavender.opacity(0.12), .clear
                    ], center: .center, startRadius: 5, endRadius: 350)
                    .frame(width: 620, height: 620)
                    .position(x: 80, y: size.size.height * 0.98)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: CLIPArtwork.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 39, height: 39)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLIP")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(2.3)
                    Text("INSTANT REPLAY")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(CLIPStyle.muted)
                }
            }
            .padding(.bottom, 43)

            Text("WORKSPACE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.37))
                .padding(.leading, 12)
                .padding(.bottom, 11)

            ForEach(CLIPPage.allCases, id: \.self) { item in
                Button {
                    withAnimation(.smooth(duration: 0.23)) { page = item }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 20)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: page == item ? .semibold : .medium))
                        Spacer()
                        if page == item {
                            Circle().fill(CLIPStyle.accent).frame(width: 5, height: 5)
                        }
                    }
                    .foregroundStyle(page == item ? CLIPStyle.text : CLIPStyle.muted)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .background(page == item ? .white.opacity(0.105) : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(TactileSidebarButtonStyle())
                .padding(.bottom, 5)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12)).foregroundStyle(CLIPStyle.muted)
                    Text("SAVE A MOMENT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.05).foregroundStyle(CLIPStyle.muted)
                }
                HStack(spacing: 5) {
                    keycap("⌘")
                    keycap("⇧")
                    keycap("S")
                }
                Text("\(durationLabel) replay")
                    .font(.system(size: 11)).foregroundStyle(CLIPStyle.muted)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(QuietSurface(radius: 16))

            HStack(spacing: 7) {
                Circle()
                    .fill(model.running ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(model.running ? "Capture active" : "Capture paused")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CLIPStyle.muted)
            }
            .padding(.top, 20)
            .padding(.leading, 8)
        }
        .padding(17)
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .modifier(FloatingGlass(radius: 23))
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .medium, design: .rounded))
            .frame(width: 31, height: 29)
            .background(.white.opacity(0.095), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CLIPStyle.border))
    }

    private var durationLabel: String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text(page == .library ? "Your moments" : "Preferences")
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .tracking(-0.65)
                    .foregroundStyle(CLIPStyle.text)
                Text(page == .library
                     ? "Keep what matters. Everything stays on your Mac."
                     : "A personal setup for every session.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CLIPStyle.muted)
            }
            Spacer(minLength: 4)
            Label(model.running ? "Recording" : "Paused",
                  systemImage: model.running ? "circle.fill" : "pause.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.running ? Color(red: 0.60, green: 0.96, blue: 0.78) : CLIPStyle.muted)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .modifier(FloatingGlass(radius: 30))
            Button {
                if model.running { Task { await model.stop() } }
                else { Task { await model.start() } }
            } label: {
                Label(model.running ? "Pause" : "Start",
                      systemImage: model.running ? "pause.fill" : "record.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(TactileGlassActionStyle())
            .disabled(model.busy)
        }
        .frame(height: 66)
        .padding(.horizontal, 4)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            HStack(spacing: 9) {
                Text("Recent clips")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("\(model.clips.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CLIPStyle.muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.white.opacity(0.09), in: Capsule())
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
                        .foregroundStyle(CLIPStyle.accent.opacity(0.70))
                    Text("It's quiet here")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Your saved replays will appear here.\nCapture a moment with ⌘⇧S.")
                        .font(.system(size: 12))
                        .foregroundStyle(CLIPStyle.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 204)
                .modifier(QuietSurface())
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 380), spacing: 15)],
                              alignment: .leading, spacing: 15) {
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
                                        .clipShape(RoundedRectangle(cornerRadius: 13))
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
                                        .padding(8)
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
                                .modifier(QuietSurface(radius: 19))
                                .overlay(RoundedRectangle(cornerRadius: 19)
                                    .strokeBorder(selectedClipIDs.contains(clip.id) && isSelectingClips
                                                  ? CLIPStyle.accent.opacity(0.86) : .clear,
                                                  lineWidth: 1.8))
                            }
                            .buttonStyle(TactileClipCardStyle())
                            .contextMenu {
                                Button("Play clip") { selectedClip = clip }
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
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.running ? Color.green : .orange)
                        .frame(width: 6, height: 6)
                    Text(model.running ? "READY WHEN YOU ARE" : "CAPTURE IS PAUSED")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.55)
                        .foregroundStyle(CLIPStyle.muted)
                }
                Text("Never miss a\nmoment.")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.7)
                    .lineSpacing(0)
                    .foregroundStyle(CLIPStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Instantly save your last \(durationLabel) of gameplay.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CLIPStyle.muted)
                HStack(spacing: 7) {
                    Image(systemName: model.bufferedSeconds >= model.replayTargetSeconds && model.running
                          ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                        .foregroundStyle(model.bufferedSeconds >= model.replayTargetSeconds && model.running
                                         ? Color.green : CLIPStyle.accent)
                    Text(model.running
                         ? (model.bufferedSeconds >= model.replayTargetSeconds
                            ? "Replay ready"
                            : "Buffering: \(model.bufferedSeconds)/\(model.replayTargetSeconds)s")
                         : "Recording paused")
                        .foregroundStyle(CLIPStyle.muted)
                }
                .font(.system(size: 11, weight: .medium))
                .accessibilityLabel(model.running
                    ? "\(model.bufferedSeconds) of \(model.replayTargetSeconds) replay seconds available"
                    : "Recording paused")
                HStack(spacing: 10) {
                    Button { model.saveReplay() } label: {
                        HStack(spacing: 7) {
                            if model.isSaving {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text(model.isSaving ? "Saving…" : "Save replay")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(TactileGlassActionStyle(prominent: true))
                    .disabled(!model.running || model.isSaving)
                    HStack(spacing: 5) {
                        Text("⌘").font(.system(size: 12, weight: .medium))
                        Text("⇧").font(.system(size: 12, weight: .medium))
                        Text("S").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(CLIPStyle.muted)
                }.padding(.top, 3)
            }
            Spacer(minLength: 4)
            VStack(spacing: 5) {
                ReplayDurationDial(seconds: $seconds)
                    .help("Drag the outer ring clockwise or anticlockwise to change replay length.")
                Text("DRAG TO ADJUST")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(CLIPStyle.muted)
            }
            .frame(width: 206)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(QuietSurface(radius: 23))
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                settingsCard("Instant replay", symbol: "clock.arrow.circlepath", note: "Choose how far back your clips go.") {
                    Text("SAVE THE LAST")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.15).foregroundStyle(CLIPStyle.muted)
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
                                        ? CLIPStyle.accent.opacity(0.27)
                                        : .white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 11))
                                    .overlay(RoundedRectangle(cornerRadius: 11)
                                        .strokeBorder(length == seconds
                                            ? CLIPStyle.accent.opacity(0.4)
                                            : CLIPStyle.border))
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

                settingsCard("Application", symbol: "switch.2", note: "Little things that make CLIP yours.") {
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
                    .foregroundStyle(CLIPStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(note).font(.system(size: 11)).foregroundStyle(CLIPStyle.muted)
                }
                Spacer()
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(QuietSurface(radius: 19))
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path")
                .font(.system(size: 11))
                .foregroundStyle(CLIPStyle.accent)
            Text(model.message)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "lock.shield")
            Text("Private · On this Mac")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(CLIPStyle.muted)
        .padding(.horizontal, 5)
        .frame(height: 22)
    }
}
