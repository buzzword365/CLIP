import Foundation

struct ReplaySegmentInfo {
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let mediaDuration: TimeInterval
}

enum ReplayWindowStatus {
    case ready([Int])
    case warmingUp(available: Int, required: Int)
    case stalled(age: Int)
}

enum ReplayWindowPolicy {
    // A replay must end close to the shortcut event, and cannot cross a capture
    // interruption. Near-total media coverage avoids presenting partial clips as 30s.
    static func evaluate(_ items: [ReplaySegmentInfo],
                         seconds: Int,
                         requestedAt: TimeInterval) -> ReplayWindowStatus {
        guard seconds > 0, requestedAt.isFinite, let last = items.last,
              last.endedAt.isFinite else {
            return .warmingUp(available: 0, required: max(seconds, 1))
        }
        let age = requestedAt - last.endedAt
        if age > 4 { return .stalled(age: Int(age.rounded(.up))) }
        if age < -2 { return .warmingUp(available: 0, required: seconds) }

        var selected: [Int] = []
        var totalMedia = 0.0
        var nextStart: TimeInterval?
        for index in items.indices.reversed() {
            let item = items[index]
            guard item.startedAt.isFinite, item.endedAt.isFinite,
                  item.mediaDuration.isFinite, item.mediaDuration > 0,
                  item.endedAt >= item.startedAt else { break }
            if let nextStart {
                let gap = nextStart - item.endedAt
                // Small encoder/queue jitter is normal; a genuine interruption
                // must not be silently bridged with old video.
                guard gap >= -0.9 && gap <= 2.0 else { break }
            }
            selected.insert(index, at: 0)
            totalMedia += item.mediaDuration
            nextStart = item.startedAt
            if totalMedia >= Double(seconds) - 1.25 { break }
        }
        guard let first = selected.first else {
            return .warmingUp(available: 0, required: seconds)
        }
        let wallCoverage = last.endedAt - items[first].startedAt
        if totalMedia >= Double(seconds) - 1.25 &&
           wallCoverage >= Double(seconds) - 1.5 {
            return .ready(selected)
        }
        return .warmingUp(available: min(seconds, max(0, Int(totalMedia.rounded(.down)))),
                          required: seconds)
    }

    /// Returns only recent, contiguous recording. If the app has been running
    /// for less than the chosen replay duration, Cmd+Shift+S can still save
    /// whatever footage exists rather than rejecting the shortcut.
    static func availableNow(_ items: [ReplaySegmentInfo],
                             seconds: Int,
                             requestedAt: TimeInterval) -> [Int]? {
        guard seconds > 0, requestedAt.isFinite, let last = items.last,
              last.endedAt.isFinite,
              requestedAt - last.endedAt <= 4,
              requestedAt - last.endedAt >= -2 else { return nil }
        var selected: [Int] = []
        var mediaSeconds = 0.0
        var nextStart: TimeInterval?
        for index in items.indices.reversed() {
            let item = items[index]
            guard item.startedAt.isFinite, item.endedAt.isFinite,
                  item.mediaDuration.isFinite, item.mediaDuration > 0,
                  item.endedAt >= item.startedAt else { break }
            if let nextStart {
                let gap = nextStart - item.endedAt
                guard gap >= -0.9 && gap <= 2.0 else { break }
            }
            selected.insert(index, at: 0)
            nextStart = item.startedAt
            mediaSeconds += item.mediaDuration
            if mediaSeconds >= Double(seconds) - 1.25 { break }
        }
        guard mediaSeconds >= 0.5 else { return nil }
        return selected
    }

    static func choose(_ items: [ReplaySegmentInfo],
                       seconds: Int,
                       requestedAt: TimeInterval) -> [Int]? {
        if case .ready(let indices) = evaluate(items, seconds: seconds,
                                              requestedAt: requestedAt) { return indices }
        return nil
    }
}
