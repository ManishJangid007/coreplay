import Foundation
import PlaybackCore
import SwiftData

/// A playlist: songs you put in order, or a smart playlist's rules. Songs
/// are kept by content key, so they survive rescans and match the same
/// file in the library on another device.
@Model
public final class Playlist {
    #Index<Playlist>([\.id], [\.dateModified])

    public var id: UUID = UUID()
    public var name: String = ""
    public var dateCreated: Date = Date.now
    public var dateModified: Date = Date.now
    /// The songs in order (`MediaFile.contentKey`). Unused by smart playlists.
    public var itemKeys: [String] = []
    /// A smart playlist's rules (JSON of `SmartPlaylistRules`).
    public var rulesData: Data?

    public init(name: String) {
        self.name = name
    }

    public var isSmart: Bool { rulesData != nil }

    public var rules: SmartPlaylistRules? {
        get { rulesData.flatMap { try? JSONDecoder().decode(SmartPlaylistRules.self, from: $0) } }
        set { rulesData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

/// A song in a playlist, and where it is in the playlist's list.
public struct PlaylistItem: Identifiable {
    public let position: Int
    public let track: Track
    public var id: Int { position }
}

extension LibraryManager {
    // MARK: - Playlists

    public func playlists() -> [Playlist] {
        let descriptor = FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func makePlaylist(named name: String, rules: SmartPlaylistRules? = nil, tracks: [Track] = []) -> Playlist {
        let playlist = Playlist(name: Self.cleanName(name))
        playlist.rules = rules
        playlist.itemKeys = tracks.compactMap { $0.file?.contentKey }.filter { !$0.isEmpty }
        context.insert(playlist)
        playlistsChanged()
        return playlist
    }

    public func rename(_ playlist: Playlist, to name: String) {
        playlist.name = Self.cleanName(name)
        touch(playlist)
    }

    public func setRules(_ rules: SmartPlaylistRules, for playlist: Playlist) {
        playlist.rules = rules
        touch(playlist)
    }

    public func delete(_ playlist: Playlist) {
        deletedPlaylistIDs[playlist.id] = .now
        context.delete(playlist)
        playlistsChanged()
    }

    public func add(_ tracks: [Track], to playlist: Playlist) {
        guard !playlist.isSmart else { return }
        playlist.itemKeys += tracks.compactMap { $0.file?.contentKey }.filter { !$0.isEmpty }
        touch(playlist)
    }

    /// Removes the songs at these places in the playlist's list.
    public func removeItems(at offsets: IndexSet, from playlist: Playlist) {
        var keys = playlist.itemKeys
        for index in offsets.sorted(by: >) where keys.indices.contains(index) {
            keys.remove(at: index)
        }
        playlist.itemKeys = keys
        touch(playlist)
    }

    /// Moves the songs at `source` to before the song at `destination`
    /// (places in the playlist's list, as `List`'s move hands them over).
    public func moveItems(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        var keys = playlist.itemKeys
        let valid = source.filter { keys.indices.contains($0) }
        let moving = valid.sorted().map { keys[$0] }
        let before = valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) {
            keys.remove(at: index)
        }
        keys.insert(contentsOf: moving, at: min(max(0, destination - before), keys.count))
        playlist.itemKeys = keys
        touch(playlist)
    }

    /// The songs in a playlist, in order. Songs that aren't in this library
    /// (removed, or only on another device) are left out; see `missingCount`.
    public func tracks(in playlist: Playlist) -> [Track] {
        if let rules = playlist.rules {
            return smartTracks(rules)
        }
        let byKey = tracksByContentKey(Set(playlist.itemKeys))
        return playlist.itemKeys.compactMap { byKey[$0] }
    }

    /// A playlist's songs with their places in it (a regular playlist can
    /// list songs this library doesn't have, which are skipped).
    public func items(in playlist: Playlist) -> [PlaylistItem] {
        if let rules = playlist.rules {
            return smartTracks(rules).enumerated().map { PlaylistItem(position: $0.offset, track: $0.element) }
        }
        let byKey = tracksByContentKey(Set(playlist.itemKeys))
        return playlist.itemKeys.enumerated().compactMap { index, key in
            byKey[key].map { PlaylistItem(position: index, track: $0) }
        }
    }

    /// Up to `limit` different covers from a regular playlist, for its tile.
    public func artworkKeys(for playlist: Playlist, limit: Int = 4) -> [String] {
        guard !playlist.isSmart else { return [] }
        let keys = Array(playlist.itemKeys.prefix(40))
        let byKey = tracksByContentKey(Set(keys))
        var result: [String] = []
        for key in keys {
            guard let track = byKey[key], let art = track.album?.artworkKey ?? track.artworkKey, !result.contains(art) else { continue }
            result.append(art)
            if result.count == limit { break }
        }
        return result
    }

    /// Songs a regular playlist lists that this library doesn't have.
    public func missingCount(in playlist: Playlist) -> Int {
        guard !playlist.isSmart else { return 0 }
        let byKey = tracksByContentKey(Set(playlist.itemKeys))
        return playlist.itemKeys.count { byKey[$0] == nil }
    }

    /// Reads an M3U, PLS or XSPF file and keeps it as a playlist of the
    /// library songs it lists (matched by path, then by file name).
    public func importPlaylist(from url: URL) throws -> (playlist: Playlist, missing: Int) {
        let entries = try PlaylistFile.entries(at: url)
        let audio = PlaybackItem.Kind.audio.rawValue
        let files = (try? context.fetch(FetchDescriptor<MediaFile>(predicate: #Predicate { $0.kindRaw == audio }))) ?? []
        var byPath: [String: MediaFile] = [:]
        var byName: [String: [MediaFile]] = [:]
        for file in files where file.track != nil {
            if let fileURL = self.url(for: file) {
                byPath[fileURL.standardizedFileURL.path] = file
            }
            byName[file.fileName.lowercased(), default: []].append(file)
        }
        var keys: [String] = []
        var missing = 0
        for entry in entries {
            let match = byPath[entry.url.standardizedFileURL.path]
                ?? byName[entry.url.lastPathComponent.lowercased()].flatMap { $0.count == 1 ? $0.first : nil }
            if let key = match?.contentKey, !key.isEmpty {
                keys.append(key)
            } else {
                missing += 1
            }
        }
        let playlist = Playlist(name: Self.cleanName(url.deletingPathExtension().lastPathComponent))
        playlist.itemKeys = keys
        context.insert(playlist)
        playlistsChanged()
        return (playlist, missing)
    }

    /// Every song that can play now, by title.
    public func allAvailableTracks() -> [Track] {
        var descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { $0.file?.isAvailable == true },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        // Each song's file is read too: fetched together, not one by one.
        descriptor.relationshipKeyPathsForPrefetching = [\.file]
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Helpers

    func tracksByContentKey(_ keys: Set<String>) -> [String: Track] {
        guard !keys.isEmpty else { return [:] }
        let audio = PlaybackItem.Kind.audio.rawValue
        let list = Array(keys)
        let files = (try? context.fetch(FetchDescriptor<MediaFile>(predicate: #Predicate { list.contains($0.contentKey) && $0.kindRaw == audio }))) ?? []
        var result: [String: Track] = [:]
        for file in files {
            if let track = file.track, result[file.contentKey] == nil {
                result[file.contentKey] = track
            }
        }
        return result
    }

    private func smartTracks(_ rules: SmartPlaylistRules) -> [Track] {
        let tracks = allAvailableTracks()
        let records = (try? context.fetch(FetchDescriptor<PlaybackRecord>())) ?? []
        let byKey = Dictionary(records.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
        return rules.select(tracks) { track in
            let record = track.file.flatMap { byKey[$0.contentKey] }
            return SmartPlaylistRules.Song(
                title: track.title,
                artist: track.artistName,
                album: track.albumTitle,
                genre: track.genreName ?? "",
                year: track.year,
                dateAdded: track.dateAdded,
                lastPlayed: record?.lastPlayedDate,
                playCount: record?.playCount ?? 0,
                duration: track.duration
            )
        }
    }

    private func touch(_ playlist: Playlist) {
        playlist.dateModified = .now
        playlistsChanged()
    }

    private func playlistsChanged() {
        save()
        bumpRevision()
        onUserStateChange?()
    }

    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Playlist" : trimmed
    }
}
