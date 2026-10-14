import Foundation
import Testing
@testable import PlaybackCore

@Suite("Lyrics")
struct LyricsTests {
    @Test func readsSyncedLyrics() throws {
        let lrc = """
        [ti:Song 1]
        [ar:The Harbour Lights]
        [offset:+500]
        [00:12.50]First line
        [00:20.00][01:05.25]Chorus
        [00:15.00]
        [00:17:30]Second line
        """
        let lyrics = try #require(Lyrics(text: lrc))
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["First line", "", "Second line", "Chorus", "Chorus"])
        #expect(lyrics.lines.map { $0.time ?? -1 } == [12.0, 14.5, 16.8, 19.5, 64.75])
        #expect(lyrics.lineIndex(at: 5) == nil)
        #expect(lyrics.lineIndex(at: 12) == 0)
        #expect(lyrics.lineIndex(at: 18) == 2)
        #expect(lyrics.lineIndex(at: 500) == 4)
    }

    @Test func readsPlainLyrics() throws {
        let lyrics = try #require(Lyrics(text: "\n\nOne\r\nTwo\n\nThree\n\n"))
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["One", "Two", "", "Three"])
        #expect(lyrics.lineIndex(at: 10) == nil)
        #expect(Lyrics(text: "  \n[ar:Someone]\n") == nil)
    }
}

@Suite("Smart playlists")
struct SmartPlaylistTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func song(_ title: String, artist: String = "A", genre: String = "Jazz", year: Int? = 1999, addedDaysAgo: Double = 1, playedDaysAgo: Double? = nil, plays: Int = 0, minutes: Double = 3) -> SmartPlaylistRules.Song {
        .init(title: title, artist: artist, album: "Album", genre: genre, year: year,
              dateAdded: now.addingTimeInterval(-addedDaysAgo * 86_400),
              lastPlayed: playedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
              playCount: plays, duration: minutes * 60)
    }

    @Test func rulesMatchAllOrAny() {
        let jazz = song("Blue", genre: "jazz", plays: 5, minutes: 7)
        let rock = song("Loud", artist: "Band", genre: "Rock", year: 2020, addedDaysAgo: 100, playedDaysAgo: 2, plays: 1)
        var rules = SmartPlaylistRules(rules: [
            .init(field: .genre, comparison: .equals, value: "Jazz"),
            .init(field: .duration, comparison: .greaterThan, value: "5"),
        ])
        #expect(rules.matches(jazz, now: now))
        #expect(!rules.matches(rock, now: now))
        rules.matchesAll = false
        rules.rules.append(.init(field: .year, comparison: .equals, value: "2020"))
        #expect(rules.matches(rock, now: now))
        #expect(SmartPlaylistRules(rules: [.init(field: .title, comparison: .beginsWith, value: "lo")]).matches(rock, now: now))
        #expect(SmartPlaylistRules(rules: [.init(field: .artist, comparison: .notEquals, value: "band")]).matches(jazz, now: now))
        #expect(SmartPlaylistRules(rules: [.init(field: .lastPlayed, comparison: .notInTheLast, value: "30")]).matches(jazz, now: now), "never played counts as not recently")
        #expect(!SmartPlaylistRules(rules: [.init(field: .lastPlayed, comparison: .notInTheLast, value: "30")]).matches(rock, now: now))
        #expect(!SmartPlaylistRules(rules: [.init(field: .dateAdded, comparison: .inTheLast, value: "30")]).matches(rock, now: now))
        #expect(!SmartPlaylistRules(rules: [.init(field: .year, comparison: .greaterThan, value: "x")]).matches(rock, now: now))
    }

    @Test func selectionIsOrderedAndLimited() {
        let songs = [song("C", plays: 1), song("A", plays: 9), song("B", plays: 4), song("D", plays: 0)]
        let top = SmartPlaylistRules.mostPlayed.select(songs, now: now) { $0 }
        #expect(top.map(\.title) == ["A", "B", "C"])
        var byTitle = SmartPlaylistRules(order: .title, limit: 2)
        #expect(byTitle.select(songs, now: now) { $0 }.map(\.title) == ["A", "B"])
        byTitle.limit = nil
        #expect(byTitle.select(songs, now: now) { $0 }.count == 4)
        #expect(SmartPlaylistRules.neverPlayed.select(songs, now: now) { $0 }.map(\.title) == ["D"])
        let data = try! JSONEncoder().encode(SmartPlaylistRules.recentlyAdded)
        #expect(try! JSONDecoder().decode(SmartPlaylistRules.self, from: data) == .recentlyAdded)
    }
}
