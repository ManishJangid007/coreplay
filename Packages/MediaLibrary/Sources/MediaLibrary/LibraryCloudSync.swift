import Foundation
import SwiftData

/// Where iCloud keeps small values: `NSUbiquitousKeyValueStore`, or a
/// stand-in for tests.
public protocol CloudValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudValueStore {
    public func setData(_ data: Data?, forKey key: String) {
        if let data {
            set(data, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

/// Syncs what you did, not what you have, through iCloud key-value storage:
/// play counts, where videos got to, watched state, favourites and playlists,
/// keyed by content fingerprint. Each device keeps scanning its own files;
/// a song or video that's only on the other device simply isn't shown.
/// Needs the iCloud ▸ Key-value storage capability; without it nothing syncs.
@MainActor
public final class LibraryCloudSync {
    public static let recordsKey = "coreplay.records.v1"
    public static let playlistsKey = "coreplay.playlists.v1"
    /// The most play records sent (iCloud keeps 1 MB per app).
    static let recordLimit = 2_500

    struct Record: Codable, Equatable {
        var plays: Int
        var last: Date?
        var position: Double?
        var duration: Double?
        var watched: Bool
        var watchedAt: Date?
        var favorite: Bool
        var rating: Int?

        enum CodingKeys: String, CodingKey {
            case plays = "c", last = "l", position = "p", duration = "d", watched = "w", watchedAt = "wa", favorite = "f", rating = "r"
        }

        init(_ record: PlaybackRecord) {
            plays = record.playCount
            last = record.lastPlayedDate
            position = record.position
            duration = record.duration
            watched = record.isWatched
            watchedAt = record.watchedDate
            favorite = record.isFavorite
            rating = record.rating
        }

        /// Counts add up to the larger; the rest follows whichever device played it last.
        func merged(with other: Record) -> Record {
            var merged = (other.last ?? .distantPast) > (last ?? .distantPast) ? other : self
            merged.plays = max(plays, other.plays)
            merged.duration = merged.duration ?? other.duration ?? duration
            return merged
        }

        func apply(to record: PlaybackRecord) {
            record.playCount = plays
            record.lastPlayedDate = last
            record.position = position
            record.duration = duration
            record.isWatched = watched
            record.watchedDate = watchedAt
            record.isFavorite = favorite
            record.rating = rating
        }
    }

    struct SyncedPlaylist: Codable, Equatable {
        var id: UUID
        var name: String
        var created: Date
        var modified: Date
        var keys: [String]
        var rules: Data?

        init(_ playlist: Playlist) {
            id = playlist.id
            name = playlist.name
            created = playlist.dateCreated
            modified = playlist.dateModified
            keys = playlist.itemKeys
            rules = playlist.rulesData
        }
    }

    struct Playlists: Codable, Equatable {
        var playlists: [SyncedPlaylist] = []
        var deleted: [UUID: Date] = [:]
    }

    private let library: LibraryManager
    private let store: CloudValueStore
    private var pushTask: Task<Void, Never>?
    private var observer: (any NSObjectProtocol)?

    public init(library: LibraryManager, store: CloudValueStore = NSUbiquitousKeyValueStore.default) {
        self.library = library
        self.store = store
    }

    /// Brings in what other devices sent, sends what's here, and keeps doing so.
    public func start() {
        library.onUserStateChange = { [weak self] in
            self?.schedulePush()
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pull()
            }
        }
        store.synchronize()
        pull()
        schedulePush()
    }

    /// Applies what iCloud holds to this library.
    public func pull() {
        let decoder = Self.decoder
        var changed = false
        if let data = store.data(forKey: Self.recordsKey),
           let remote = try? decoder.decode([String: Record].self, from: data) {
            let local = Dictionary(((try? library.context.fetch(FetchDescriptor<PlaybackRecord>())) ?? []).map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
            for (key, incoming) in remote where !key.isEmpty {
                if let record = local[key] {
                    let current = Record(record)
                    let merged = current.merged(with: incoming)
                    if merged != current {
                        merged.apply(to: record)
                        changed = true
                    }
                } else {
                    let record = PlaybackRecord(contentKey: key)
                    incoming.apply(to: record)
                    library.context.insert(record)
                    changed = true
                }
            }
        }
        if let data = store.data(forKey: Self.playlistsKey),
           let remote = try? decoder.decode(Playlists.self, from: data) {
            let local = Dictionary(library.playlists().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, deletedAt) in remote.deleted {
                if let playlist = local[id], playlist.dateModified <= deletedAt {
                    library.context.delete(playlist)
                    changed = true
                }
            }
            for incoming in remote.playlists {
                if let deletedHere = library.deletedPlaylistIDs[incoming.id], deletedHere >= incoming.modified { continue }
                if let deletedThere = remote.deleted[incoming.id], deletedThere >= incoming.modified { continue }
                if let playlist = local[incoming.id] {
                    guard incoming.modified > playlist.dateModified else { continue }
                    playlist.name = incoming.name
                    playlist.itemKeys = incoming.keys
                    playlist.rulesData = incoming.rules
                    playlist.dateModified = incoming.modified
                } else {
                    let playlist = Playlist(name: incoming.name)
                    playlist.id = incoming.id
                    playlist.dateCreated = incoming.created
                    playlist.dateModified = incoming.modified
                    playlist.itemKeys = incoming.keys
                    playlist.rulesData = incoming.rules
                    library.context.insert(playlist)
                }
                changed = true
            }
        }
        guard changed else { return }
        library.save()
        library.loadWatchStates()
        library.bumpRevision()
    }

    /// Sends this library's state, merged with what iCloud already holds.
    public func pushNow() {
        pushTask?.cancel()
        pushTask = nil
        let decoder = Self.decoder
        let encoder = Self.encoder

        var records = (try? store.data(forKey: Self.recordsKey).map { try decoder.decode([String: Record].self, from: $0) }) ?? [:]
        let local = ((try? library.context.fetch(FetchDescriptor<PlaybackRecord>())) ?? [])
            .filter { !$0.contentKey.isEmpty && ($0.playCount > 0 || $0.position != nil || $0.isWatched || $0.isFavorite || $0.rating != nil) }
        for record in local {
            let mine = Record(record)
            records[record.contentKey] = records[record.contentKey].map { $0.merged(with: mine) } ?? mine
        }
        if records.count > Self.recordLimit {
            let kept = records.sorted { ($0.value.last ?? .distantPast) > ($1.value.last ?? .distantPast) }.prefix(Self.recordLimit)
            records = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        if let data = try? encoder.encode(records) {
            store.setData(data, forKey: Self.recordsKey)
        }

        var playlists = (try? store.data(forKey: Self.playlistsKey).map { try decoder.decode(Playlists.self, from: $0) }) ?? Playlists()
        for (id, date) in library.deletedPlaylistIDs {
            playlists.deleted[id] = max(date, playlists.deleted[id] ?? .distantPast)
        }
        var byID = Dictionary(playlists.playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for playlist in library.playlists() {
            let mine = SyncedPlaylist(playlist)
            if let theirs = byID[mine.id], theirs.modified > mine.modified { continue }
            byID[mine.id] = mine
        }
        playlists.playlists = byID.values
            .filter { playlist in (playlists.deleted[playlist.id] ?? .distantPast) < playlist.modified }
            .sorted { $0.name < $1.name }
        if let data = try? encoder.encode(playlists) {
            store.setData(data, forKey: Self.playlistsKey)
        }
        store.synchronize()
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.pushNow()
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
