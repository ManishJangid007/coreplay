import Foundation

/// Which frames a video's scrub previews hold, and the order they're made in.
///
/// The video is divided into equal slots; each slot gets one frame, taken
/// from its middle, so a preview is never more than half a slot away from
/// the time under the user's finger. Frames are made coarse to fine (every
/// 16th slot first, then the 8ths between them, and so on), so scrubbing
/// finds a nearby frame within seconds of a video starting, long before the
/// whole strip is done.
public struct ScrubPreviewPlan: Hashable, Sendable, Codable {
    public let duration: TimeInterval
    /// Seconds between frames.
    public let interval: TimeInterval
    public let count: Int

    /// - Parameters:
    ///   - targetCount: Frames wanted for long videos.
    ///   - minimumInterval: Short videos get a frame at most this often.
    public init(duration: TimeInterval, targetCount: Int = 200, minimumInterval: TimeInterval = 2) {
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        self.duration = safeDuration
        guard safeDuration > 0 else {
            interval = minimumInterval
            count = 0
            return
        }
        let spacing = max(minimumInterval, safeDuration / Double(max(targetCount, 1)))
        interval = spacing
        count = max(1, Int((safeDuration / spacing).rounded(.up)))
    }

    /// The moment frame `index` shows: the middle of its slot.
    public func time(of index: Int) -> TimeInterval {
        let middle = (Double(index) + 0.5) * interval
        return min(max(middle, 0), max(duration - 0.5, 0))
    }

    /// The frame for `time`.
    public func index(for time: TimeInterval) -> Int {
        guard count > 0, interval > 0, time.isFinite else { return 0 }
        return min(max(Int(time / interval), 0), count - 1)
    }

    /// Every index exactly once, coarse to fine.
    public var generationOrder: [Int] {
        guard count > 0 else { return [] }
        var order: [Int] = []
        order.reserveCapacity(count)
        var seen = Set<Int>()
        var stride = 16
        while stride >= 1 {
            var index = 0
            while index < count {
                if seen.insert(index).inserted {
                    order.append(index)
                }
                index += stride
            }
            stride /= 2
        }
        return order
    }

    /// The closest index to `target` for which `isAvailable` is true,
    /// searching outwards (earlier frames win ties).
    public func nearest(to target: Int, where isAvailable: (Int) -> Bool) -> Int? {
        guard count > 0 else { return nil }
        let start = min(max(target, 0), count - 1)
        if isAvailable(start) { return start }
        var distance = 1
        while start - distance >= 0 || start + distance < count {
            if start - distance >= 0, isAvailable(start - distance) { return start - distance }
            if start + distance < count, isAvailable(start + distance) { return start + distance }
            distance += 1
        }
        return nil
    }
}
