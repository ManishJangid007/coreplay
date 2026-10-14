import Foundation

/// A smart playlist's rules, matched against songs: "Genre is Jazz and
/// Last Played not in the last 30 days, 25 songs, most played first".
/// Plain values (kept as JSON on the playlist), so they're tested anywhere.
public struct SmartPlaylistRules: Codable, Hashable, Sendable {
    public enum Field: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
        case title, artist, album, genre, year, dateAdded, lastPlayed, playCount, duration

        public enum Kind: Sendable { case text, number, date }

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .genre: "Genre"
            case .year: "Year"
            case .dateAdded: "Date Added"
            case .lastPlayed: "Last Played"
            case .playCount: "Plays"
            case .duration: "Length (minutes)"
            }
        }

        public var kind: Kind {
            switch self {
            case .title, .artist, .album, .genre: .text
            case .year, .playCount, .duration: .number
            case .dateAdded, .lastPlayed: .date
            }
        }
    }

    public enum Comparison: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
        case contains, equals, notEquals, beginsWith
        case greaterThan, lessThan
        case inTheLast, notInTheLast

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .contains: "contains"
            case .equals: "is"
            case .notEquals: "is not"
            case .beginsWith: "begins with"
            case .greaterThan: "is more than"
            case .lessThan: "is less than"
            case .inTheLast: "in the last (days)"
            case .notInTheLast: "not in the last (days)"
            }
        }

        public static func options(for kind: Field.Kind) -> [Comparison] {
            switch kind {
            case .text: [.contains, .equals, .notEquals, .beginsWith]
            case .number: [.equals, .greaterThan, .lessThan]
            case .date: [.inTheLast, .notInTheLast]
            }
        }
    }

    public struct Rule: Codable, Hashable, Sendable, Identifiable {
        public var id = UUID()
        public var field: Field
        public var comparison: Comparison
        /// Text, a number, or a number of days.
        public var value: String

        public init(field: Field, comparison: Comparison, value: String) {
            self.field = field
            self.comparison = comparison
            self.value = value
        }
    }

    public enum Order: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
        case title, artist, mostPlayed, recentlyAdded, recentlyPlayed, random

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .mostPlayed: "Most Played"
            case .recentlyAdded: "Recently Added"
            case .recentlyPlayed: "Recently Played"
            case .random: "Random"
            }
        }
    }

    /// What the rules look at in a song.
    public struct Song: Sendable {
        public var title: String
        public var artist: String
        public var album: String
        public var genre: String
        public var year: Int?
        public var dateAdded: Date
        public var lastPlayed: Date?
        public var playCount: Int
        public var duration: TimeInterval?

        public init(title: String, artist: String, album: String, genre: String, year: Int?, dateAdded: Date, lastPlayed: Date?, playCount: Int, duration: TimeInterval?) {
            self.title = title
            self.artist = artist
            self.album = album
            self.genre = genre
            self.year = year
            self.dateAdded = dateAdded
            self.lastPlayed = lastPlayed
            self.playCount = playCount
            self.duration = duration
        }
    }

    /// `true`: every rule must match; `false`: any one.
    public var matchesAll: Bool
    public var rules: [Rule]
    public var order: Order
    /// The most songs, or `nil` for all of them.
    public var limit: Int?

    public init(matchesAll: Bool = true, rules: [Rule] = [], order: Order = .title, limit: Int? = nil) {
        self.matchesAll = matchesAll
        self.rules = rules
        self.order = order
        self.limit = limit
    }

    public func matches(_ song: Song, now: Date = .now) -> Bool {
        guard !rules.isEmpty else { return true }
        return matchesAll
            ? rules.allSatisfy { Self.rule($0, matches: song, now: now) }
            : rules.contains { Self.rule($0, matches: song, now: now) }
    }

    /// The matching items, in order, up to the limit.
    public func select<Item>(_ items: [Item], now: Date = .now, song: (Item) -> Song) -> [Item] {
        var matching = items.map { ($0, song($0)) }.filter { matches($0.1, now: now) }
        switch order {
        case .title:
            matching.sort { $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending }
        case .artist:
            matching.sort {
                let artist = $0.1.artist.localizedStandardCompare($1.1.artist)
                return artist == .orderedSame ? $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending : artist == .orderedAscending
            }
        case .mostPlayed:
            matching.sort { $0.1.playCount > $1.1.playCount }
        case .recentlyAdded:
            matching.sort { $0.1.dateAdded > $1.1.dateAdded }
        case .recentlyPlayed:
            matching.sort { ($0.1.lastPlayed ?? .distantPast) > ($1.1.lastPlayed ?? .distantPast) }
        case .random:
            matching.shuffle()
        }
        let chosen = matching.map(\.0)
        guard let limit, limit > 0 else { return chosen }
        return Array(chosen.prefix(limit))
    }

    private static func rule(_ rule: Rule, matches song: Song, now: Date) -> Bool {
        let value = rule.value.trimmingCharacters(in: .whitespaces)
        switch rule.field.kind {
        case .text:
            let text: String
            switch rule.field {
            case .title: text = song.title
            case .artist: text = song.artist
            case .album: text = song.album
            default: text = song.genre
            }
            switch rule.comparison {
            case .contains: return value.isEmpty || text.localizedCaseInsensitiveContains(value)
            case .equals: return text.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            case .notEquals: return text.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
            case .beginsWith: return text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
            default: return false
            }
        case .number:
            guard let number = Double(value) else { return false }
            let actual: Double?
            switch rule.field {
            case .year: actual = song.year.map(Double.init)
            case .playCount: actual = Double(song.playCount)
            default: actual = song.duration.map { $0 / 60 }
            }
            guard let actual else { return false }
            switch rule.comparison {
            case .equals: return rule.field == .duration ? abs(actual - number) < 0.5 : actual == number
            case .greaterThan: return actual > number
            case .lessThan: return actual < number
            default: return false
            }
        case .date:
            guard let days = Double(value), days >= 0 else { return false }
            let cutoff = now.addingTimeInterval(-days * 86_400)
            let date = rule.field == .dateAdded ? song.dateAdded : song.lastPlayed
            switch rule.comparison {
            case .inTheLast: return date.map { $0 >= cutoff } ?? false
            case .notInTheLast: return date.map { $0 < cutoff } ?? true
            default: return false
            }
        }
    }

    // MARK: Starting points

    public static let recentlyAdded = SmartPlaylistRules(rules: [Rule(field: .dateAdded, comparison: .inTheLast, value: "30")], order: .recentlyAdded, limit: 100)
    public static let mostPlayed = SmartPlaylistRules(rules: [Rule(field: .playCount, comparison: .greaterThan, value: "0")], order: .mostPlayed, limit: 25)
    public static let neverPlayed = SmartPlaylistRules(rules: [Rule(field: .playCount, comparison: .lessThan, value: "1")], order: .random, limit: 100)
}
