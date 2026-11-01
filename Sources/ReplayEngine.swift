import Foundation
import Darwin
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import AppKit

struct CaptureOptions {
    let seconds: Int
    let resolution: String
    let fps: Int
    let systemAudio: Bool
    let microphone: Bool
}

private final class Segment {
    let url: URL
    let writer: AVAssetWriter
    let video: AVAssetWriterInput
    let system: AVAssetWriterInput?
    let microphone: AVAssetWriterInput?
    let start: CMTime
    var last: CMTime
    let startedAt: TimeInterval
    var endedAt: TimeInterval
    init(url: URL, writer: AVAssetWriter, video: AVAssetWriterInput,
         system: AVAssetWriterInput?, microphone: AVAssetWriterInput?,
         start: CMTime, uptime: TimeInterval) {
        self.url = url; self.writer = writer; self.video = video
        self.system = system; self.microphone = microphone
        self.start = start; self.last = start
        self.startedAt = uptime; self.endedAt = uptime
    }
    var length: Double { max(0, CMTimeGetSeconds(last - start)) }
}

final class ReplayEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onClip: ((Result<URL, Error>) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStalled: (() -> Void)?
    var onBufferProgress: ((Int, Int) -> Void)?
    private let options: CaptureOptions
    private var replaySeconds: Int
    private let queue = DispatchQueue(label: "com.clip.encoder", qos: .userInitiated)
    private var stream: SCStream?
    private var active: Segment?
    private var finished: [Segment] = []
    private struct ReplayRequest {
        let seconds: Int
        let requestedAt: TimeInterval
    }
    private var pending: [ReplayRequest] = []
    private var watchdog: DispatchSourceTimer?
    private var captureStartedAt: TimeInterval = 0
    private var lastScreenEventAt: TimeInterval = 0
    private var lastReportedProgress = -1
    private var lastReportedTarget = -1
    private var lastFrameWrittenAt: TimeInterval = 0
    private var latestSourceFrameAt: TimeInterval = 0
    private var latestSourceBuffer: CMSampleBuffer?
    private var lastWrittenPTS = CMTime.invalid
    private var screenIsBlankOrSuspended = false
    private var stalledReported = false
    private var busyExports: Set<URL> = []
    private var isStopping = false
    private var pendingFinalizations = 0
    private var closeWaiters: [() -> Void] = []
    private var width = 1920
    private var height = 1080
    private let bufferDirectory: URL
    private let clipsDirectory: URL

    init(options: CaptureOptions) {
        self.options = options
        self.replaySeconds = options.seconds
        let fm = FileManager.default
        let bufferRoot = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CLIP/Buffer", isDirectory: true)
        let sessionName = "pid-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
        bufferDirectory = bufferRoot.appendingPathComponent(sessionName, isDirectory: true)
        clipsDirectory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/CLIP", isDirectory: true)
        super.init()
        try? fm.createDirectory(at: bufferDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        // Never delete segments from another live recording/export.
        // Sweep abandoned sessions after one day; active sessions remove their own buffers on stop.
        if let entries = try? fm.contentsOfDirectory(at: bufferRoot,
                     includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry != bufferDirectory {
                let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let age = Date().timeIntervalSince(modified)
                let components = entry.lastPathComponent.split(separator: "-")
                if components.count >= 3, components[0] == "pid",
                   let owner = Int32(components[1]), owner > 0 {
                    // New-format directories are removed as soon as their owning
                    // process has exited. Never touch a still-running session.
                    if kill(owner, 0) == -1 && errno == ESRCH {
                        try? fm.removeItem(at: entry)
                    }
                } else if age > 600 {
                    // Earlier builds used UUID-only directories with no owner marker.
                    // Preserve very recent files, but do not retain abandoned buffers forever.
                    try? fm.removeItem(at: entry)
                }
            }
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "CLIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display available for capture."])
        }
        let maxHeight = options.resolution == "720p" ? 720 :
            options.resolution == "1440p" ? 1440 :
            options.resolution == "Native" ? display.height : 1080
        let ratio = min(1.0, Double(maxHeight) / Double(display.height))
        width = max(2, Int(Double(display.width) * ratio) / 2 * 2)
        height = max(2, Int(Double(display.height) * ratio) / 2 * 2)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5
        config.showsCursor = true
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.captureMicrophone = options.microphone

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio { try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if options.microphone { try newStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        stream = newStream
        try await newStream.startCapture()
        queue.async {
            self.captureStartedAt = ProcessInfo.processInfo.systemUptime
            self.installWatchdog()
        }
    }

    private func installWatchdog() {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // ScreenCaptureKit does NOT generate new .complete frames while the
        // desktop is unchanged. Keep writing the last visible image with fresh
        // timestamps so a quiet/idle screen still has a real 30-second replay.
        timer.schedule(deadline: .now() + .milliseconds(250),
                       repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopping else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.appendStillFrameIfNeeded(at: now)

            let window = self.finished.map {
                ReplaySegmentInfo(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                  mediaDuration: $0.length)
            } + (self.active.flatMap { segment in
                segment.length > 0.1
                    ? [ReplaySegmentInfo(startedAt: segment.startedAt,
                                         endedAt: segment.endedAt,
                                         mediaDuration: segment.length)] : nil
            } ?? [])
            let result = ReplayWindowPolicy.evaluate(window,
                seconds: self.replaySeconds, requestedAt: now)
            let available: Int
            switch result {
            case .ready: available = self.replaySeconds
            case .warmingUp(let length, _): available = length
            case .stalled: available = 0
            }
            if available != self.lastReportedProgress ||
               self.replaySeconds != self.lastReportedTarget {
                self.lastReportedProgress = available
                self.lastReportedTarget = self.replaySeconds
                DispatchQueue.main.async {
                    self.onBufferProgress?(available, self.replaySeconds)
                }
            }

            // A genuinely stalled INITIAL stream is different from a static
            // screen. After the first frame, continue buffering the last frame
            // until an explicit blank/suspended status or stream error occurs.
            if self.latestSourceBuffer == nil && !self.stalledReported &&
                self.captureStartedAt > 0 &&
                now - self.captureStartedAt > 15 {
                self.stalledReported = true
                DispatchQueue.main.async { self.onStalled?() }
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func appendStillFrameIfNeeded(at now: TimeInterval) {
        guard !isStopping, !screenIsBlankOrSuspended,
              let previous = latestSourceBuffer,
              latestSourceFrameAt > 0,
              now - lastFrameWrittenAt >= 0.20 else { return }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(previous)
        guard sourcePTS.isValid else { return }
        let elapsed = now - latestSourceFrameAt
        guard elapsed >= 0 else { return }

        // Give the last visible frame a new timestamp without duplicating
        // the stale PTS that made AVAssetWriter reject static-screen samples.
        let newPTS = sourcePTS + CMTime(seconds: elapsed,
                                        preferredTimescale: 60000)
        guard let copy = CLIPFrameRetiming.copy(previous, at: newPTS) else {
            report("Could not extend the recording on an unchanged screen.")
            return
        }
        appendVideoSample(copy, at: now)
    }

    private func appendVideoSample(_ buffer: CMSampleBuffer, at now: TimeInterval) {
        guard !isStopping else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard pts.isValid,
              !lastWrittenPTS.isValid ||
              CMTimeCompare(pts, lastWrittenPTS) > 0 else { return }

        if let segment = active {
            // A real interrupted capture must not be joined across a long gap.
            if now - segment.endedAt > 2.5 ||
                CMTimeGetSeconds(pts - segment.start) >= 3.0 {
                closeSegment()
            }
        }
        if active == nil {
            do { active = try createSegment(start: pts) }
            catch { report(error.localizedDescription); return }
        }
        guard let segment = active, segment.video.isReadyForMoreMediaData else {
            return
        }
        if segment.video.append(buffer) {
            segment.last = pts
            segment.endedAt = now
            lastFrameWrittenAt = now
            lastWrittenPTS = pts
        } else {
            report(segment.writer.error?.localizedDescription ??
                   "Unable to encode a replay video frame.")
        }
    }

    func stop() async {
        do { try await stream?.stopCapture() } catch { }
        stream = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.isStopping = true
                self.watchdog?.cancel()
                self.watchdog = nil
                self.closeSegment(onClosed: { continuation.resume() })
            }
        }
    }

    func setReplayDuration(_ seconds: Int) {
        queue.async {
            self.replaySeconds = max(15, min(600, seconds))
            self.pruneBuffer()
        }
    }

    func saveLastSeconds() {
        queue.async {
            self.pending.append(ReplayRequest(
                seconds: self.replaySeconds,
                requestedAt: ProcessInfo.processInfo.systemUptime))
            if self.active != nil {
                self.closeSegment()
            } else {
                self.flushCompletedSegments()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onFailure?(error.localizedDescription) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard buffer.isValid, CMSampleBufferDataIsReady(buffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if type == .screen {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
            let value = attachments?.first?[.status] as? Int
            guard let value, let status = SCFrameStatus(rawValue: value) else { return }
            lastScreenEventAt = now
            switch status {
            case .complete, .started:
                guard CMSampleBufferGetImageBuffer(buffer) != nil else { return }
                screenIsBlankOrSuspended = false
                latestSourceBuffer = buffer
                latestSourceFrameAt = now
                appendVideoSample(buffer, at: now)
            case .idle:
                // This is NORMAL when nothing on the desktop has changed.
                // Timer-generated samples extend the last visible image.
                screenIsBlankOrSuspended = false
            case .blank, .suspended, .stopped:
                screenIsBlankOrSuspended = true
                // Stop using the old still if the display went away. After
                // unlock, the next real frame starts a fresh contiguous run.
                latestSourceBuffer = nil
                if active != nil { closeSegment() }
            @unknown default:
                break
            }
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard pts.isValid, let segment = active,
              CMTimeCompare(pts, segment.start) >= 0 else { return }
        if type == .audio {
            if let input = segment.system, input.isReadyForMoreMediaData {
                _ = input.append(buffer)
            }
        } else if type == .microphone {
            if let input = segment.microphone, input.isReadyForMoreMediaData {
                _ = input.append(buffer)
            }
        }
    }

    private func createSegment(start: CMTime) throws -> Segment {
        let url = bufferDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = false
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.resolution == "720p" ? 5_000_000 : 10_000_000,
                AVVideoExpectedSourceFrameRateKey: options.fps,
                AVVideoMaxKeyFrameIntervalKey: options.fps
            ]
        ]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw err("Cannot create H.264 video encoder.") }
        writer.add(video)

        func audioInput(channels: Int) -> AVAssetWriterInput? {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48000, AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input); return input }
            return nil
        }
        let system = options.systemAudio ? audioInput(channels: 2) : nil
        let microphone = options.microphone ? audioInput(channels: 1) : nil
        guard writer.startWriting() else {
            throw writer.error ?? err("Could not start the recording encoder.")
        }
        writer.startSession(atSourceTime: start)
        return Segment(url: url, writer: writer, video: video, system: system,
                       microphone: microphone, start: start,
                       uptime: ProcessInfo.processInfo.systemUptime)
    }

    // One segment can be encoding while another is already recording.
    // Wait for ALL pending writers before servicing a replay request or ending a session.
    private func closeSegment(onClosed: (() -> Void)? = nil) {
        if let onClosed { closeWaiters.append(onClosed) }
        guard let segment = active else {
            flushCompletedSegments()
            return
        }
        active = nil
        pendingFinalizations += 1
        segment.video.markAsFinished()
        segment.system?.markAsFinished()
        segment.microphone?.markAsFinished()
        segment.writer.finishWriting {
            self.queue.async {
                self.pendingFinalizations -= 1
                if segment.writer.status == .completed && segment.length > 0.1 {
                    self.finished.append(segment)
                    self.finished.sort { CMTimeCompare($0.start, $1.start) < 0 }
                    self.pruneBuffer()
                } else {
                    try? FileManager.default.removeItem(at: segment.url)
                    if let error = segment.writer.error {
                        self.report(error.localizedDescription)
                    }
                }
                self.flushCompletedSegments()
            }
        }
    }

    private func flushCompletedSegments() {
        guard pendingFinalizations == 0 else { return }
        completePending()
        let waiters = closeWaiters
        closeWaiters.removeAll()
        waiters.forEach { $0() }
        cleanupAfterStop()
    }

    private func cleanupAfterStop() {
        guard isStopping && pendingFinalizations == 0 &&
                pending.isEmpty && busyExports.isEmpty else { return }
        finished.removeAll()
        try? FileManager.default.removeItem(at: bufferDirectory)
    }

    private func pruneBuffer() {
        let now = ProcessInfo.processInfo.systemUptime
        let keep = Double(max(replaySeconds, 30) + 14)
        // A completed segment's file can be valid even after ScreenCaptureKit
        // has stopped delivering frames. Expire it by actual elapsed time.
        while let first = finished.first,
              first.endedAt < now - keep {
            finished.removeFirst()
            if !busyExports.contains(first.url) {
                try? FileManager.default.removeItem(at: first.url)
            }
        }
        var duration = finished.reduce(0) { $0 + $1.length }
        while finished.count > 1 && duration > keep {
            let oldest = finished.removeFirst()
            duration -= oldest.length
            if !busyExports.contains(oldest.url) {
                try? FileManager.default.removeItem(at: oldest.url)
            }
        }
    }

    private func completePending() {
        guard !pending.isEmpty else { return }
        let requests = pending
        pending.removeAll()
        for request in requests {
            let window = finished.map {
                ReplaySegmentInfo(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                  mediaDuration: $0.length)
            }
            let selection = ReplayWindowPolicy.evaluate(
                window, seconds: request.seconds, requestedAt: request.requestedAt)
            let indices: [Int]
            switch selection {
            case .ready(let ready):
                indices = ready
            case .warmingUp(let available, let required):
                // On the first seconds after launch, save what's genuinely
                // recorded, even though a full 30-second history does not yet exist.
                guard let partial = ReplayWindowPolicy.availableNow(
                    window, seconds: request.seconds, requestedAt: request.requestedAt)
                else {
                    let message = "CLIP is starting capture (\(available)/\(required)s). " +
                        "Try the shortcut again in a moment."
                    DispatchQueue.main.async { self.onClip?(.failure(self.err(message))) }
                    continue
                }
                indices = partial
            case .stalled(let age):
                let message = "No new screen footage for \(age) seconds. " +
                    "CLIP is reconnecting; press Start if capture is paused."
                DispatchQueue.main.async { self.onClip?(.failure(self.err(message))) }
                NSLog("CLIP replay capture stale: %d seconds", age)
                continue
            }
            let chosen = indices.map { finished[$0] }
            let urls = chosen.map(\.url)
            busyExports.formUnion(urls)
            let availableSeconds = chosen.reduce(0.0) { $0 + $1.length }
            let isShort = availableSeconds < Double(request.seconds) - 1.25
            let shortLabel = isShort ? " - Short \(max(1, Int(availableSeconds.rounded())))s" : ""
            let output = clipsDirectory.appendingPathComponent(
                "CLIP " + Self.fileDateFormatter.string(from: Date()) + " " +
                UUID().uuidString.prefix(5) + shortLabel + ".mp4")
            DispatchQueue.global(qos: .userInitiated).async {
                Self.export(segments: chosen, seconds: request.seconds, output: output) { result in
                    self.queue.async {
                        self.busyExports.subtract(urls)
                        self.pruneBuffer()
                        for url in urls where !self.finished.contains(where: { $0.url == url }) {
                            try? FileManager.default.removeItem(at: url)
                        }
                        self.cleanupAfterStop()
                        DispatchQueue.main.async { self.onClip?(result) }
                    }
                }
            }
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f
    }()

    private static func export(segments: [Segment], seconds: Int, output: URL,
                               completion: @escaping (Result<URL, Error>) -> Void) {
        let assetList = segments.map { AVURLAsset(url: $0.url) }
        let composition = AVMutableComposition()
        guard let movieTrack = composition.addMutableTrack(withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(NSError(domain: "CLIP", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot create clip video track."])))
            return
        }
        let audioTrackCount = assetList.map { $0.tracks(withMediaType: .audio).count }.max() ?? 0
        let audioOne = audioTrackCount >= 1
            ? composition.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        let audioTwo = audioTrackCount >= 2
            ? composition.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid) : nil
        // The audio sample stream can extend a few milliseconds beyond the video.
        // Build ranges from each VIDEO track, not AVAsset.duration, or insertion fails.
        let videoTracks = assetList.map { $0.tracks(withMediaType: .video).first }
        let total = videoTracks.compactMap { $0?.timeRange.duration.seconds }.reduce(0, +)
        var trim = max(0, total - Double(seconds))
        var position = CMTime.zero
        do {
            for (index, asset) in assetList.enumerated() {
                guard let sourceVideo = videoTracks[index] else { continue }
                let available = max(0, sourceVideo.timeRange.duration.seconds)
                if trim >= available { trim -= available; continue }
                let trimTime = CMTime(seconds: trim, preferredTimescale: 60000)
                let start = sourceVideo.timeRange.start + trimTime
                let duration = sourceVideo.timeRange.duration - trimTime
                guard duration.seconds > 0 else { continue }
                let videoRange = CMTimeRange(start: start, duration: duration)
                try movieTrack.insertTimeRange(videoRange, of: sourceVideo, at: position)
                let sourceAudio = asset.tracks(withMediaType: .audio)
                let destAudio = [audioOne, audioTwo]
                for (trackIndex, audioTrack) in sourceAudio.prefix(2).enumerated() {
                    guard let outputTrack = destAudio[trackIndex] else { continue }
                    let overlap = CMTimeRangeGetIntersection(videoRange, otherRange: audioTrack.timeRange)
                    if !overlap.isEmpty && overlap.duration.seconds > 0 {
                        let at = position + (overlap.start - videoRange.start)
                        try? outputTrack.insertTimeRange(overlap, of: audioTrack, at: at)
                    }
                }
                position = position + videoRange.duration
                trim = 0
            }
        } catch { completion(.failure(error)); return }
        guard position.seconds > 0,
              let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(NSError(domain: "CLIP", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Not enough video to export."])))
            return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let first = audioOne, let second = audioTwo {
            let primary = AVMutableAudioMixInputParameters(track: first)
            let mic = AVMutableAudioMixInputParameters(track: second)
            primary.setVolume(1.0, at: .zero)
            mic.setVolume(1.0, at: .zero)
            let mix = AVMutableAudioMix()
            mix.inputParameters = [primary, mic]
            session.audioMix = mix
        }
        session.exportAsynchronously {
            if session.status == .completed {
                completion(.success(output))
            } else {
                completion(.failure(session.error ?? NSError(domain: "CLIP", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Clip export failed."])))
            }
        }
    }

    private func err(_ message: String) -> NSError {
        NSError(domain: "CLIP", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func report(_ message: String) {
        DispatchQueue.main.async { self.onFailure?(message) }
    }
}
#if DEBUG_EXPORT
extension ReplayEngine {
    static func testExport(_ urls: [URL], output: URL) {
        do {
            let segments: [Segment] = try urls.enumerated().map { index, url in
                let dummyURL = URL(fileURLWithPath: "/tmp/clip-export-test/unused-\(index)-\(UUID().uuidString).mov")
                let writer = try AVAssetWriter(outputURL: dummyURL, fileType: .mov)
                let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
                return Segment(url: url, writer: writer, video: video,
                               system: nil, microphone: nil, start: .zero)
            }
            export(segments: segments, seconds: 5, output: output) { result in
                switch result {
                case .success(let url): print("EXPORT SUCCESS", url.path); exit(0)
                case .failure(let error): print("EXPORT FAILURE", error); exit(1)
                }
            }
        } catch { print("SETUP FAILURE", error); exit(2) }
    }
}
#endif
