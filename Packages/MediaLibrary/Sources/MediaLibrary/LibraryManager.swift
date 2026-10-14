import Foundation
import MetadataProviders
import Observation
import PlaybackCore
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

/// The library as the app sees it: sources, scanning, playback items for
/// library content, play counts, watched state and edits. Views read the
/// models with `@Query` from `container`; this object does everything else.
///
/// All background work runs one job at a time on `LibraryIndexer` (its own
/// model context): scans, removals, lookups and frame grabs. Videos,
/// shows and seasons are only ever written there, so the main context never
/// races it; play history (`PlaybackRecord`) is only written here.
@MainActor
@Observable
public final class LibraryManager {
    public enum Activity: Equatable, Sendable {
        case idle
        case scanning(sourceID: UUID, sourceName: String, processed: Int, total: Int)
        /// Fetching details and artwork (TMDB, or TVmaze and Wikipedia).
        case lookingUp
    }

    /// One unit of background work.
    enum Job: Equatable {
        case scan(UUID)
        case remove(UUID)
        case lookUp
        case thumbnails
    }

    public enum LibraryError: LocalizedError {
        case alreadyAdded(String)
        case insideExistingSource(String)
        case containsExistingSource(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyAdded(let name):
                "\u{201C}\(name)\u{201D} is already in your library."
            case .insideExistingSource(let name):
                "This folder is already part of \u{201C}\(name)\u{201D}."
            case .containsExistingSource(let name):
                "This folder contains \u{201C}\(name)\u{201D}, which is already in your library. Remove it first, then add the larger folder."
            }
        }
    }

    public let container: ModelContainer
    public let artworkStore: ArtworkStore
    public private(set) var activity: Activity = .idle
    /// The last scanning or storage problem, for the Sources screen.
    public var lastError: String?
    /// Bumped whenever scans, play counts or edits change the library, for
    /// views that compute things `@Query` can't express.
    public private(set) var revision = 0
    /// Watched state and resume positions by content key (see `watchState(for:)`).
    public internal(set) var watchStates: [String: WatchState] = [:]
    /// Whether a TMDB key is set (Settings ▸ Metadata).
    public internal(set) var hasMetadataKey = false
    /// Without a TMDB key, look videos up on TVmaze (shows) and Wikipedia
    /// (movies), which need no key. On unless turned off in Settings.
    public internal(set) var usesFreeMetadataSources = false
    /// The last lookup problem (a rejected key, no connection), for Settings.
    public internal(set) var metadataProblem: String?
    /// Movies and shows the user added with "+" (see `LibraryManager+Watchlist`),
    /// newest first, as `WatchlistEntry` identifiers.
    public internal(set) var watchlist: [String] = []
    /// Grabs frames for video artwork; set by the app (it lives in PlaybackEngine).
    @ObservationIgnored public var frameSource: (any VideoFrameSource)?
    /// Find lyrics online (LRCLIB) for songs without any. Off unless turned on in Settings.
    public internal(set) var looksUpLyrics = false
    /// Playlists deleted on this device, so iCloud sync doesn't bring them back.
    @ObservationIgnored public internal(set) var deletedPlaylistIDs: [UUID: Date] = [:]

    @ObservationIgnored private var indexerTask: Task<LibraryIndexer, Never>?
    @ObservationIgnored var roots: [UUID: URL] = [:]
    @ObservationIgnored private var scopedRoots: [UUID: URL] = [:]
    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var currentJob: (job: Job, task: Task<Void, Never>)?
    @ObservationIgnored private var lastFullScan: Date?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored var metadataKey: String?
    @ObservationIgnored var persistsWatchlist = false
    #if os(macOS)
    @ObservationIgnored private var watchers: [UUID: FolderWatcher] = [:]
    @ObservationIgnored private var pendingWatchRescans: Set<UUID> = []
    #endif

    /// - Parameter inMemory: Keeps everything in memory (tests and previews).
    public init(inMemory: Bool = false) {
        var openError: String?
        if let container = try? LibraryStore.makeContainer(inMemory: inMemory) {
            self.container = container
        } else if let container = try? LibraryStore.makeContainer(inMemory: true) {
            // A damaged store mustn't stop the app from playing files.
            self.container = container
            openError = "Your library couldn\u{2019}t be opened, so a temporary one is being used. Your files are untouched."
        } else {
            fatalError("The library schema is invalid.")
        }
        let artworkDirectory = inMemory
            ? FileManager.default.temporaryDirectory.appending(path: "CoreplayArtwork-\(UUID().uuidString)", directoryHint: .isDirectory)
            : ArtworkStore.defaultDirectory
        artworkStore = ArtworkStore(directory: artworkDirectory)
        lastError = openError
        if !inMemory {
            metadataKey = MetadataKeyStore.load()
            hasMetadataKey = metadataKey != nil
            usesFreeMetadataSources = UserDefaults.standard.object(forKey: Self.freeSourcesKey) as? Bool ?? true
            watchlist = UserDefaults.standard.stringArray(forKey: Self.watchlistKey) ?? []
            looksUpLyrics = UserDefaults.standard.bool(forKey: Self.lyricsLookupKey)
        }
        persistsWatchlist = !inMemory
    }

    public var context: ModelContext { container.mainContext }

    /// Called after play counts, progress, watched state or playlists
    /// change, so iCloud sync can send them (`LibraryCloudSync`).
    @ObservationIgnored public var onUserStateChange: (@MainActor () -> Void)?

    func bumpRevision() {
        revision += 1
    }

    public var isScanning: Bool {
        if case .scanning = activity { return true }
        return false
    }

    // MARK: - Starting up

    /// Call once at launch: adds the default source, reconnects the others and
    /// scans whatever changed since last time, in the background.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        addDefaultSources()
        for source in sources() {
            connect(source)
        }
        save()
        loadWatchStates()
        scanAll()
        retakeSquashedFramesIfNeeded()
    }

    /// Version 2 of frames taken from videos (see `clearSquashedFrames`).
    static let frameVersionKey = "library.frameVersion"

    private func retakeSquashedFramesIfNeeded() {
        guard UserDefaults.standard.integer(forKey: Self.frameVersionKey) < 2 else { return }
        Task {
            let indexer = await indexer()
            let cleared = (try? await indexer.clearSquashedFrames()) ?? 0
            UserDefaults.standard.set(2, forKey: Self.frameVersionKey)
            if cleared > 0 {
                bumpRevision()
            }
            enqueue(.thumbnails)
        }
    }

    /// iOS: rescans when the app comes back to the foreground, at most every few minutes.
    public func refreshIfStale(minimumInterval: TimeInterval = 300) {
        guard hasStarted else { return }
        if let lastFullScan, Date.now.timeIntervalSince(lastFullScan) < minimumInterval { return }
        scanAll()
    }

    public func scanAll() {
        lastFullScan = .now
        for source in sources() {
            enqueue(.scan(source.id))
        }
    }

    public func rescan(_ source: Source) {
        enqueue(.scan(source.id))
    }

    public func sources() -> [Source] {
        (try? context.fetch(FetchDescriptor<Source>(sortBy: [SortDescriptor(\.dateAdded)]))) ?? []
    }

    // MARK: - Adding and removing sources

    /// Adds a folder or file the user picked or dropped. The URL must still
    /// carry its security scope (straight from the picker or the drop).
    @discardableResult
    public func addSource(at url: URL) throws -> Source {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let standardized = url.standardizedFileURL
        let path = standardized.path(percentEncoded: false)
        let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        try checkOverlap(path: path, isDirectory: isDirectory)

        let bookmark = try SourceAccess.bookmark(for: standardized)
        let name = standardized.lastPathComponent
        let source = Source(name: name, kind: isDirectory ? .folder : .file, bookmarkData: bookmark, path: path)
        context.insert(source)
        save()
        connect(source)
        enqueue(.scan(source.id))
        return source
    }

    #if os(macOS)
    public var hasMusicFolder: Bool { sources().contains { $0.kind == .musicFolder } }
    public var hasMoviesFolder: Bool { sources().contains { $0.kind == .moviesFolder } }

    /// Adds ~/Music (the sandbox grants read access to it).
    public func addMusicFolder() {
        addFixedSource(kind: .musicFolder, name: "Music", root: SourceAccess.musicDirectory)
    }

    public func addMoviesFolder() {
        addFixedSource(kind: .moviesFolder, name: "Movies", root: SourceAccess.moviesDirectory)
    }

    private func addFixedSource(kind: SourceKind, name: String, root: URL) {
        guard !sources().contains(where: { $0.kind == kind }) else { return }
        let source = Source(name: name, kind: kind, path: root.path(percentEncoded: false))
        context.insert(source)
        save()
        connect(source)
        enqueue(.scan(source.id))
    }
    #endif

    /// Removes a source and its songs and videos from the library (the files
    /// themselves are untouched).
    public func remove(_ source: Source) {
        let id = source.id
        jobs.removeAll { $0 == .scan(id) }
        // A scan of this source stops at its next batch.
        if let currentJob, currentJob.job == .scan(id) {
            currentJob.task.cancel()
        }
        roots[id] = nil
        if let scoped = scopedRoots.removeValue(forKey: id) {
            scoped.stopAccessingSecurityScopedResource()
        }
        #if os(macOS)
        watchers.removeValue(forKey: id)?.stop()
        #endif
        enqueue(.remove(id), first: true)
    }

    /// The folder (or file) a source points at, while it's connected.
    public func location(of source: Source) -> URL? {
        roots[source.id]
    }

    // MARK: - Playing library content

    /// The file URL for a library file, when its source is connected.
    public func url(for file: MediaFile) -> URL? {
        guard let source = file.source, let root = roots[source.id] else { return nil }
        return file.relativePath.isEmpty ? root : root.appending(path: file.relativePath, directoryHint: .notDirectory)
    }

    public func artworkURL(_ key: String?, _ variant: ArtworkStore.Variant) -> URL? {
        guard let key else { return nil }
        return artworkStore.url(for: key, variant: variant)
    }

    public func playbackItem(for track: Track) -> PlaybackItem? {
        guard let file = track.file, file.isAvailable, let url = url(for: file) else { return nil }
        return PlaybackItem(
            url: url,
            kind: .audio,
            title: track.title,
            artist: track.artistName,
            albumTitle: track.albumTitle,
            artworkURL: artworkURL(track.artworkKey ?? track.album?.artworkKey, .large),
            enginePreference: file.enginePreference,
            libraryID: file.id
        )
    }

    /// Playable items for `tracks`, skipping unavailable ones.
    public func playbackItems(for tracks: [Track]) -> [PlaybackItem] {
        tracks.compactMap(playbackItem(for:))
    }

    /// Any library file: songs and videos with their library details, other
    /// files with a title from the file name.
    public func playbackItem(for file: MediaFile) -> PlaybackItem? {
        if let track = file.track {
            return playbackItem(for: track)
        }
        if let video = file.video {
            return playbackItem(for: video)
        }
        guard file.isAvailable, let url = url(for: file) else { return nil }
        return PlaybackItem(url: url, kind: file.kind, enginePreference: file.enginePreference, libraryID: file.id)
    }

    // MARK: - Play history

    /// Counts a play (the app calls this when `ListeningTracker` says so).
    public func recordPlay(libraryID: UUID) {
        guard let file = mediaFile(id: libraryID) else { return }
        let record = playbackRecord(contentKey: file.contentKey)
        record.playCount += 1
        record.lastPlayedDate = .now
        save()
        revision += 1
        onUserStateChange?()
    }

    /// Stores a duration the player learned for a file the scanner couldn't time.
    public func noteDuration(_ duration: TimeInterval, libraryID: UUID) {
        guard duration > 0, duration.isFinite, let file = mediaFile(id: libraryID) else { return }
        if let known = file.duration, abs(known - duration) < 1 { return }
        file.duration = duration
        file.track?.duration = duration
        save()
    }

    /// Albums of the songs played most recently, newest first.
    public func recentlyPlayedAlbums(limit: Int = 12) -> [Album] {
        var descriptor = FetchDescriptor<PlaybackRecord>(
            predicate: #Predicate { $0.lastPlayedDate != nil },
            sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return [] }
        let keys = records.map(\.contentKey)
        let files = (try? context.fetch(FetchDescriptor<MediaFile>(predicate: #Predicate { keys.contains($0.contentKey) }))) ?? []
        let filesByKey = Dictionary(files.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<PersistentIdentifier>()
        var albums: [Album] = []
        for key in keys {
            guard let album = filesByKey[key]?.track?.album, seen.insert(album.persistentModelID).inserted else { continue }
            albums.append(album)
            if albums.count == limit { break }
        }
        return albums
    }

    /// Your most played songs, most plays first: the Songs chart.
    public func mostPlayedTracks(limit: Int = 10) -> [Track] {
        var descriptor = FetchDescriptor<PlaybackRecord>(
            predicate: #Predicate { $0.playCount > 0 },
            sortBy: [SortDescriptor(\.playCount, order: .reverse), SortDescriptor(\.lastPlayedDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 4
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return [] }
        let keys = records.map(\.contentKey)
        let audio = PlaybackItem.Kind.audio.rawValue
        let files = (try? context.fetch(FetchDescriptor<MediaFile>(predicate: #Predicate { keys.contains($0.contentKey) && $0.kindRaw == audio }))) ?? []
        let filesByKey = Dictionary(files.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(keys.lazy.compactMap { filesByKey[$0]?.track }.filter(\.isAvailable).prefix(limit))
    }

    public func playCount(for file: MediaFile) -> Int {
        existingRecord(contentKey: file.contentKey)?.playCount ?? 0
    }

    // MARK: - Edit Info

    /// Applies Edit Info changes. Edited fields are remembered so rescans
    /// never overwrite them.
    public func apply(_ edit: TrackEdit, to track: Track) {
        var edited = Set(track.editedFields)
        func update<Value: Equatable>(_ field: TrackField, _ keyPath: ReferenceWritableKeyPath<Track, Value>, _ value: Value) {
            guard track[keyPath: keyPath] != value else { return }
            track[keyPath: keyPath] = value
            edited.insert(field.rawValue)
        }
        update(.title, \.title, edit.title)
        update(.artist, \.artistName, edit.artist)
        update(.album, \.albumTitle, edit.album)
        update(.albumArtist, \.albumArtistName, edit.albumArtist)
        update(.genre, \.genreName, edit.genre)
        update(.year, \.year, edit.year)
        update(.trackNumber, \.trackNumber, edit.trackNumber)
        update(.discNumber, \.discNumber, edit.discNumber)
        update(.compilation, \.isCompilation, edit.isCompilation)
        track.sortTitle = NameNormalizer.sortKey(track.title)
        track.editedFields = edited.sorted()

        let grouper = LibraryGrouper(context: context)
        grouper.attach(track)
        do {
            try grouper.removeOrphans()
        } catch {
            lastError = "Couldn\u{2019}t save your changes: \(error.localizedDescription)"
        }
        revision += 1
    }

    // MARK: - Background jobs

    func enqueue(_ job: Job, first: Bool = false) {
        if !jobs.contains(job) {
            if first {
                jobs.insert(job, at: 0)
            } else {
                jobs.append(job)
            }
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            let task = Task { [weak self] in
                guard let self else { return }
                await self.perform(job)
            }
            currentJob = (job, task)
            await task.value
            currentJob = nil
        }
        activity = .idle
        worker = nil
    }

    private func perform(_ job: Job) async {
        switch job {
        case .scan(let id):
            await scan(sourceID: id)
            // New videos get details and artwork once the scans are done.
            enqueue(.lookUp)
            enqueue(.thumbnails)
        case .remove(let id):
            await removeSource(id: id)
        case .lookUp:
            await lookUpBatch()
        case .thumbnails:
            if jobs.contains(.lookUp) {
                // Lookups may bring real artwork; take frames after them.
                enqueue(.thumbnails)
            } else {
                await thumbnailBatch()
            }
        }
    }

    private func removeSource(id: UUID) async {
        let indexer = await indexer()
        do {
            try await indexer.removeSource(id: id)
            let keys = try await indexer.artworkKeysInUse()
            let store = artworkStore
            await Task.detached(priority: .utility) { store.removeAll(except: keys) }.value
        } catch {
            lastError = "Couldn\u{2019}t remove the source: \(error.localizedDescription)"
        }
        revision += 1
    }

    static let freeSourcesKey = "metadata.usesFreeSources"

    /// One batch of lookups (TMDB with a key, otherwise TVmaze and
    /// Wikipedia); queues another while there's more to do, behind any
    /// scans that arrived meanwhile.
    private func lookUpBatch() async {
        guard let key = metadataKey else {
            if usesFreeMetadataSources {
                await keylessLookUpBatch()
            }
            return
        }
        let client = TMDBClient(key: key)
        let indexer = await indexer()
        activity = .lookingUp
        do {
            let settled = try await indexer.lookUpPending(client: client, artworkStore: artworkStore)
            metadataProblem = nil
            if settled > 0 {
                revision += 1
                enqueue(.lookUp)
            }
        } catch is CancellationError {
            // Picked up again after the next scan.
        } catch let failure as TMDBClient.Failure {
            metadataProblem = failure.localizedDescription
        } catch {
            // Offline or a timeout: try again with the next scan.
            metadataProblem = "Couldn\u{2019}t reach TMDB: \(error.localizedDescription)"
        }
        activity = .idle
    }

    private func keylessLookUpBatch() async {
        let indexer = await indexer()
        activity = .lookingUp
        do {
            let settled = try await indexer.lookUpPendingWithoutKey(tvmaze: TVmazeClient(), wikipedia: WikipediaClient(), artworkStore: artworkStore)
            metadataProblem = nil
            if settled > 0 {
                revision += 1
                enqueue(.lookUp)
            }
        } catch is CancellationError {
            // Picked up again after the next scan.
        } catch {
            // Offline or rate limited: try again with the next scan.
            metadataProblem = "Couldn\u{2019}t reach TVmaze or Wikipedia: \(error.localizedDescription)"
        }
        activity = .idle
    }

    private func thumbnailBatch() async {
        guard let frameSource else { return }
        let indexer = await indexer()
        let tried = await indexer.generateThumbnails(frameSource: frameSource, roots: roots, artworkStore: artworkStore)
        if tried > 0 {
            revision += 1
            enqueue(.thumbnails)
        }
    }

    // MARK: - Scanning

    private func scan(sourceID id: UUID) async {
        guard let source = source(id: id) else { return }
        let indexer = await indexer()
        guard let root = connect(source) else {
            try? await indexer.markUnavailable(sourceID: id)
            revision += 1
            return
        }
        let name = source.name
        let isSingleFile = source.kind == .file
        activity = .scanning(sourceID: id, sourceName: name, processed: 0, total: 0)
        do {
            _ = try await indexer.scan(sourceID: id, root: root, isSingleFile: isSingleFile, artworkStore: artworkStore) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .scanning(let current, _, _, _) = self.activity, current == progress.sourceID else { return }
                    self.activity = .scanning(sourceID: progress.sourceID, sourceName: name, processed: progress.processed, total: progress.total)
                }
            }
        } catch is CancellationError {
            // Cancelled: the next scan picks up where this one stopped.
        } catch {
            lastError = "Couldn\u{2019}t finish scanning \u{201C}\(name)\u{201D}: \(error.localizedDescription)"
        }
        activity = .idle
        revision += 1
    }

    func indexer() async -> LibraryIndexer {
        if let indexerTask {
            return await indexerTask.value
        }
        let container = self.container
        // Created off the main actor so its context works on a background queue.
        let task = Task.detached(priority: .utility) {
            LibraryIndexer(modelContainer: container)
        }
        indexerTask = task
        return await task.value
    }

    // MARK: - Connecting sources

    /// Resolves a source's folder, keeps its security scope open while the
    /// app runs, and starts watching it on the Mac. `nil` when unreachable.
    @discardableResult
    private func connect(_ source: Source) -> URL? {
        if let root = roots[source.id] {
            return root
        }
        var root: URL?
        var changed = false
        // Save straight away: the scanner's context edits sources too, and
        // unsaved edits here would conflict with its saves.
        defer {
            if changed { save() }
        }
        switch source.kind {
        case .appDocuments:
            root = SourceAccess.documentsDirectory
        case .folder, .file:
            if let bookmark = source.bookmarkData, let resolved = try? SourceAccess.resolve(bookmark) {
                if resolved.url.startAccessingSecurityScopedResource() {
                    scopedRoots[source.id] = resolved.url
                }
                if resolved.isStale, let fresh = try? SourceAccess.bookmark(for: resolved.url) {
                    source.bookmarkData = fresh
                    changed = true
                }
                root = resolved.url
            }
        case .musicFolder:
            #if os(macOS)
            root = SourceAccess.musicDirectory
            #else
            break
            #endif
        case .moviesFolder:
            #if os(macOS)
            root = SourceAccess.moviesDirectory
            #else
            break
            #endif
        }
        guard let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            if source.isAvailable {
                source.isAvailable = false
                changed = true
            }
            return nil
        }
        roots[source.id] = root
        let path = root.path(percentEncoded: false)
        if source.lastKnownPath != path {
            source.lastKnownPath = path
            changed = true
        }
        if !source.isAvailable {
            source.isAvailable = true
            changed = true
        }
        #if os(macOS)
        watch(source.id, root: root, isFile: source.kind == .file)
        #endif
        return root
    }

    #if os(macOS)
    private func watch(_ id: UUID, root: URL, isFile: Bool) {
        guard watchers[id] == nil else { return }
        let folder = isFile ? root.deletingLastPathComponent() : root
        watchers[id] = FolderWatcher(url: folder) { [weak self] in
            Task { @MainActor in
                self?.folderChanged(id)
            }
        }
    }

    /// FSEvents already coalesces; this also waits for copies to settle.
    private func folderChanged(_ id: UUID) {
        guard pendingWatchRescans.insert(id).inserted else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            pendingWatchRescans.remove(id)
            enqueue(.scan(id))
        }
    }
    #endif

    private func addDefaultSources() {
        #if os(iOS)
        if !sources().contains(where: { $0.kind == .appDocuments }) {
            let name = UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone"
            let source = Source(name: name, kind: .appDocuments, path: SourceAccess.documentsDirectory.path(percentEncoded: false))
            context.insert(source)
        }
        #endif
    }

    private func checkOverlap(path: String, isDirectory: Bool) throws {
        let newPath = path.hasSuffix("/") ? path : path + "/"
        for source in sources() {
            let existing = source.lastKnownPath.hasSuffix("/") ? source.lastKnownPath : source.lastKnownPath + "/"
            if existing == newPath {
                throw LibraryError.alreadyAdded(source.name)
            }
            if source.kind != .file, newPath.hasPrefix(existing) {
                throw LibraryError.insideExistingSource(source.name)
            }
            if isDirectory, existing.hasPrefix(newPath) {
                throw LibraryError.containsExistingSource(source.name)
            }
        }
    }

    // MARK: - Lookups

    func source(id: UUID) -> Source? {
        var descriptor = FetchDescriptor<Source>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func mediaFile(id: UUID) -> MediaFile? {
        var descriptor = FetchDescriptor<MediaFile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func existingRecord(contentKey: String) -> PlaybackRecord? {
        var descriptor = FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.contentKey == contentKey })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func playbackRecord(contentKey: String) -> PlaybackRecord {
        if let existing = existingRecord(contentKey: contentKey) {
            return existing
        }
        let record = PlaybackRecord(contentKey: contentKey)
        context.insert(record)
        return record
    }

    func save() {
        do {
            try context.save()
        } catch {
            lastError = "Couldn\u{2019}t save the library: \(error.localizedDescription)"
        }
    }
}

/// The values Edit Info shows and changes.
public struct TrackEdit: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String?
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var isCompilation: Bool

    public init(track: Track) {
        title = track.title
        artist = track.artistName
        album = track.albumTitle
        albumArtist = track.albumArtistName
        genre = track.genreName
        year = track.year
        trackNumber = track.trackNumber
        discNumber = track.discNumber
        isCompilation = track.isCompilation
    }
}
