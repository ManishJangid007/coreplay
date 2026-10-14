import Foundation
import PlaybackCore
import SwiftData
import Testing
@testable import MediaLibrary

/// A large library stays quick: the lists and playlists people open most
/// are timed with ten thousand songs.
@MainActor
@Suite("A large library")
struct LibraryScaleTests {
    @Test func tenThousandSongsStayQuick() throws {
        let library = LibraryManager(inMemory: true)
        let context = library.context
        let count = 10_000
        let genres = ["Jazz", "Rock", "Pop", "Classical"]
        var started = Date()
        for index in 0..<count {
            let file = MediaFile()
            file.fileName = "song-\(index).flac"
            file.contentKey = "key-\(index)"
            context.insert(file)
            let track = Track()
            track.title = "Song \(index)"
            track.sortTitle = "song \(index)"
            track.artistName = "Artist \(index % 400)"
            track.albumTitle = "Album \(index % 900)"
            track.genreName = genres[index % genres.count]
            track.duration = 180 + Double(index % 120)
            track.file = file
            context.insert(track)
            if index.isMultiple(of: 3) {
                let record = PlaybackRecord(contentKey: file.contentKey)
                record.playCount = index % 37
                record.lastPlayedDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
                context.insert(record)
            }
        }
        try context.save()
        let built = Date().timeIntervalSince(started)

        started = Date()
        let all = library.allAvailableTracks()
        let listing = Date().timeIntervalSince(started)
        #expect(all.count == count)

        started = Date()
        let jazz = library.makePlaylist(named: "Jazz Favourites", rules: SmartPlaylistRules(
            rules: [.init(field: .genre, comparison: .equals, value: "jazz"), .init(field: .playCount, comparison: .greaterThan, value: "5")],
            order: .mostPlayed,
            limit: 100
        ))
        let smart = library.tracks(in: jazz)
        let smartTime = Date().timeIntervalSince(started)
        #expect(smart.count == 100)

        started = Date()
        let big = library.makePlaylist(named: "Everything", tracks: Array(all.prefix(5_000)))
        let resolved = library.tracks(in: big)
        let playlistTime = Date().timeIntervalSince(started)
        #expect(resolved.count == 5_000)

        started = Date()
        let top = library.mostPlayedTracks(limit: 10)
        let topTime = Date().timeIntervalSince(started)
        #expect(top.count == 10)

        print("Library scale: built \(count) songs in \(String(format: "%.2f", built)) s; all songs \(String(format: "%.3f", listing)) s; smart playlist \(String(format: "%.3f", smartTime)) s; 5,000-song playlist \(String(format: "%.3f", playlistTime)) s; Top Songs \(String(format: "%.3f", topTime)) s")
        #expect(listing < 3)
        #expect(smartTime < 3)
        #expect(playlistTime < 3)
        #expect(topTime < 1)
    }
}
