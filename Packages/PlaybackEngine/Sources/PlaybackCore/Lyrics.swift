import Foundation

/// A song's words: timed lines from an LRC file (synced, shown as the song
/// plays) or plain text.
public struct Lyrics: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        /// When the line starts; `nil` in plain lyrics.
        public var time: TimeInterval?
        /// Empty for an instrumental gap.
        public var text: String

        public init(time: TimeInterval?, text: String) {
            self.time = time
            self.text = text
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public var isSynced: Bool {
        lines.contains { $0.time != nil }
    }

    /// Reads LRC (`[01:23.45]words`, several stamps on one line, an
    /// `[offset:+250]` tag, other tags dropped) or plain text. `nil` when
    /// there are no words at all.
    public init?(text: String) {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var offset: TimeInterval = 0
        var timed: [Line] = []
        var plain: [Line] = []
        for raw in rawLines {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var stamps: [TimeInterval] = []
            var isTag = false
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let inside = rest[rest.index(after: rest.startIndex)..<close]
                if let time = Self.time(from: inside) {
                    stamps.append(time)
                } else if let colon = inside.firstIndex(of: ":") {
                    // A tag such as [ar:Artist] or [offset:+250].
                    isTag = true
                    if inside[..<colon].lowercased() == "offset",
                       let milliseconds = Double(inside[inside.index(after: colon)...].trimmingCharacters(in: .whitespaces)) {
                        offset = milliseconds / 1_000
                    }
                } else {
                    break
                }
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            if !stamps.isEmpty {
                timed += stamps.map { Line(time: $0, text: words) }
            } else if !isTag {
                plain.append(Line(time: nil, text: words))
            }
        }
        if !timed.isEmpty {
            // LRC offsets move the words earlier when positive.
            lines = timed
                .map { Line(time: max(0, ($0.time ?? 0) - offset), text: $0.text) }
                .sorted { ($0.time ?? 0) < ($1.time ?? 0) }
        } else {
            // Plain text: trim blank lines at either end.
            while plain.first?.text.isEmpty == true { plain.removeFirst() }
            while plain.last?.text.isEmpty == true { plain.removeLast() }
            lines = plain
        }
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }
    }

    /// The line being sung at `time` (synced lyrics), or `nil` before the first.
    public func lineIndex(at time: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if (lines[middle].time ?? 0) <= time {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    /// "mm:ss.xx", "mm:ss:xx" or "mm:ss".
    private static func time(from stamp: Substring) -> TimeInterval? {
        let parts = stamp.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Double(parts[0]), minutes >= 0, parts[0].allSatisfy(\.isNumber) else { return nil }
        let seconds: Double
        if parts.count == 3 {
            guard let whole = Double(parts[1]), let fraction = Double("0." + parts[2]) else { return nil }
            seconds = whole + fraction
        } else {
            guard let value = Double(parts[1]) else { return nil }
            seconds = value
        }
        guard seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }
}
