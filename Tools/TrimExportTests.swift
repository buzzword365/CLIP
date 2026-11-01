import Foundation
import AVFoundation

@main struct TrimExportTests {
    static func main() async throws {
        guard CommandLine.arguments.count >= 3 else {
            fatalError("Usage: trim-test <source mp4> <output directory>")
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
        let sourceAsset = AVURLAsset(url: source)
        let originalDuration = CMTimeGetSeconds(try await sourceAsset.load(.duration))
        let originalSize = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as! NSNumber
        guard originalDuration >= 12 else { fatalError("Test source needs >= 12 seconds") }
        let cases = [(2.3, 8.7), (5.0, 10.0), (0.0, originalDuration)]
        for (start, end) in cases {
            let destination = try await ClipTrimExporter.export(
                source: source, start: start, end: end,
                outputDirectory: outputDirectory)
            let exported = AVURLAsset(url: destination)
            let duration = CMTimeGetSeconds(try await exported.load(.duration))
            let video = try await exported.loadTracks(withMediaType: .video)
            let audio = try await exported.loadTracks(withMediaType: .audio)
            guard abs(duration - (end-start)) < 0.55, !video.isEmpty, !audio.isEmpty else {
                fatalError("Bad trim \(start)-\(end) actual \(duration): video \(video.count), audio \(audio.count)")
            }
            print("PASS \(start)-\(end): \(duration)s, audio \(audio.count) video \(video.count), \(destination.lastPathComponent)")
        }
        do {
            _ = try await ClipTrimExporter.export(source: source,
                                                  start: 10, end: 2,
                                                  outputDirectory: outputDirectory)
            fatalError("Invalid reversed range incorrectly exported!")
        } catch ClipTrimError.invalidRange {
            print("PASS reversed handle interval rejected")
        }
        let afterSize = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as! NSNumber
        guard originalSize == afterSize else { fatalError("Original recording changed!") }
        print("PASS original recording unchanged")
    }
}
