import Foundation
import MetadataProviders
import PlaybackCore
import SwiftData

/// A video's watched state and resume position (kept in `PlaybackRecord`).
public struct WatchState: Sendable, Equatable {
    public var position: TimeInterval?
    public var duration: TimeInterval?
    public var isWatched: Bool
    public var lastPlayedDate: Date?

    init(_ record: PlaybackRecord) {
        position = record.position
        duration = record.duration
        isWatched = record.isWatched
        lastPlayedDate = record.lastPlayedDate
    }

    /// Started and not finished.
    public var isInProgress: Bool {
        !isWatched && position != nil
    }

    /// 0…1 for progress bars, while in progress.
    public var progress: Double? {
        isInProgress ? ResumePolicy.progress(position: position, duration: duration) : nil
    }

    public var remaining: TimeInterval? {
        guard isInProgress, let position, let duration, duration > position else { return nil }
        return duration - position
    }
}

/// What a source folder's videos are, as the Sources screen offers it.
public enum VideoFolderContent: String, Sendable, CaseIterable, Identifiable {
    case automatic, movies, tvShows, homeVideos

    public var id: Self { self }

    public var title: String {
        switch self {
        case .automatic: "Decide from Names"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .homeVideos: "Home Videos"
        }
    }

    init(_ hint: VideoContentHint) {
        self = VideoFolderContent(rawValue: hint.rawValue) ?? .automatic
    }

    var hint: VideoContentHint {
        VideoContentHint(rawValue: rawValue) ?? .automatic
    }
}

extension Source {
    /// What the user said this folder's videos are.
    public var videoContent: VideoFolderContent {
        VideoFolderContent(videoHint)
    }
}

extension LibraryManager {
    // MARK: - Watched state

    func loadWatchStates() {
        let descriptor = FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.position != nil || $0.isWatched == true })
        var states: [String: WatchState] = [:]
        for record in (try? context.fetch(descriptor)) ?? [] {
            states[record.contentKey] = WatchState(record)
        }
        watchStates = states
    }

    public func watchState(for video: Video) -> WatchState? {
        guard let key = video.file?.contentKey, !key.isEmpty else { return nil }
        return watchStates[key]
    }

    public func isWatched(_ video: Video) -> Bool {
        watchState(for: video)?.isWatched ?? false
    }

    /// Saves where a video got to (the app calls this with `WatchProgressTracker`'s saves).
    public func recordProgress(libraryID: UUID, position: TimeInterval, duration: TimeInterval?, outcome: ResumePolicy.Outcome) {
        guard let file = mediaFile(id: libraryID), file.kind == .video, !file.contentKey.isEmpty else { return }
        let record = playbackRecord(contentKey: file.contentKey)
        let wasInProgress = record.position != nil && !record.isWatched
        let wasWatched = record.isWatched
        switch outcome {
        case .fromStart:
            record.position = nil
        case .resume(let at):
            record.position = at
            record.isWatched = false
        case .watched:
            record.position = nil
            record.isWatched = true
            record.watchedDate = .now
            record.playCount += 1
        }
        if let duration, duration > 0 {
            record.duration = duration
        }
        record.lastPlayedDate = .now
        save()
        updateWatchState(record)
        // Home's rows change when something starts, finishes or stops being in progress.
        if wasInProgress != (record.position != nil && !record.isWatched) || wasWatched != record.isWatched {
            bumpRevision()
        }
    }

    public func markWatched(_ videos: [Video]) {
        for video in videos {
            guard let key = video.file?.contentKey, !key.isEmpty else { continue }
            let record = playbackRecord(contentKey: key)
            if !record.isWatched {
                record.isWatched = true
                record.watchedDate = .now
                record.playCount += 1
            }
            record.position = nil
            record.lastPlayedDate = record.lastPlayedDate ?? .now
            updateWatchState(record)
        }
        save()
        bumpRevision()
    }

    public func markUnwatched(_ videos: [Video]) {
        for video in videos {
            guard let key = video.file?.contentKey, let record = existingRecord(contentKey: key) else { continue }
            record.isWatched = false
            record.watchedDate = nil
            record.position = nil
            updateWatchState(record)
        }
        save()
        bumpRevision()
    }

    private func updateWatchState(_ record: PlaybackRecord) {
        if record.position == nil, !record.isWatched {
            watchStates[record.contentKey] = nil
        } else {
            watchStates[record.contentKey] = WatchState(record)
        }
    }

    // MARK: - Home rows

    /// Videos started and not finished, most recent first.
    public func continueWatching(limit: Int = 20) -> [Video] {
        let keys = watchStates
            .filter { $0.value.isInProgress }
            .sorted { ($0.value.lastPlayedDate ?? .distantPast) > ($1.value.lastPlayedDate ?? .distantPast) }
            .map(\.key)
        return videos(forContentKeys: Array(keys.prefix(limit * 2))).filter(\.isAvailable).prefix(limit).map { $0 }
    }

    /// The next episode of each show you've been watching, most recent show first.
    public func upNext(limit: Int = 20) -> [Video] {
        let keys = watchStates
            .filter { $0.value.lastPlayedDate != nil }
            .sorted { ($0.value.lastPlayedDate ?? .distantPast) > ($1.value.lastPlayedDate ?? .distantPast) }
            .map(\.key)
        var seenShows = Set<PersistentIdentifier>()
        var result: [Video] = []
        for video in videos(forContentKeys: Array(keys.prefix(300))) where video.kind == .episode {
            guard let show = video.show, seenShows.insert(show.persistentModelID).inserted else { continue }
            // An episode in progress is in Continue Watching; the show waits.
            if watchState(for: video)?.isInProgress == true { continue }
            if let next = nextEpisode(after: video) {
                result.append(next)
                if result.count == limit { break }
            }
        }
        return result
    }

    /// The next unwatched episode after `video` (specials only follow specials).
    public func nextEpisode(after video: Video) -> Video? {
        guard let show = video.show else { return nil }
        let episodes = show.orderedEpisodes.filter { ($0.seasonNumber == 0) == (video.seasonNumber == 0) }
        guard let index = episodes.firstIndex(where: { $0.id == video.id }) else { return nil }
        return episodes[(index + 1)...].first { $0.isAvailable && !isWatched($0) }
    }

    /// What a show page's main button plays: the episode in progress, the
    /// one after the last watched, or the first.
    public func nextUp(in show: TVShow) -> (video: Video, isResume: Bool)? {
        let episodes = show.orderedEpisodes.filter(\.isAvailable)
        var latest: (video: Video, state: WatchState, date: Date)?
        for episode in episodes {
            guard let state = watchState(for: episode), let date = state.lastPlayedDate else { continue }
            if latest == nil || date > latest!.date {
                latest = (episode, state, date)
            }
        }
        if let latest {
            if latest.state.isInProgress {
                return (latest.video, true)
            }
            if let next = nextEpisode(after: latest.video) {
                return (next, false)
            }
        }
        if let first = episodes.first(where: { $0.seasonNumber != 0 && !isWatched($0) }) {
            return (first, false)
        }
        return episodes.first.map { ($0, false) }
    }

    /// Videos for content keys, in the keys' order.
    private func videos(forContentKeys keys: [String]) -> [Video] {
        guard !keys.isEmpty else { return [] }
        let videoKind = PlaybackItem.Kind.video.rawValue
        let descriptor = FetchDescriptor<MediaFile>(predicate: #Predicate { keys.contains($0.contentKey) && $0.kindRaw == videoKind })
        let files = (try? context.fetch(descriptor)) ?? []
        let byKey = Dictionary(files.compactMap { file in file.video.map { (file.contentKey, $0) } }, uniquingKeysWith: { first, _ in first })
        var seen = Set<PersistentIdentifier>()
        return keys.compactMap { byKey[$0] }.filter { seen.insert($0.persistentModelID).inserted }
    }

    // MARK: - Playing videos

    /// A video to play, resuming where it was stopped unless `fromStart`.
    public func playbackItem(for video: Video, fromStart: Bool = false) -> PlaybackItem? {
        guard let file = video.file, file.isAvailable, let url = url(for: file) else { return nil }
        let state = watchState(for: video)
        let start = fromStart ? nil : ResumePolicy.startPosition(saved: state?.position, duration: state?.duration ?? video.duration)
        return PlaybackItem(
            url: url,
            kind: .video,
            title: video.displayTitle,
            artist: subtitle(for: video),
            artworkURL: artworkURL(video.stillArtworkKey ?? video.posterArtworkKey, .large),
            startPosition: start,
            enginePreference: file.enginePreference,
            externalSubtitleURLs: sidecarSubtitles(for: url),
            libraryID: file.id
        )
    }

    /// `video`, then (for episodes) the episodes after it, as the TV app
    /// plays them on.
    public func playbackItems(startingWith video: Video, fromStart: Bool = false) -> [PlaybackItem] {
        guard let first = playbackItem(for: video, fromStart: fromStart) else { return [] }
        guard video.kind == .episode, let show = video.show else { return [first] }
        let episodes = show.orderedEpisodes.filter { ($0.seasonNumber == 0) == (video.seasonNumber == 0) }
        guard let index = episodes.firstIndex(where: { $0.id == video.id }) else { return [first] }
        let following = episodes[(index + 1)...].prefix(40).compactMap { playbackItem(for: $0) }
        return [first] + following
    }

    /// "Breaking Bad · S1, E2" for episodes, the year for movies, the date for home videos.
    public func subtitle(for video: Video) -> String? {
        switch video.kind {
        case .episode:
            return [video.showTitle, video.episodeLabel].compactMap { $0 }.joined(separator: " \u{00B7} ")
        case .movie:
            return video.year.map(String.init)
        case .homeVideo:
            return video.file?.recordedDate?.formatted(date: .long, time: .omitted)
        }
    }

    /// Subtitle files next to a video that share its name (`Movie.srt`, `Movie.en.srt`).
    func sidecarSubtitles(for url: URL) -> [URL] {
        guard url.isFileURL else { return [] }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return [] }
        return names
            .filter { name in
                let lowered = name.lowercased()
                let ext = (lowered.split(separator: ".").last.map(String.init) ?? "")
                return VideoFolderCache.subtitleExtensions.contains(ext) && ext != "idx"
                    && (lowered.hasPrefix(base + ".") || PathMetadata.removingExtension(lowered) == base)
            }
            .sorted()
            .map { directory.appending(path: $0, directoryHint: .notDirectory) }
    }

    /// A frame of the video, for the artwork picker.
    public func frame(of video: Video, at time: TimeInterval?, maxPixelSize: Int = 1_280) async -> Data? {
        guard let frameSource, let file = video.file, let url = url(for: file) else { return nil }
        return await frameSource.frameJPEG(from: url, at: time, maxPixelSize: maxPixelSize, precise: true)
    }

    // MARK: - Edits and artwork

    public func apply(_ edit: VideoEdit, to video: Video) {
        let id = video.id
        Task {
            do {
                try await indexer().applyVideoEdit(edit, videoID: id)
                bumpRevision()
                enqueue(.lookUp)
            } catch {
                lastError = "Couldn\u{2019}t save your changes: \(error.localizedDescription)"
            }
        }
    }

    public func apply(_ edit: ShowEdit, to show: TVShow) {
        let id = show.id
        Task {
            do {
                try await indexer().applyShowEdit(edit, showID: id)
                bumpRevision()
            } catch {
                lastError = "Couldn\u{2019}t save your changes: \(error.localizedDescription)"
            }
        }
    }

    /// Uses an image the user chose as the video's artwork.
    @discardableResult
    public func setArtwork(imageData: Data, for video: Video) async -> Bool {
        guard let key = await storeImage(imageData) else { return false }
        do {
            try await indexer().setArtwork(videoID: video.id, key: key)
            bumpRevision()
            return true
        } catch {
            lastError = "Couldn\u{2019}t save the artwork: \(error.localizedDescription)"
            return false
        }
    }

    /// Uses a frame of the video as its artwork.
    @discardableResult
    public func setArtworkFromFrame(of video: Video, at time: TimeInterval) async -> Bool {
        guard let data = await frame(of: video, at: time, maxPixelSize: 1_920) else { return false }
        return await setArtwork(imageData: data, for: video)
    }

    public func resetArtwork(for video: Video) {
        let id = video.id
        Task {
            try? await indexer().setArtwork(videoID: id, key: nil)
            bumpRevision()
        }
    }

    @discardableResult
    public func setArtwork(imageData: Data, for show: TVShow) async -> Bool {
        guard let key = await storeImage(imageData) else { return false }
        do {
            try await indexer().setArtwork(showID: show.id, key: key)
            bumpRevision()
            return true
        } catch {
            lastError = "Couldn\u{2019}t save the artwork: \(error.localizedDescription)"
            return false
        }
    }

    public func resetArtwork(for show: TVShow) {
        let id = show.id
        Task {
            try? await indexer().setArtwork(showID: id, key: nil)
            bumpRevision()
        }
    }

    private func storeImage(_ data: Data) async -> String? {
        let store = artworkStore
        return await Task.detached(priority: .userInitiated) { store.store(data) }.value
    }

    /// What this folder's videos are; they're sorted again straight away.
    public func setVideoContent(_ content: VideoFolderContent, for source: Source) {
        let id = source.id
        Task {
            do {
                try await indexer().setVideoHint(sourceID: id, hint: content.hint)
                enqueue(.scan(id))
            } catch {
                lastError = "Couldn\u{2019}t change the folder: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - TMDB

    /// Checks and saves the user's TMDB key, then looks everything up.
    public func setMetadataKey(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeMetadataKey()
            return
        }
        do {
            try await TMDBClient(key: trimmed).validate()
            metadataProblem = nil
        } catch TMDBClient.Failure.invalidKey {
            throw TMDBClient.Failure.invalidKey
        } catch {
            // Offline: keep the key and try it later.
            metadataProblem = "Couldn\u{2019}t reach TMDB to check the key: \(error.localizedDescription)"
        }
        try MetadataKeyStore.save(trimmed)
        metadataKey = trimmed
        hasMetadataKey = true
        enqueue(.lookUp)
    }

    public func removeMetadataKey() {
        MetadataKeyStore.delete()
        metadataKey = nil
        hasMetadataKey = false
        metadataProblem = nil
    }

    /// Settings ▸ Metadata ▸ Look Up Again: everything that wasn't found.
    public func lookUpUnmatchedAgain() {
        Task {
            _ = try? await indexer().retryNotFound()
            enqueue(.lookUp)
        }
    }

    public func lookUpAgain(_ video: Video) {
        let id = video.id
        Task {
            try? await indexer().requestLookup(videoID: id)
            enqueue(.lookUp)
        }
    }

    public func lookUpAgain(_ show: TVShow) {
        let id = show.id
        Task {
            try? await indexer().requestLookup(showID: id)
            enqueue(.lookUp)
        }
    }

    // MARK: - Free sources

    /// Settings ▸ Metadata: look things up on TVmaze and Wikipedia when
    /// there's no TMDB key.
    public func setUsesFreeMetadataSources(_ uses: Bool) {
        usesFreeMetadataSources = uses
        UserDefaults.standard.set(uses, forKey: Self.freeSourcesKey)
        if uses, !hasMetadataKey {
            enqueue(.lookUp)
        }
    }

    /// Whether lookups (and Fix Match) can run at all.
    public var canLookUp: Bool {
        hasMetadataKey || usesFreeMetadataSources
    }

    /// Where Fix Match searches: "TMDB", "Wikipedia" or "TVmaze".
    public func lookupSourceName(forShows: Bool) -> String {
        if hasMetadataKey { return "TMDB" }
        return forShows ? "TVmaze" : "Wikipedia"
    }

    // MARK: - Fix Match

    public func searchMovies(_ title: String, year: Int?) async throws -> [LookupResult] {
        if let key = metadataKey {
            return try await TMDBClient(key: key).searchMovies(title: title, year: year).prefix(20).map { result in
                LookupResult(id: result.id, title: result.title, year: result.year, overview: result.overview, posterURL: TMDBClient.imageURL(result.posterPath, size: "w185"))
            }
        }
        guard usesFreeMetadataSources else { throw TMDBClient.Failure.invalidKey }
        let pages = try await WikipediaClient().searchFilms(title: title, year: year)
        return pages.filter(WikipediaFilms.isFilm).map { page in
            LookupResult(
                id: page.pageid,
                title: WikipediaFilms.parseTitle(page.title).title,
                year: WikipediaFilms.year(of: page),
                overview: WikipediaFilms.synopsis(page),
                posterURL: page.posterURL,
                source: .wikipedia
            )
        }
    }

    public func searchShows(_ title: String, year: Int?) async throws -> [LookupResult] {
        if let key = metadataKey {
            return try await TMDBClient(key: key).searchShows(title: title, year: year).prefix(20).map { result in
                LookupResult(id: result.id, title: result.name, year: result.year, overview: result.overview, posterURL: TMDBClient.imageURL(result.posterPath, size: "w185"))
            }
        }
        guard usesFreeMetadataSources else { throw TMDBClient.Failure.invalidKey }
        return try await TVmazeClient().searchShows(title: title).prefix(20).map { show in
            LookupResult(
                id: show.id,
                title: show.name,
                year: show.year,
                overview: show.plainSummary,
                posterURL: show.image?.medium.flatMap(URL.init(string:)),
                source: .tvmaze
            )
        }
    }

    public func fixMatch(_ video: Video, with result: LookupResult) async throws {
        switch result.source {
        case .tmdb:
            guard let key = metadataKey else { throw TMDBClient.Failure.invalidKey }
            try await indexer().fixMatch(videoID: video.id, tmdbID: result.id, client: TMDBClient(key: key), artworkStore: artworkStore)
        case .wikipedia:
            try await indexer().fixMatch(videoID: video.id, wikipediaPageID: result.id, wikipedia: WikipediaClient(), artworkStore: artworkStore)
        case .tvmaze:
            return
        }
        bumpRevision()
    }

    public func fixMatch(_ show: TVShow, with result: LookupResult) async throws {
        switch result.source {
        case .tmdb:
            guard let key = metadataKey else { throw TMDBClient.Failure.invalidKey }
            try await indexer().fixMatch(showID: show.id, tmdbID: result.id, client: TMDBClient(key: key), artworkStore: artworkStore)
        case .tvmaze:
            try await indexer().fixMatch(showID: show.id, tvmazeID: result.id, tvmaze: TVmazeClient(), artworkStore: artworkStore)
        case .wikipedia:
            return
        }
        bumpRevision()
    }
}
