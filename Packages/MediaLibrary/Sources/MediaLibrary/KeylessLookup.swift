import Foundation
import MetadataProviders
import SwiftData

// Lookups without a TMDB key: TVmaze for shows and their episodes, Wikipedia
// (with Wikidata for the IMDb ID) for movies. They run like TMDB's: read what
// needs looking up, do the network work off the actor, apply the results to
// whatever still exists. Matches are marked `.keyless`, so a TMDB key added
// later replaces them with TMDB's fuller details and larger artwork.

enum KeylessFetcher {
    // MARK: Movies

    static func movie(_ query: LookupQuery, wikipedia: WikipediaClient, store: ArtworkStore) async throws -> MovieDetails? {
        var pages = try await wikipedia.searchFilms(title: query.title, year: query.year)
        var page = WikipediaFilms.best(pages, title: query.title, year: query.year)
        if page == nil, query.year != nil {
            // Search engines weigh the year heavily; try the title alone too.
            pages = try await wikipedia.searchFilms(title: query.title, year: nil)
            page = WikipediaFilms.best(pages, title: query.title, year: query.year)
        }
        guard let page else { return nil }
        return await details(page, wikipedia: wikipedia, store: store)
    }

    static func details(_ page: WikipediaPage, wikipedia: WikipediaClient, store: ArtworkStore) async -> MovieDetails {
        async let poster = download(page.posterURL, store: store) { try await wikipedia.image($0) }
        var imdbID: String?
        if let item = page.pageprops?.wikibaseItem {
            imdbID = try? await wikipedia.imdbID(wikidataID: item)
        }
        return MovieDetails(
            tmdbID: nil,
            imdbID: imdbID,
            title: WikipediaFilms.parseTitle(page.title).title,
            originalTitle: nil,
            year: WikipediaFilms.year(of: page),
            releaseDate: nil,
            overview: WikipediaFilms.synopsis(page),
            tagline: nil,
            runtime: nil,
            genres: [],
            contentRating: nil,
            rating: nil,
            cast: [],
            directors: [],
            studio: nil,
            posterKey: await poster,
            backdropKey: nil
        )
    }

    // MARK: Shows

    static func show(_ query: LookupQuery, tvmaze: TVmazeClient, store: ArtworkStore) async throws -> ShowDetails? {
        var match: TVmazeShow?
        if let imdbID = query.imdbID {
            match = try await tvmaze.show(imdbID: imdbID)
        }
        if match == nil {
            let results = try await tvmaze.searchShows(title: query.title)
            match = TVmazeMatching.bestShow(results, title: query.title, year: query.year)
        }
        guard let match else { return nil }
        return try await show(id: match.id, seasons: query.seasons, tvmaze: tvmaze, store: store)
    }

    /// A show by its TVmaze ID, with the given seasons' episodes (every
    /// episode of a season when its set is empty).
    static func show(id: Int, seasons wanted: [Int: Set<Int>], tvmaze: TVmazeClient, store: ArtworkStore) async throws -> ShowDetails? {
        guard let full = try await tvmaze.showDetails(id: id) else { return nil }
        let images = (try? await tvmaze.images(showID: id)) ?? []
        async let poster = download(full.show.image?.best, store: store) { try await tvmaze.image($0) }
        async let backdrop = download(TVmazeImage.background(in: images), store: store) { try await tvmaze.image($0) }

        var seasons: [Int: SeasonDetails] = [:]
        for (number, episodeNumbers) in wanted.sorted(by: { $0.key < $1.key }) {
            let info = full.seasons.first { $0.number == number }
            var episodes: [Int: EpisodeDetails] = [:]
            for episode in full.episodes where episode.season == number {
                guard let episodeNumber = episode.number,
                      episodeNumbers.isEmpty || episodeNumbers.contains(episodeNumber) else { continue }
                let still = await download(episode.image?.best, store: store) { try await tvmaze.image($0) }
                episodes[episodeNumber] = EpisodeDetails(
                    tmdbID: nil,
                    title: episode.name.flatMap { $0.isEmpty ? nil : $0 },
                    overview: HTMLText.plain(episode.summary),
                    airDate: episode.airdate.flatMap { $0.isEmpty ? nil : $0 },
                    runtime: episode.runtime.flatMap { $0 > 0 ? Double($0 * 60) : nil },
                    stillKey: still
                )
            }
            guard info != nil || !episodes.isEmpty else { continue }
            let seasonPoster = await download(info?.image?.best, store: store) { try await tvmaze.image($0) }
            seasons[number] = SeasonDetails(
                number: number,
                title: info?.name.flatMap { $0.isEmpty ? nil : $0 },
                overview: HTMLText.plain(info?.summary),
                year: info?.premiereDate.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil },
                posterKey: seasonPoster,
                episodes: episodes
            )
        }

        return ShowDetails(
            tmdbID: nil,
            title: full.show.name,
            year: full.show.year,
            overview: full.show.plainSummary,
            genres: full.show.genres ?? [],
            contentRating: nil,
            network: full.show.network?.name ?? full.show.webChannel?.name,
            rating: full.show.rating?.average,
            cast: full.cast.prefix(20).map {
                CastMember(name: $0.person.name, role: $0.character?.name, imageURL: $0.person.image?.medium.flatMap(URL.init(string:)))
            },
            posterKey: await poster,
            backdropKey: await backdrop,
            seasons: seasons
        )
    }

    /// Downloads and stores an image; `nil` if there's none or it fails.
    static func download(_ url: URL?, store: ArtworkStore, using fetch: @Sendable (URL) async throws -> Data) async -> String? {
        guard let url, let data = try? await fetch(url), !data.isEmpty else { return nil }
        return await Task.detached(priority: .utility) { store.store(data) }.value
    }
}

extension LibraryIndexer {
    /// Without a TMDB key: looks up a batch of waiting movies (Wikipedia) and
    /// shows (TVmaze), and episodes added to shows already found. Returns how
    /// many items it settled (0 when nothing is waiting). Throws when the
    /// sources can't be reached; waiting items stay waiting.
    public func lookUpPendingWithoutKey(tvmaze: TVmazeClient, wikipedia: WikipediaClient, artworkStore: ArtworkStore, batchSize: Int = 6) async throws -> Int {
        let pending = MatchState.pending.rawValue
        let movieKind = VideoKind.movie.rawValue
        let episodeKind = VideoKind.episode.rawValue

        var movieDescriptor = FetchDescriptor<Video>(predicate: #Predicate<Video> { video in
            video.matchStateRaw == pending && video.kindRaw == movieKind
        })
        movieDescriptor.fetchLimit = batchSize
        let movieQueries = try modelContext.fetch(movieDescriptor).map {
            LookupQuery(id: $0.id, title: $0.title.isEmpty ? $0.displayTitle : $0.title, year: $0.year, tmdbID: $0.tmdbID, imdbID: $0.imdbID)
        }

        var showDescriptor = FetchDescriptor<TVShow>(predicate: #Predicate<TVShow> { show in show.matchStateRaw == pending })
        showDescriptor.fetchLimit = max(2, batchSize / 2)
        let showQueries = try modelContext.fetch(showDescriptor).map { show in
            LookupQuery(id: show.id, title: show.title, year: show.year, tmdbID: show.tmdbID, imdbID: show.imdbID, seasons: Self.seasonMap(show.episodes))
        }

        // Episodes waiting in shows that are already settled: fetch their shows again.
        var episodeDescriptor = FetchDescriptor<Video>(predicate: #Predicate<Video> { video in
            video.matchStateRaw == pending && video.kindRaw == episodeKind
        })
        episodeDescriptor.fetchLimit = 60
        var episodeShows: [UUID: LookupQuery] = [:]
        var settled = 0
        for episode in try modelContext.fetch(episodeDescriptor) {
            guard let show = episode.show else { continue }
            switch show.matchState {
            case .matched, .manual, .keyless:
                guard let season = episode.seasonNumber, let number = episode.episodeNumber else {
                    episode.matchState = .notFound
                    settled += 1
                    continue
                }
                var query = episodeShows[show.id] ?? LookupQuery(id: show.id, title: show.title, year: show.year, imdbID: show.imdbID)
                query.seasons[season, default: []].insert(number)
                episodeShows[show.id] = query
            case .notFound, .local:
                episode.matchState = show.matchState
                settled += 1
            case .pending:
                break // looked up with its show
            }
        }
        if settled > 0 {
            try modelContext.save()
        }
        guard !movieQueries.isEmpty || !showQueries.isEmpty || !episodeShows.isEmpty else { return settled }

        // Network: one at a time, as both services ask.
        var movieResults: [(UUID, MovieDetails?)] = []
        for query in movieQueries {
            movieResults.append((query.id, try await KeylessFetcher.movie(query, wikipedia: wikipedia, store: artworkStore)))
        }
        var showResults: [(UUID, ShowDetails?)] = []
        for query in showQueries {
            showResults.append((query.id, try await KeylessFetcher.show(query, tvmaze: tvmaze, store: artworkStore)))
        }
        var episodeResults: [(UUID, ShowDetails?)] = []
        for query in episodeShows.values {
            episodeResults.append((query.id, try await KeylessFetcher.show(query, tvmaze: tvmaze, store: artworkStore)))
        }

        // Apply to whatever still exists.
        for (id, details) in movieResults {
            guard let video = try video(id: id) else { continue }
            if let details {
                Self.apply(details, to: video, state: .keyless)
            } else {
                video.matchState = .notFound
            }
            video.lastMatchAttempt = .now
            settled += 1
        }
        for (id, details) in showResults {
            guard let show = try show(id: id) else { continue }
            if let details {
                Self.apply(details, to: show, state: .keyless, context: modelContext)
            } else {
                show.matchState = .notFound
                for episode in show.episodes where episode.matchState == .pending {
                    episode.matchState = .notFound
                }
            }
            show.lastMatchAttempt = .now
            settled += 1
        }
        for (id, details) in episodeResults {
            guard let show = try show(id: id) else { continue }
            let seasons = details.map { Array($0.seasons.values) } ?? []
            for season in seasons {
                settled += Self.apply(season, toEpisodesOf: show, context: modelContext, state: .keyless)
            }
            // Episodes the listing doesn't have keep their names; don't ask again.
            for episode in show.episodes where episode.matchState == .pending {
                episode.matchState = .notFound
                settled += 1
            }
        }
        try modelContext.save()
        return max(settled, 1)
    }

    /// Fix Match without a key, for a movie: the user picked a Wikipedia article.
    public func fixMatch(videoID: UUID, wikipediaPageID: Int, wikipedia: WikipediaClient, artworkStore: ArtworkStore) async throws {
        guard let page = try await wikipedia.page(id: wikipediaPageID) else {
            throw WikipediaClient.Failure.unreadableResponse
        }
        let details = await KeylessFetcher.details(page, wikipedia: wikipedia, store: artworkStore)
        guard let video = try video(id: videoID) else { return }
        if video.kind != .movie {
            video.kind = .movie
            video.editedFields = Array(Set(video.editedFields).union([VideoField.kind.rawValue])).sorted()
            VideoGrouper(context: modelContext).detach(video)
        }
        video.localFields = []
        video.tmdbID = nil
        Self.apply(details, to: video, state: .manual)
        video.lastMatchAttempt = .now
        try modelContext.save()
        try VideoGrouper(context: modelContext).removeOrphans()
    }

    /// Fix Match without a key, for a show: the user picked a TVmaze show.
    public func fixMatch(showID: UUID, tvmazeID: Int, tvmaze: TVmazeClient, artworkStore: ArtworkStore) async throws {
        guard let current = try show(id: showID) else { return }
        let seasons = Self.seasonMap(current.episodes)
        guard let details = try await KeylessFetcher.show(id: tvmazeID, seasons: seasons, tvmaze: tvmaze, store: artworkStore) else {
            throw TVmazeClient.Failure.unreadableResponse
        }
        guard let show = try show(id: showID) else { return }
        show.localFields = []
        show.tmdbID = nil
        Self.apply(details, to: show, state: .manual, context: modelContext)
        show.lastMatchAttempt = .now
        try modelContext.save()
    }
}
