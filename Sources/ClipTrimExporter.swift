import Foundation
import AVFoundation

enum ClipTrimError: LocalizedError {
    case invalidRange
    case noVideo
    case unavailableExporter
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .invalidRange: "Select a valid section of the clip before saving."
        case .noVideo: "This file does not contain a playable video track."
        case .unavailableExporter: "macOS could not create a video exporter for this clip."
        case .invalidOutput: "The trimmed video could not be verified."
        }
    }
}

/// Exports a new MP4. The original URL is never overwritten or deleted.
/// Highest-quality re-encoding avoids inaccurate start points on non-keyframes.
enum ClipTrimExporter {
    static func export(source: URL,
                       start: Double,
                       end: Double,
                       outputDirectory: URL) async throws -> URL {
        guard source.isFileURL, start.isFinite, end.isFinite,
              start >= 0, end - start >= 0.25 else {
            throw ClipTrimError.invalidRange
        }

        let asset = AVURLAsset(url: source)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw ClipTrimError.noVideo }
        guard duration.isFinite, duration > 0,
              start <= duration - 0.25, end <= duration + 0.05 else {
            throw ClipTrimError.invalidRange
        }
        let clampedEnd = min(end, duration)
        try FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent
        let out = outputDirectory.appendingPathComponent(
            "\(stem) - Trimmed \(UUID().uuidString.prefix(6)).mp4")
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipTrimError.unavailableExporter
        }
        let startTime = CMTime(seconds: start, preferredTimescale: 60000)
        let endTime = CMTime(seconds: clampedEnd, preferredTimescale: 60000)
        session.timeRange = CMTimeRange(start: startTime, end: endTime)
        session.shouldOptimizeForNetworkUse = true

        do {
            try await session.export(to: out, as: .mp4)
            let result = AVURLAsset(url: out)
            let actualTime = try await result.load(.duration)
            let actual = CMTimeGetSeconds(actualTime)
            let tracks = try await result.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty, actual.isFinite, actual > 0,
                  abs(actual - (clampedEnd - start)) < 0.55 else {
                throw ClipTrimError.invalidOutput
            }
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }
}
