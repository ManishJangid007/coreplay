import Foundation
import PlaybackCore
import SwiftData
import Testing
@testable import MediaLibrary

@MainActor
@Suite("Playlists and iCloud sync")
struct PlaylistAndSyncTests {
    final class MemoryStore: CloudValueStore {
        var values: [String: Data] = [:]
        func data(forKey key: String) -> Data? { values[key] }
        func setData(_ data: Data?, forKey key: String) { values[key] = data }
        func synchronize() -> Bool { true }
    }

    /// Three songs on an album, with files, in an in-memory library.
    private func library(withSongs count: Int = 3) throws -> (LibraryManager, [Track]) {
        let library = LibraryManager(inMemory: true)
        var tracks: [Track] = []
        for number in 1...count {
            let file = MediaFile()
            file.fileName = "song-\(number).flac"
            file.contentKey = "key-\(number)"
            library.context.insert(file)
            let track = Track()
            track.title = "Song \(number)"
            track.sortTitle = track.title.lowercased()
            track.artistName = number == 3 ? "Other" : "Band"
            track.genreName = "Jazz"
            track.duration = 200
            track.file = file
            library.context.insert(track)
            tracks.append(track)
        }
        try library.context.save()
        return (library, tracks)
    }

    @Test func playlistsKeepOrderAndSkipMissingSongs() throws {
        let (library, tracks) = try library()
        let playlist = library.makePlaylist(named: "  Road Trip ", tracks: [tracks[2], tracks[0]])
        #expect(playlist.name == "Road Trip")
        library.add([tracks[1]], to: playlist)
        #expect(library.tracks(in: playlist).map(\.title) == ["Song 3", "Song 1", "Song 2"])
        library.moveItems(in: playlist, from: [2], to: 0)
        #expect(library.tracks(in: playlist).map(\.title) == ["Song 2", "Song 3", "Song 1"])
        // A song from another device: listed, not shown, counted as missing.
        playlist.itemKeys.insert("elsewhere", at: 1)
        #expect(library.items(in: playlist).map(\.position) == [0, 2, 3])
        #expect(library.missingCount(in: playlist) == 1)
        library.removeItems(at: [2], from: playlist)
        #expect(library.tracks(in: playlist).map(\.title) == ["Song 2", "Song 1"])
        #expect(library.makePlaylist(named: "   ").name == "Untitled Playlist")
    }

    @Test func smartPlaylistsFollowTheirRules() throws {
        let (library, _) = try library()
        let record = PlaybackRecord(contentKey: "key-2")
        record.playCount = 7
        library.context.insert(record)
        try library.context.save()
        let band = library.makePlaylist(named: "Band", rules: SmartPlaylistRules(rules: [.init(field: .artist, comparison: .equals, value: "band")]))
        #expect(band.isSmart)
        #expect(library.tracks(in: band).map(\.title) == ["Song 1", "Song 2"])
        let top = library.makePlaylist(named: "Top", rules: .mostPlayed)
        #expect(library.tracks(in: top).map(\.title) == ["Song 2"])
        library.add([], to: band)
        #expect(band.itemKeys.isEmpty)
    }

    @Test func playStateAndPlaylistsTravelThroughICloud() throws {
        let store = MemoryStore()
        let (mac, macTracks) = try library()
        let (phone, _) = try library()
        let played = PlaybackRecord(contentKey: "key-1")
        played.playCount = 3
        played.lastPlayedDate = Date(timeIntervalSince1970: 1_000)
        mac.context.insert(played)
        let film = PlaybackRecord(contentKey: "film-1")
        film.position = 1_200
        film.duration = 6_000
        film.lastPlayedDate = Date(timeIntervalSince1970: 2_000)
        mac.context.insert(film)
        mac.makePlaylist(named: "Road Trip", tracks: [macTracks[1]])
        try mac.context.save()
        LibraryCloudSync(library: mac, store: store).pushNow()

        let phoneSync = LibraryCloudSync(library: phone, store: store)
        phoneSync.pull()
        func record(_ key: String, in library: LibraryManager) -> PlaybackRecord? {
            try? library.context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.contentKey == key })).first
        }
        #expect(record("key-1", in: phone)?.playCount == 3)
        #expect(record("film-1", in: phone)?.position == 1_200)
        let synced = try #require(phone.playlists().first)
        #expect(synced.name == "Road Trip")
        #expect(phone.tracks(in: synced).map(\.title) == ["Song 2"])

        // The phone plays it again and deletes the playlist; the Mac follows.
        let phoneRecord = try #require(record("key-1", in: phone))
        phoneRecord.playCount = 4
        phoneRecord.lastPlayedDate = Date(timeIntervalSince1970: 3_000)
        phone.delete(synced)
        phoneSync.pushNow()
        LibraryCloudSync(library: mac, store: store).pull()
        #expect(record("key-1", in: mac)?.playCount == 4)
        #expect(mac.playlists().isEmpty)
    }
}
