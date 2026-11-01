import Foundation
import CoreMedia
import CoreVideo

enum CLIPFrameRetiming {
    /// Keeps a static captured image visible for the full replay period.
    /// Each copy receives a strictly increasing presentation timestamp.
    static func copy(_ source: CMSampleBuffer, at pts: CMTime) -> CMSampleBuffer? {
        guard source.isValid, pts.isValid,
              CMSampleBufferGetImageBuffer(source) != nil else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: source,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &result)
        guard status == noErr else { return nil }
        return result
    }
}
