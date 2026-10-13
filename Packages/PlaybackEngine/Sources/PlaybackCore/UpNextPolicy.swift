import Foundation

/// When the player offers the next episode, as the TV app does once the end
/// credits roll.
///
/// With a chapter marking the credits, the card appears there and the next
/// episode starts after a short countdown. Without one, the card appears in
/// the last seconds and the next episode starts when this one ends, so no
/// part of the story is ever cut off. Pure value logic, tested on its own.
public enum UpNextPolicy {
    /// Without a credits chapter, the card appears this long before the end.
    public static let leadTime: TimeInterval = 20
    /// From a credits chapter, the next episode starts after this long.
    public static let countdown: TimeInterval = 10
    /// Trailers and clips never offer the next item early.
    public static let minimumDuration: TimeInterval = 240

    public enum Phase: Equatable, Sendable {
        /// Nothing to show.
        case hidden
        /// Show the card. `countdown` is `nil` when the next item waits for
        /// the viewer (autoplay is off).
        case offering(countdown: Countdown?)
        /// The countdown has run out at the credits: start the next item now.
        case startNext
    }

    public struct Countdown: Equatable, Sendable {
        /// Seconds until the next item starts.
        public var remaining: TimeInterval
        /// The countdown's full length, for a progress ring.
        public var total: TimeInterval

        public init(remaining: TimeInterval, total: TimeInterval) {
            self.remaining = remaining
            self.total = total
        }

        /// 0 when the countdown starts, 1 when it runs out.
        public var fraction: Double {
            guard total > 0 else { return 1 }
            return min(max(1 - remaining / total, 0), 1)
        }
    }

    /// The start of the end credits: a chapter named like "End Credits" or
    /// "Outro" that starts in the last third and isn't the very end.
    public static func creditsStart(chapters: [Chapter], duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration >= minimumDuration else { return nil }
        let candidates = chapters.filter { chapter in
            guard let title = chapter.title, isCreditsTitle(title) else { return false }
            return chapter.start >= duration * 0.67 && chapter.start < duration - 5
        }
        return candidates.map(\.start).min()
    }

    static func isCreditsTitle(_ title: String) -> Bool {
        let lowered = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = ["credit", "outro", "end title", "closing title", "abspann", "générique", "generique"]
        if words.contains(where: lowered.contains) {
            return true
        }
        return lowered == "end" || lowered == "ending"
    }

    /// Where the card appears, or `nil` when this item never offers the next one early.
    public static func offerTime(duration: TimeInterval?, creditsStart: TimeInterval?) -> TimeInterval? {
        guard let duration, duration >= minimumDuration else { return nil }
        return creditsStart ?? duration - leadTime
    }

    /// What the player shows at `currentTime`.
    /// - Parameter autoplays: Whether the next item starts by itself.
    public static func phase(
        currentTime: TimeInterval,
        duration: TimeInterval?,
        creditsStart: TimeInterval?,
        autoplays: Bool
    ) -> Phase {
        guard let duration, let offer = offerTime(duration: duration, creditsStart: creditsStart),
              currentTime >= offer, currentTime < duration + 1 else { return .hidden }
        guard autoplays else { return .offering(countdown: nil) }
        if let creditsStart {
            let deadline = min(creditsStart + countdown, duration)
            if deadline < duration, currentTime >= deadline {
                return .startNext
            }
            return .offering(countdown: Countdown(remaining: max(deadline - currentTime, 0), total: deadline - creditsStart))
        }
        // No credits marker: count down to the natural end.
        return .offering(countdown: Countdown(remaining: max(duration - currentTime, 0), total: duration - offer))
    }
}
