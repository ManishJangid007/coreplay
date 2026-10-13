import Foundation

/// Formats playback positions the way Apple's players do: `0:07`, `12:34`,
/// `1:02:03`, and `-4:56` for remaining time.
public enum PlaybackTimeFormatter {
    /// Formats `seconds`. Pass `referenceDuration` so a 1-hour movie shows
    /// `0:00:07` rather than `0:07`, keeping both labels the same width.
    public static func string(from seconds: TimeInterval, referenceDuration: TimeInterval? = nil) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        let showHours = hours > 0 || (referenceDuration ?? 0) >= 3_600
        if showHours {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
        }
        return "\(minutes):\(twoDigits(secs))"
    }

    /// Remaining time, e.g. `-4:56`.
    public static func remainingString(currentTime: TimeInterval, duration: TimeInterval) -> String {
        let remaining = max(0, duration - currentTime)
        return "-" + string(from: remaining.rounded(.up), referenceDuration: duration)
    }

    /// Spoken form for VoiceOver, e.g. "1 hour, 2 minutes, 3 seconds".
    public static func accessibilityString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "Unknown" }
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs) \(secs == 1 ? "second" : "seconds")") }
        return parts.joined(separator: ", ")
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
