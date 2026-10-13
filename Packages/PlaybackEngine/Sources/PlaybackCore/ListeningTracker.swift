import Foundation

/// Decides when a song counts as played: after it has actually played for
/// half its length or four minutes, whichever comes first (the build
/// prompt's rule, which is also Last.fm's). Seeking doesn't count as listening.
///
/// Feed it a sample every second or two; `update` returns `true` exactly once
/// per play of an item.
public struct ListeningTracker: Sendable {
    public var minimumFraction: Double = 0.5
    public var maximumRequired: TimeInterval = 240
    /// Songs shorter than this never count (jingles, intros, silence).
    public var minimumDuration: TimeInterval = 30
    /// Position jumps bigger than this between samples are seeks, not listening.
    public var largestPlayedStep: TimeInterval = 10

    public private(set) var itemID: UUID?
    public private(set) var listenedTime: TimeInterval = 0
    public private(set) var hasCounted = false
    private var lastPosition: TimeInterval?

    public init() {}

    /// - Returns: `true` when this sample completes a play.
    public mutating func update(itemID: UUID?, position: TimeInterval, duration: TimeInterval?, isPlaying: Bool) -> Bool {
        if itemID != self.itemID {
            self.itemID = itemID
            listenedTime = 0
            hasCounted = false
            lastPosition = position
            return false
        }
        guard itemID != nil else { return false }
        defer { lastPosition = position }

        // Back at the start after reaching the end: a replay (Repeat One).
        if hasCounted, let lastPosition, let duration, position < 5, lastPosition > duration - 10 {
            listenedTime = 0
            hasCounted = false
        }

        guard isPlaying, let lastPosition else { return false }
        let step = position - lastPosition
        if step > 0, step <= largestPlayedStep {
            listenedTime += step
        }
        guard !hasCounted else { return false }
        if let duration, duration < minimumDuration {
            return false
        }
        let required = duration.map { min($0 * minimumFraction, maximumRequired) } ?? maximumRequired
        if listenedTime >= required {
            hasCounted = true
            return true
        }
        return false
    }
}
