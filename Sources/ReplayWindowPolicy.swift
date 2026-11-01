import Foundation

// Pure selection policy used by the live engine and regression tests.
// Media duration alone is insufficient: a paused ScreenCaptureKit stream
// can leave valid-looking segments from minutes ago in memory.
struct ReplaySegmentInfo {
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let mediaDuration: TimeInterval
}

enum ReplayWindowPolicy {
    static func choose(_ items: [ReplaySegmentInfo],
                       seconds: Int,
                       requestedAt: TimeInterval) -> [Int]? {
        guard seconds >= 1, !items.isEmpty, requestedAt.isFinite else { return nil }
        guard let last = items.last,
              last.endedAt.isFinite,
              last.endedAt >= requestedAt - 3.0,
              last.endedAt <= requestedAt + 1.0 else { return nil }
        var selected: [Int] = []
        var totalMedia: TimeInterval = 0
        var newestStart: TimeInterval?
        for index in items.indices.reversed() {
            let item = items[index]
            guard item.startedAt.isFinite, item.endedAt.isFinite,
                  item.mediaDuration.isFinite, item.mediaDuration > 0,
                  item.endedAt >= item.startedAt else { return nil }
            if let nextStart = newestStart {
                // The previous segment must join the next one without long gaps.
                let gap = nextStart - item.endedAt
                guard gap >= -0.75 && gap <= 1.5 else { break }
            }
            selected.insert(index, at: 0)
            totalMedia += item.mediaDuration
            newestStart = item.startedAt
            if totalMedia >= Double(seconds) - 1.25 { break }
        }
        guard let firstIndex = selected.first,
              totalMedia >= Double(seconds) - 1.25,
              last.endedAt - items[firstIndex].startedAt >= Double(seconds) - 1.25
        else { return nil }
        return selected
    }
}
