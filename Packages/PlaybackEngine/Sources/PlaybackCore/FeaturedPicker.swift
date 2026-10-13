import Foundation

/// Chooses what the hero carousel at the top of Home, Movies and TV Shows
/// features: what was just added, what you're in the middle of, then a pick
/// of what you haven't watched that changes once a day.
///
/// Works on plain values so the rules can be tested without a library.
public enum FeaturedPicker {
    public struct Candidate: Hashable, Sendable {
        public var id: String
        public var dateAdded: Date
        public var lastPlayed: Date?
        /// Started and not finished (a movie, or a show's latest episode).
        public var isInProgress: Bool
        /// Watched to the end (a movie), or every episode watched (a show).
        public var isFinished: Bool
        /// A real backdrop (not a frame from the file), which makes the best hero.
        public var hasBackdrop: Bool
        /// Any picture at all: backdrop, frame or poster.
        public var hasArtwork: Bool

        public init(
            id: String,
            dateAdded: Date,
            lastPlayed: Date? = nil,
            isInProgress: Bool = false,
            isFinished: Bool = false,
            hasBackdrop: Bool = false,
            hasArtwork: Bool = true
        ) {
            self.id = id
            self.dateAdded = dateAdded
            self.lastPlayed = lastPlayed
            self.isInProgress = isInProgress
            self.isFinished = isFinished
            self.hasBackdrop = hasBackdrop
            self.hasArtwork = hasArtwork
        }
    }

    /// Items added this recently are "New".
    public static let newWindow: TimeInterval = 14 * 24 * 60 * 60
    static let maximumNew = 3
    static let maximumInProgress = 2

    public static func isNew(_ dateAdded: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(dateAdded) < newWindow
    }

    /// Identifiers of up to `limit` candidates, in the order to show them.
    public static func pick(_ candidates: [Candidate], limit: Int = 8, now: Date = .now) -> [String] {
        guard limit > 0 else { return [] }
        // Without a picture, a hero is just a title on grey; use those only
        // when there's nothing better.
        let pictured = candidates.filter(\.hasArtwork)
        let pool = pictured.count >= min(3, candidates.count) ? pictured : candidates

        var chosen: [String] = []
        var seen = Set<String>()

        let new = pool
            .filter { isNew($0.dateAdded, now: now) && !$0.isFinished && !$0.isInProgress }
            .sorted { $0.dateAdded > $1.dateAdded }
        appendUnique(new.prefix(maximumNew), to: &chosen, seen: &seen, limit: limit)

        let inProgress = pool
            .filter(\.isInProgress)
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        appendUnique(inProgress.prefix(maximumInProgress), to: &chosen, seen: &seen, limit: limit)

        // The day's picks: unwatched first, real backdrops before frames,
        // in an order that's stable for the day and changes the next.
        let day = Int(now.timeIntervalSince1970 / 86_400)
        let rest = pool
            .filter { !seen.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.isFinished != rhs.isFinished { return !lhs.isFinished }
                if lhs.hasBackdrop != rhs.hasBackdrop { return lhs.hasBackdrop }
                if lhs.hasArtwork != rhs.hasArtwork { return lhs.hasArtwork }
                return shuffleKey(lhs.id, day: day) < shuffleKey(rhs.id, day: day)
            }
        appendUnique(rest[...], to: &chosen, seen: &seen, limit: limit)
        return chosen
    }

    private static func appendUnique(_ items: ArraySlice<Candidate>, to chosen: inout [String], seen: inout Set<String>, limit: Int) {
        for item in items {
            guard chosen.count < limit else { return }
            if seen.insert(item.id).inserted {
                chosen.append(item.id)
            }
        }
    }

    /// FNV-1a over the day and the identifier, then MurmurHash3's finaliser
    /// so a new day reshuffles everything: a fixed order for the day (Swift's
    /// `Hasher` is seeded differently on every launch).
    static func shuffleKey(_ id: String, day: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(day)#\(id)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        hash = hash &* 0xc4ce_b9fe_1a85_ec53
        hash ^= hash >> 33
        return hash
    }
}
