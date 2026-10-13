import Foundation
import MetadataProviders
import SwiftData

// TMDB lookups for movies and shows, run on the indexer's context.
//
// Each batch reads what needs looking up, does every network request and
// image download off the actor, then applies the results to fresh copies of
// the models (anything deleted meanwhile is skipped). Edited and `.nfo`
// fields are never replaced.

/// Sizes TMDB serves that match what Coreplay shows.
enum TMDBImageSize {
    static let poster = "w780"
    static let backdrop = "w1280"
    static let still = "w780"
    static let profile = "w185"
}

/// Details for a movie, ready to apply.
struct MovieDetails: Sendable {
    /// `nil` when the details came from the free sources.
    var tmdbID: Int?
    var imdbID: String?
    var title: String
    var originalTitle: String?
    var year: Int?
    var releaseDate: String?
    var overview: String?
    var tagline: String?
    var runtime: Double?
    var genres: [String]
    var contentRating: String?
    var rating: Double?
    var cast: [CastMember]
    var directors: [String]
    var studio: String?
    var posterKey: String?
    var backdropKey: String?
}

struct EpisodeDetails: Sendable {
    var tmdbID: Int?
    var title: String?
    var overview: String?
    var airDate: String?
    var runtime: Double?
    var stillKey: String?
}

struct SeasonDetails: Sendable {
    var number: Int
    var title: String?
    var overview: String?
    var year: Int?
    var posterKey: String?
    var episodes: [Int: EpisodeDetails]
}

struct ShowDetails: Sendable {
    /// `nil` when the details came from the free sources.
    var tmdbID: Int?
    var title: String
    var year: Int?
    var overview: String?
    var genres: [String]
    var contentRating: String?
    var network: String?
    var rating: Double?
    var cast: [CastMember]
    var posterKey: String?
    var backdropKey: String?
    var seasons: [Int: SeasonDetails]
}

/// A title to look up, copied out of the model.
struct LookupQuery: Sendable {
    var id: UUID
    var title: String
    var year: Int?
    var tmdbID: Int?
    var imdbID: String?
    /// Shows: the season numbers present, with their episode numbers.
    var seasons: [Int: Set<Int>] = [:]
}

/// What a TMDB search offers in Fix Match.
public struct LookupResult: Identifiable, Sendable, Hashable {
    /// Where a result came from; its `id` belongs to that source.
    public enum Source: String, Sendable, Hashable {
        case tmdb
        case wikipedia
        case tvmaze

        public var name: String {
            switch self {
            case .tmdb: "TMDB"
            case .wikipedia: "Wikipedia"
            case .tvmaze: "TVmaze"
            }
        }
    }

    public var id: Int
    public var title: String
    public var year: Int?
    public var overview: String?
    public var posterURL: URL?
    public var source: Source = .tmdb
}

enum LookupFetcher {
    // MARK: Movies

    static func movie(_ query: LookupQuery, client: TMDBClient, store: ArtworkStore) async throws -> MovieDetails? {
        var tmdbID = query.tmdbID
        if tmdbID == nil, let imdbID = query.imdbID {
            tmdbID = try await client.find(imdbID: imdbID).movieResults.first?.id
        }
        if tmdbID == nil {
            var results = try await client.searchMovies(title: query.title, year: query.year)
            if results.isEmpty, query.year != nil {
                // Years in names are sometimes the DVD's, not the film's.
                results = try await client.searchMovies(title: query.title, year: nil)
            }
            tmdbID = TMDBMatching.bestMovie(results, title: query.title, year: query.year)?.id
        }
        guard let tmdbID else { return nil }
        let movie: TMDBMovie
        do {
            movie = try await client.movie(id: tmdbID)
        } catch TMDBClient.Failure.notFound {
            return nil
        }
        return await details(movie, client: client, store: store)
    }

    static func details(_ movie: TMDBMovie, client: TMDBClient, store: ArtworkStore) async -> MovieDetails {
        async let poster = image(movie.posterPath, size: TMDBImageSize.poster, client: client, store: store)
        async let backdrop = image(movie.backdropPath, size: TMDBImageSize.backdrop, client: client, store: store)
        return MovieDetails(
            tmdbID: movie.id,
            imdbID: movie.imdbId,
            title: movie.title,
            originalTitle: movie.originalTitle == movie.title ? nil : movie.originalTitle,
            year: movie.year,
            releaseDate: movie.releaseDate.flatMap { $0.isEmpty ? nil : $0 },
            overview: movie.overview.flatMap { $0.isEmpty ? nil : $0 },
            tagline: movie.tagline.flatMap { $0.isEmpty ? nil : $0 },
            runtime: movie.runtime.flatMap { $0 > 0 ? Double($0 * 60) : nil },
            genres: movie.genres?.map(\.name) ?? [],
            contentRating: movie.certification(region: client.region),
            rating: movie.voteAverage.flatMap { $0 > 0 ? $0 : nil },
            cast: cast(movie.credits),
            directors: movie.directors,
            studio: movie.productionCompanies?.first?.name,
            posterKey: await poster,
            backdropKey: await backdrop
        )
    }

    // MARK: Shows

    static func show(_ query: LookupQuery, client: TMDBClient, store: ArtworkStore) async throws -> ShowDetails? {
        var tmdbID = query.tmdbID
        if tmdbID == nil, let imdbID = query.imdbID {
            tmdbID = try await client.find(imdbID: imdbID).tvResults.first?.id
        }
        if tmdbID == nil {
            var results = try await client.searchShows(title: query.title, year: query.year)
            if results.isEmpty, query.year != nil {
                results = try await client.searchShows(title: query.title, year: nil)
            }
            tmdbID = TMDBMatching.bestShow(results, title: query.title, year: query.year)?.id
        }
        guard let tmdbID else { return nil }
        let show: TMDBShow
        do {
            show = try await client.show(id: tmdbID)
        } catch TMDBClient.Failure.notFound {
            return nil
        }
        async let poster = image(show.posterPath, size: TMDBImageSize.poster, client: client, store: store)
        async let backdrop = image(show.backdropPath, size: TMDBImageSize.backdrop, client: client, store: store)
        var seasons: [Int: SeasonDetails] = [:]
        for (number, episodes) in query.seasons.sorted(by: { $0.key < $1.key }) {
            if let details = try await season(showID: tmdbID, number: number, episodes: episodes, client: client, store: store) {
                seasons[number] = details
            }
        }
        return ShowDetails(
            tmdbID: show.id,
            title: show.name,
            year: show.year,
            overview: show.overview.flatMap { $0.isEmpty ? nil : $0 },
            genres: show.genres?.map(\.name) ?? [],
            contentRating: show.certification(region: client.region),
            network: show.networks?.first?.name,
            rating: show.voteAverage.flatMap { $0 > 0 ? $0 : nil },
            cast: cast(show.credits),
            posterKey: await poster,
            backdropKey: await backdrop,
            seasons: seasons
        )
    }

    /// A season's episodes, with stills downloaded for the ones in the library.
    static func season(showID: Int, number: Int, episodes wanted: Set<Int>, client: TMDBClient, store: ArtworkStore) async throws -> SeasonDetails? {
        let season: TMDBSeason
        do {
            season = try await client.season(showID: showID, number: number)
        } catch TMDBClient.Failure.notFound {
            return nil
        }
        let poster = await image(season.posterPath, size: TMDBImageSize.poster, client: client, store: store)
        var episodes: [Int: EpisodeDetails] = [:]
        for episode in season.episodes ?? [] where wanted.isEmpty || wanted.contains(episode.episodeNumber) {
            let still = await image(episode.stillPath, size: TMDBImageSize.still, client: client, store: store)
            episodes[episode.episodeNumber] = EpisodeDetails(
                tmdbID: episode.id,
                title: episode.name.flatMap { $0.isEmpty ? nil : $0 },
                overview: episode.overview.flatMap { $0.isEmpty ? nil : $0 },
                airDate: episode.airDate.flatMap { $0.isEmpty ? nil : $0 },
                runtime: episode.runtime.flatMap { $0 > 0 ? Double($0 * 60) : nil },
                stillKey: still
            )
        }
        return SeasonDetails(
            number: number,
            title: season.name.flatMap { $0.isEmpty ? nil : $0 },
            overview: season.overview.flatMap { $0.isEmpty ? nil : $0 },
            year: season.airDate.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil },
            posterKey: poster,
            episodes: episodes
        )
    }

    // MARK: Helpers

    static func cast(_ credits: TMDBCredits?) -> [CastMember] {
        (credits?.cast ?? [])
            .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
            .prefix(20)
            .map { CastMember(name: $0.name, role: $0.character.flatMap { $0.isEmpty ? nil : $0 }, imageURL: TMDBClient.imageURL($0.profilePath, size: TMDBImageSize.profile)) }
    }

    /// Downloads and stores an image; `nil` if there's none or it fails
    /// (artwork is never worth failing a lookup for).
    static func image(_ path: String?, size: String, client: TMDBClient, store: ArtworkStore) async -> String? {
        guard let path, !path.isEmpty, let data = try? await client.image(path: path, size: size) else { return nil }
        return await Task.detached(priority: .utility) { store.store(data) }.value
    }
}

extension LibraryIndexer {
    /// Looks up a batch of movies and shows that are waiting, and episodes
    /// added to shows that were already matched. Returns how many items it
    /// settled (0 when nothing is waiting). Throws when TMDB can't be used
    /// right now (bad key, offline, rate limited); waiting items stay waiting.
    public func lookUpPending(client: TMDBClient, artworkStore: ArtworkStore, batchSize: Int = 8) async throws -> Int {
        let pending = MatchState.pending.rawValue
        // Matches from the free sources are looked up again: TMDB has more.
        let keyless = MatchState.keyless.rawValue
        let movieKind = VideoKind.movie.rawValue
        let episodeKind = VideoKind.episode.rawValue

        var movieDescriptor = FetchDescriptor<Video>(predicate: #Predicate<Video> { video in
            (video.matchStateRaw == pending || video.matchStateRaw == keyless) && video.kindRaw == movieKind
        })
        movieDescriptor.fetchLimit = batchSize
        let movieQueries = try modelContext.fetch(movieDescriptor).map {
            LookupQuery(id: $0.id, title: $0.title.isEmpty ? $0.displayTitle : $0.title, year: $0.year, tmdbID: $0.tmdbID, imdbID: $0.imdbID)
        }

        var showDescriptor = FetchDescriptor<TVShow>(predicate: #Predicate<TVShow> { show in
            show.matchStateRaw == pending || show.matchStateRaw == keyless
        })
        showDescriptor.fetchLimit = max(2, batchSize / 2)
        let showQueries = try modelContext.fetch(showDescriptor).map { show in
            LookupQuery(id: show.id, title: show.title, year: show.year, tmdbID: show.tmdbID, imdbID: show.imdbID, seasons: Self.seasonMap(show.episodes))
        }

        // Episodes waiting in shows that are already settled.
        var episodeDescriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.matchStateRaw == pending && $0.kindRaw == episodeKind })
        episodeDescriptor.fetchLimit = 60
        var episodeQueries: [Int: [Int: Set<Int>]] = [:] // show TMDB ID → season → episodes
        var settled = 0
        for episode in try modelContext.fetch(episodeDescriptor) {
            guard let show = episode.show else { continue }
            switch show.matchState {
            case .matched, .manual:
                if let showID = show.tmdbID, let season = episode.seasonNumber, let number = episode.episodeNumber {
                    episodeQueries[showID, default: [:]][season, default: []].insert(number)
                } else {
                    episode.matchState = .notFound
                    settled += 1
                }
            case .notFound, .local:
                episode.matchState = show.matchState
                settled += 1
            case .pending, .keyless:
                break // looked up with its show
            }
        }
        if settled > 0 {
            try modelContext.save()
        }
        guard !movieQueries.isEmpty || !showQueries.isEmpty || !episodeQueries.isEmpty else { return settled }

        // Network, a few at a time.
        var movieResults: [(UUID, MovieDetails?)] = []
        for chunk in movieQueries.chunked(4) {
            try await withThrowingTaskGroup(of: (UUID, MovieDetails?).self) { group in
                for query in chunk {
                    group.addTask { (query.id, try await LookupFetcher.movie(query, client: client, store: artworkStore)) }
                }
                for try await result in group {
                    movieResults.append(result)
                }
            }
        }
        var showResults: [(UUID, ShowDetails?)] = []
        for query in showQueries {
            showResults.append((query.id, try await LookupFetcher.show(query, client: client, store: artworkStore)))
        }
        var seasonResults: [(Int, SeasonDetails)] = []
        for (showID, seasons) in episodeQueries {
            for (number, episodes) in seasons {
                if let details = try await LookupFetcher.season(showID: showID, number: number, episodes: episodes, client: client, store: artworkStore) {
                    seasonResults.append((showID, details))
                }
            }
        }

        // Apply to whatever still exists.
        for (id, details) in movieResults {
            guard let video = try video(id: id) else { continue }
            if let details {
                Self.apply(details, to: video, state: .matched)
            } else {
                video.matchState = .notFound
            }
            video.lastMatchAttempt = .now
            settled += 1
        }
        for (id, details) in showResults {
            guard let show = try show(id: id) else { continue }
            if let details {
                Self.apply(details, to: show, state: .matched, context: modelContext)
            } else {
                show.matchState = .notFound
                for episode in show.episodes where episode.matchState == .pending {
                    episode.matchState = .notFound
                }
            }
            show.lastMatchAttempt = .now
            settled += 1
        }
        for (showID, season) in seasonResults {
            let target: Int? = showID
            var descriptor = FetchDescriptor<TVShow>(predicate: #Predicate { $0.tmdbID == target })
            descriptor.fetchLimit = 4
            for show in try modelContext.fetch(descriptor) {
                settled += Self.apply(season, toEpisodesOf: show, context: modelContext)
            }
        }
        // Episodes TMDB doesn't list keep their names; don't ask again.
        for (showID, seasons) in episodeQueries {
            let target: Int? = showID
            var descriptor = FetchDescriptor<TVShow>(predicate: #Predicate { $0.tmdbID == target })
            descriptor.fetchLimit = 4
            for show in try modelContext.fetch(descriptor) {
                for episode in show.episodes where episode.matchState == .pending && seasons[episode.seasonNumber ?? -1] != nil {
                    episode.matchState = .notFound
                    settled += 1
                }
            }
        }
        try modelContext.save()
        return max(settled, 1)
    }

    /// Fix Match for a movie: the user picked `tmdbID`.
    public func fixMatch(videoID: UUID, tmdbID: Int, client: TMDBClient, artworkStore: ArtworkStore) async throws {
        let movie = try await client.movie(id: tmdbID)
        let details = await LookupFetcher.details(movie, client: client, store: artworkStore)
        guard let video = try video(id: videoID) else { return }
        if video.kind != .movie {
            video.kind = .movie
            video.editedFields = Array(Set(video.editedFields).union([VideoField.kind.rawValue])).sorted()
            VideoGrouper(context: modelContext).detach(video)
        }
        // A manual match replaces names and lookups, but not the user's edits.
        video.localFields = []
        Self.apply(details, to: video, state: .manual)
        video.lastMatchAttempt = .now
        try modelContext.save()
        try VideoGrouper(context: modelContext).removeOrphans()
    }

    /// Fix Match for a show: the user picked `tmdbID`.
    public func fixMatch(showID: UUID, tmdbID: Int, client: TMDBClient, artworkStore: ArtworkStore) async throws {
        guard let current = try show(id: showID) else { return }
        let query = LookupQuery(id: showID, title: current.title, year: current.year, tmdbID: tmdbID, seasons: Self.seasonMap(current.episodes))
        guard let details = try await LookupFetcher.show(query, client: client, store: artworkStore) else {
            throw TMDBClient.Failure.notFound
        }
        guard let show = try show(id: showID) else { return }
        show.localFields = []
        Self.apply(details, to: show, state: .manual, context: modelContext)
        show.lastMatchAttempt = .now
        try modelContext.save()
    }

    /// "Look Up Again" for everything TMDB couldn't find.
    public func retryNotFound() throws -> Int {
        let notFound = MatchState.notFound.rawValue
        let pending = MatchState.pending.rawValue
        var count = 0
        for video in try modelContext.fetch(FetchDescriptor<Video>(predicate: #Predicate { $0.matchStateRaw == notFound })) {
            video.matchStateRaw = pending
            count += 1
        }
        for show in try modelContext.fetch(FetchDescriptor<TVShow>(predicate: #Predicate { $0.matchStateRaw == notFound })) {
            show.matchStateRaw = pending
            count += 1
        }
        try modelContext.save()
        return count
    }

    // MARK: - Applying

    static func seasonMap(_ episodes: [Video]) -> [Int: Set<Int>] {
        var map: [Int: Set<Int>] = [:]
        for episode in episodes {
            guard let season = episode.seasonNumber else { continue }
            var numbers = map[season, default: []]
            if let number = episode.episodeNumber {
                numbers.insert(number)
                if let last = episode.lastEpisodeNumber, last > number, last - number < 10 {
                    numbers.formUnion(number...last)
                }
            }
            map[season] = numbers
        }
        return map
    }

    static func apply(_ details: MovieDetails, to video: Video, state: MatchState) {
        let edited = Set(video.editedFields)
        let local = state == .manual ? Set<String>() : Set(video.localFields)
        func free(_ field: VideoField) -> Bool { !edited.contains(field.rawValue) && !local.contains(field.rawValue) }
        // TMDB's artwork replaces the free sources' small posters, but never local files.
        let replacesArtwork = state == .manual
            || (video.matchState == .keyless && state != .keyless && !video.localFields.contains(VideoField.artwork.rawValue))

        video.matchState = state
        video.tmdbID = details.tmdbID ?? video.tmdbID
        video.imdbID = details.imdbID ?? video.imdbID
        if free(.title) {
            video.title = details.title
            video.sortTitle = NameNormalizer.sortKey(details.title)
        }
        if free(.year), let year = details.year { video.year = year }
        if free(.releaseDate), let date = details.releaseDate { video.releaseDate = date }
        if free(.overview), let overview = details.overview { video.overview = overview }
        if free(.genres), !details.genres.isEmpty { video.genres = details.genres }
        if free(.contentRating), let rating = details.contentRating { video.contentRating = rating }
        if free(.runtime), let runtime = details.runtime { video.runtime = runtime }
        if free(.cast), !details.cast.isEmpty { video.cast = details.cast }
        video.originalTitle = details.originalTitle ?? video.originalTitle
        video.tagline = details.tagline ?? video.tagline
        video.rating = details.rating ?? video.rating
        if !details.directors.isEmpty { video.directors = details.directors }
        video.studio = details.studio ?? video.studio
        if let key = details.posterKey, video.posterKey == nil || replacesArtwork { video.posterKey = key }
        if let key = details.backdropKey, video.backdropKey == nil || replacesArtwork { video.backdropKey = key }
    }

    static func apply(_ details: ShowDetails, to show: TVShow, state: MatchState, context: ModelContext) {
        let edited = Set(show.editedFields)
        let local = state == .manual ? Set<String>() : Set(show.localFields)
        func free(_ field: VideoField) -> Bool { !edited.contains(field.rawValue) && !local.contains(field.rawValue) }
        let replacesArtwork = state == .manual
            || (show.matchState == .keyless && state != .keyless && !show.localFields.contains(VideoField.artwork.rawValue))

        show.matchState = state
        show.tmdbID = details.tmdbID ?? show.tmdbID
        if free(.title) {
            show.title = details.title
            show.sortTitle = NameNormalizer.sortKey(details.title)
        }
        if free(.year), let year = details.year { show.year = year }
        if free(.overview), let overview = details.overview { show.overview = overview }
        if free(.genres), !details.genres.isEmpty { show.genres = details.genres }
        if free(.cast), !details.cast.isEmpty { show.cast = details.cast }
        show.contentRating = details.contentRating ?? show.contentRating
        show.network = details.network ?? show.network
        show.rating = details.rating ?? show.rating
        if let key = details.posterKey, show.posterKey == nil || replacesArtwork { show.posterKey = key }
        if let key = details.backdropKey, show.backdropKey == nil || replacesArtwork { show.backdropKey = key }
        for episode in show.episodes where episode.showTitle != show.title {
            episode.showTitle = show.title
        }
        for season in details.seasons.values {
            _ = apply(season, toEpisodesOf: show, context: context, state: state, replacesArtwork: replacesArtwork)
        }
        for episode in show.episodes where episode.matchState == .pending {
            // Not in TMDB's listing (or numbered differently): names stay.
            episode.matchState = .notFound
        }
    }

    /// Season details onto the show's season and its episodes; returns how many episodes it settled.
    @discardableResult
    static func apply(_ details: SeasonDetails, toEpisodesOf show: TVShow, context: ModelContext, state: MatchState = .matched, replacesArtwork: Bool = false) -> Int {
        let replaces = replacesArtwork || state == .manual
        if let season = show.seasons.first(where: { $0.number == details.number }) {
            if let title = details.title { season.title = title }
            season.overview = details.overview ?? season.overview
            season.year = details.year ?? season.year
            if let key = details.posterKey, season.posterKey == nil || replaces { season.posterKey = key }
        }
        var settled = 0
        for episode in show.episodes where episode.seasonNumber == details.number {
            guard let number = episode.episodeNumber, let info = details.episodes[number] else { continue }
            let edited = Set(episode.editedFields)
            let local = state == .manual ? Set<String>() : Set(episode.localFields)
            func free(_ field: VideoField) -> Bool { !edited.contains(field.rawValue) && !local.contains(field.rawValue) }
            if free(.title), var title = info.title {
                // Two episodes in one file: "Part One & Part Two".
                if let last = episode.lastEpisodeNumber, last > number, let second = details.episodes[last]?.title, second != title {
                    title += " & " + second
                }
                episode.title = title
                episode.sortTitle = NameNormalizer.sortKey(title)
            }
            if free(.overview), let overview = info.overview { episode.overview = overview }
            if free(.releaseDate), let date = info.airDate {
                episode.releaseDate = date
                episode.year = Int(date.prefix(4))
            }
            if free(.runtime), let runtime = info.runtime { episode.runtime = runtime }
            if let key = info.stillKey, episode.stillKey == nil || (replaces && !episode.localFields.contains(VideoField.artwork.rawValue)) {
                episode.stillKey = key
            }
            episode.tmdbID = info.tmdbID ?? episode.tmdbID
            episode.matchState = state
            episode.lastMatchAttempt = .now
            settled += 1
        }
        return settled
    }

    // MARK: - Lookups by ID

    func video(id: UUID) throws -> Video? {
        var descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func show(id: UUID) throws -> TVShow? {
        var descriptor = FetchDescriptor<TVShow>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: Swift.max(size, 1)).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
