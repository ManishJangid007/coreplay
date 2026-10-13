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

    /// Reads a typed time: "1:02:03", "62:03", "45", or "1h 2m 3s".
    /// Returns `nil` for anything else.
    public static func seconds(from text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(where: { "hms".contains($0) }) {
            var total: TimeInterval = 0
            var number = ""
            var sawUnit = false
            for character in trimmed where !character.isWhitespace {
                if character.isNumber || character == "." {
                    number.append(character)
                    continue
                }
                guard let value = Double(number) else { return nil }
                switch character {
                case "h": total += value * 3_600
                case "m": total += value * 60
                case "s": total += value
                default: return nil
                }
                number = ""
                sawUnit = true
            }
            guard number.isEmpty, sawUnit else { return nil }
            return total
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value >= 0 else { return nil }
            // Minutes and seconds after the first field must be under 60.
            if index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
