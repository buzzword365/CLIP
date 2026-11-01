import SwiftUI
import ScreenCaptureKit
import AVFoundation
import AVKit
import UserNotifications
import ServiceManagement
import Carbon
import AppKit

struct ClipItem: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var date: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

final class GlobalHotkey {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let pointer = userData else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.action() }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | shiftKey),
                            EventHotKeyID(signature: 0x434C4950, id: 1),
                            GetApplicationEventTarget(), 0, &hotkey)
    }
    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class CLIPModel: ObservableObject {
    static let shared = CLIPModel()
    private init() {
        Task { @MainActor [weak self] in self?.bootstrap() }
    }
    @Published var running = false
    @Published var busy = false
    @Published var isSaving = false
    @Published var message = "Ready to capture"
    @Published var clips: [ClipItem] = []
    @Published var lastSaved = ""
    private var engine: ReplayEngine?
    private var hotkey: GlobalHotkey?
    private var bootstrapped = false

    var saveFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/CLIP")
    }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        hotkey = GlobalHotkey { [weak self] in self?.saveReplay() }
        refreshClips()
        updateLaunchAtLogin(UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true)
        if UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        Task { await start() }
    }

    func refreshClips() {
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        clips = ((try? FileManager.default.contentsOfDirectory(
            at: saveFolder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .map(ClipItem.init(url:))
            .sorted { $0.date > $1.date }
    }

    func start() async {
        guard !running && !busy else { return }
        busy = true; message = "Starting screen capture…"
        defer { busy = false }
        let prefs = UserDefaults.standard
        let seconds = prefs.integer(forKey: "durationSeconds")
        let fps = prefs.integer(forKey: "framesPerSecond")
        let config = CaptureOptions(
            seconds: seconds > 0 ? seconds : 30,
            resolution: prefs.string(forKey: "resolution") ?? "1080p",
            fps: fps > 0 ? fps : 60,
            systemAudio: prefs.object(forKey: "systemAudio") as? Bool ?? true,
            microphone: prefs.object(forKey: "microphone") as? Bool ?? false)
        if config.microphone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else {
                message = "Microphone access denied. Enable it in System Settings or turn Mic off."
                return
            }
        }
        let capture = ReplayEngine(options: config)
        capture.onClip = { [weak self] result in
            guard let self else { return }
            self.isSaving = false
            switch result {
            case .success(let url):
                self.message = "Saved: " + url.lastPathComponent
                self.lastSaved = url.lastPathComponent
                self.refreshClips()
                if UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true {
                    let note = UNMutableNotificationContent()
                    note.title = "Clip saved"
                    note.body = url.lastPathComponent
                    note.sound = .default
                    UNUserNotificationCenter.current().add(
                        UNNotificationRequest(identifier: UUID().uuidString,
                                              content: note, trigger: nil)) { _ in }
                }
            case .failure(let error):
                let diagnostic = error as NSError
                self.message = "Clip failed (\(diagnostic.domain):\(diagnostic.code)): " + diagnostic.localizedDescription
                NSLog("CLIP export error: %@", String(describing: error))
            }
        }
        capture.onFailure = { [weak self] error in
            self?.message = "Capture error: " + error
            self?.isSaving = false
        }
        do {
            try await capture.start()
            self.engine = capture
            running = true
            message = "Recording rolling buffer — ⌘⇧S saves the last \(config.seconds)s"
        } catch {
            let detail = error as NSError
            NSLog("CLIP capture start error: domain=%@ code=%ld detail=%@", detail.domain, detail.code, String(describing: detail))
            message = error.localizedDescription.localizedCaseInsensitiveContains("TCC")
                ? "Screen recording access required. Enable CLIP in System Settings, then press Start."
                : "Cannot start capture: " + error.localizedDescription
        }
    }

    func stop() async {
        guard running, !busy else { return }
        busy = true
        let old = engine
        engine = nil
        running = false
        await old?.stop()
        message = "Capture paused"
        busy = false
    }

    func restart() {
        Task {
            if running { await stop() }
            await start()
        }
    }

    func saveReplay() {
        guard running, let engine else {
            message = "Start recording before saving a clip."
            return
        }
        // A quick double-click or repeating global hotkey must not export duplicate clips.
        guard !isSaving else { return }
        isSaving = true
        message = "Saving replay…"
        engine.saveLastSeconds()
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(saveFolder)
    }

    // Recoverable deletion: user clips go to Finder's Trash, not permanent removal.
    func delete(_ clip: ClipItem) {
        deleteClips(ids: [clip.id])
    }

    func deleteClips(ids: Set<String>) {
        let targets = clips.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        var moved = 0
        var firstError: Error?
        for clip in targets {
            do {
                try FileManager.default.trashItem(at: clip.url, resultingItemURL: nil)
                moved += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        refreshClips()
        if let firstError {
            message = "Moved \(moved) clip(s) to Trash; some failed: " + firstError.localizedDescription
        } else {
            message = "Moved \(moved) clip(s) to Trash"
        }
    }

    func setReplayDuration(_ seconds: Int) {
        engine?.setReplayDuration(seconds)
        if running {
            message = "Replay set to \(seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"). Longer replays fill as recording continues."
        }
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            message = "Login item: " + error.localizedDescription
        }
    }

    private var fallbackWindow: NSWindow?
    func openAppWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: {
            $0.canBecomeKey && $0.isVisible && $0.frame.width > 500
        }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        if let window = fallbackWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "CLIP"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 960, height: 660)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentView = NSHostingView(rootView: CLIPView(model: self))
        window.isReleasedWhenClosed = false
        window.center()
        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct CLIPMenu: View {
    @ObservedObject var model: CLIPModel
    var body: some View {
        Text(model.running ? "Replay capture active" : "Replay capture paused")
        Button(model.isSaving ? "Saving replay…" : "Save last replay  ⌘⇧S") {
            model.saveReplay()
        }
        .disabled(!model.running || model.isSaving)
        Button(model.running ? "Pause capture" : "Start capture") {
            if model.running { Task { await model.stop() } }
            else { Task { await model.start() } }
        }
        Divider()
        Button("Open CLIP") { model.openAppWindow() }
        Button("Open clip folder") { model.revealFolder() }
        Divider()
        Button(model.isSaving ? "Finishing clip…" : "Quit CLIP") {
            NSApplication.shared.terminate(nil)
        }
        .disabled(model.isSaving)
    }
}

@MainActor
final class CLIPAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // The resource icon is explicitly applied at runtime so Dock does not
        // retain the generic placeholder from the app's first unsigned builds.
        if let url = Bundle.main.url(forResource: "CLIPLogo", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        CLIPModel.shared.openAppWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag { CLIPModel.shared.openAppWindow() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = CLIPModel.shared
        guard !model.isSaving else {
            model.message = "Finish saving your current clip before quitting."
            return .terminateCancel
        }
        guard model.running else { return .terminateNow }
        Task { @MainActor in
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct CLIPApp: App {
    @NSApplicationDelegateAdaptor(CLIPAppDelegate.self) private var delegate
    @StateObject private var model = CLIPModel.shared
    var body: some Scene {
        // One AppKit-managed window prevents duplicate SwiftUI WindowGroup scenes
        // and makes menu-bar reopening reliable after the user closes the window.
        MenuBarExtra("CLIP", systemImage: "record.circle") {
            CLIPMenu(model: model)
        }
    }
}
