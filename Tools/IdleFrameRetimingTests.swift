import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

@main
struct IdleFrameRetimingTests {
    static func main() async throws {
        let output = URL(fileURLWithPath: "/tmp/clip-idle-frame-test.mov")
        try? FileManager.default.removeItem(at: output)
        var raw: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 256, 144,
                                  kCVPixelFormatType_32BGRA, nil, &raw) == kCVReturnSuccess,
              let image = raw else { fatalError("Pixel buffer") }
        CVPixelBufferLockBaseAddress(image, [])
        memset(CVPixelBufferGetBaseAddress(image), 87, CVPixelBufferGetDataSize(image))
        CVPixelBufferUnlockBaseAddress(image, [])
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: image,
            formatDescriptionOut: &description) == noErr,
              let format = description else { fatalError("Format description") }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var original: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: image,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &original) == noErr,
              let original else { fatalError("Original sample") }

        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 256, AVVideoHeightKey: 144
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain:"CLIPTest",code:1) }
        writer.startSession(atSourceTime: .zero)
        guard input.append(original) else { throw writer.error ?? NSError(domain:"CLIPTest",code:2) }
        var last = CMTime.zero
        for index in 1...120 {
            let pts = CMTime(seconds: Double(index) / 4,
                             preferredTimescale: 60000)
            guard let copy = CLIPFrameRetiming.copy(original, at: pts) else {
                fatalError("Unable to retime static frame index \(index)")
            }
            guard CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(copy), last) > 0 else {
                fatalError("Timestamp did not advance")
            }
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard input.append(copy) else {
                throw writer.error ?? NSError(domain:"CLIPTest",code:3)
            }
            last = pts
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain:"CLIPTest",code:4)
        }
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds >= 29.75 && seconds <= 30.5 else {
            fatalError("Expected 30 seconds of static footage; got \(seconds)")
        }
        print("PASS: 120 unchanged-screen frames generated with increasing timestamps")
        print("PASS: 30-second encoded H.264 video created from a single unchanged frame")
        print("TEST MOV: \(output.path)")
    }
}
