import Foundation
import Testing
@testable import MetadataProviders

@Suite("TMDB")
struct TMDBTests {
    @Test func requestsUseTheRightCredential() throws {
        let v3 = TMDBClient(key: " 0123456789abcdef0123456789abcdef ", language: "en-GB", region: "GB")
        let keyed = v3.request("search/movie", query: [URLQueryItem(name: "query", value: "Heat")])
        let keyedURL = try #require(keyed.url?.absoluteString)
        #expect(keyedURL.hasPrefix("https://api.themoviedb.org/3/search/movie?"))
        #expect(keyedURL.contains("api_key=0123456789abcdef0123456789abcdef"))
        #expect(keyedURL.contains("language=en-GB"))
        #expect(keyed.value(forHTTPHeaderField: "Authorization") == nil)

        let token = String(repeating: "eyJhbGciOiJIUzI1NiJ9", count: 4)
        let v4 = TMDBClient(key: token)
        let bearer = v4.request("movie/949", query: [])
        #expect(bearer.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(bearer.url?.absoluteString.contains("api_key") == false)
    }

    @Test func imageURLs() {
        #expect(TMDBClient.imageURL("/abc.jpg", size: "w780")?.absoluteString == "https://image.tmdb.org/t/p/w780/abc.jpg")
        #expect(TMDBClient.imageURL(nil, size: "w780") == nil)
    }

    @Test func decodesMovieDetails() throws {
        let json = """
        {"id":949,"title":"Heat","original_title":"Heat","overview":"Obsessive master thief…","tagline":"A Los Angeles crime saga",
         "release_date":"1995-12-15","runtime":170,"genres":[{"id":28,"name":"Action"},{"id":80,"name":"Crime"}],
         "poster_path":"/poster.jpg","backdrop_path":"/backdrop.jpg","vote_average":7.9,"imdb_id":"tt0113277",
         "production_companies":[{"name":"Regency Enterprises"}],
         "credits":{"cast":[{"name":"Al Pacino","character":"Lt. Vincent Hanna","profile_path":"/pacino.jpg","order":0}],
                    "crew":[{"name":"Michael Mann","job":"Director"},{"name":"Dante Spinotti","job":"Director of Photography"}]},
         "release_dates":{"results":[{"iso_3166_1":"GB","release_dates":[{"certification":"15","type":3}]},
                                     {"iso_3166_1":"US","release_dates":[{"certification":"","type":4},{"certification":"R","type":3}]}]}}
        """
        let movie = try TMDBClient.decoder.decode(TMDBMovie.self, from: Data(json.utf8))
        #expect(movie.title == "Heat")
        #expect(movie.year == 1995)
        #expect(movie.runtime == 170)
        #expect(movie.genres?.map(\.name) == ["Action", "Crime"])
        #expect(movie.directors == ["Michael Mann"])
        #expect(movie.credits?.cast?.first?.character == "Lt. Vincent Hanna")
        #expect(movie.certification(region: "GB") == "15")
        #expect(movie.certification(region: "FR") == "R")
        #expect(movie.imdbId == "tt0113277")
    }

    @Test func decodesShowsAndSeasons() throws {
        let show = try TMDBClient.decoder.decode(TMDBShow.self, from: Data("""
        {"id":1396,"name":"Breaking Bad","first_air_date":"2008-01-20","episode_run_time":[45,47],"networks":[{"name":"AMC"}],
         "seasons":[{"season_number":0,"name":"Specials"},{"season_number":1,"name":"Season 1","poster_path":"/s1.jpg","episode_count":7}],
         "content_ratings":{"results":[{"iso_3166_1":"US","rating":"TV-MA"}]}}
        """.utf8))
        #expect(show.year == 2008)
        #expect(show.seasons?.count == 2)
        #expect(show.certification(region: "DE") == "TV-MA")
        #expect(show.networks?.first?.name == "AMC")

        let season = try TMDBClient.decoder.decode(TMDBSeason.self, from: Data("""
        {"season_number":1,"episodes":[{"id":62085,"episode_number":1,"season_number":1,"name":"Pilot","air_date":"2008-01-20","runtime":58,"still_path":"/pilot.jpg"}]}
        """.utf8))
        #expect(season.episodes?.first?.name == "Pilot")
        #expect(season.episodes?.first?.stillPath == "/pilot.jpg")
    }

    @Test func matchesTheRightMovie() {
        let results = [
            TMDBMovieResult(id: 1, title: "Heat", releaseDate: "1986-03-14", voteCount: 60),
            TMDBMovieResult(id: 949, title: "Heat", releaseDate: "1995-12-15", voteCount: 7_000),
            TMDBMovieResult(id: 3, title: "The Heat", releaseDate: "2013-06-27", voteCount: 4_000),
        ]
        #expect(TMDBMatching.bestMovie(results, title: "Heat", year: 1995)?.id == 949)
        #expect(TMDBMatching.bestMovie(results, title: "Heat", year: 1986)?.id == 1)
        // No year: the most popular exact title wins.
        #expect(TMDBMatching.bestMovie(results, title: "Heat", year: nil)?.id == 949)
        // A year nothing matches: no match rather than a wrong one.
        #expect(TMDBMatching.bestMovie(results, title: "Heat", year: 2005) == nil)
        // A different film altogether.
        #expect(TMDBMatching.bestMovie(results, title: "Heathers", year: nil) == nil)
    }

    @Test func toleratesSmallDifferences() {
        let results = [TMDBMovieResult(id: 194, title: "Amélie", originalTitle: "Le Fabuleux Destin d'Amélie Poulain", releaseDate: "2001-04-25")]
        #expect(TMDBMatching.bestMovie(results, title: "Amelie", year: 2001)?.id == 194)
        #expect(TMDBMatching.bestMovie(results, title: "Le Fabuleux Destin d Amelie Poulain", year: 2001)?.id == 194)
        let shows = [TMDBShowResult(id: 1668, name: "Friends", firstAirDate: "1994-09-22")]
        #expect(TMDBMatching.bestShow(shows, title: "friends", year: nil)?.id == 1668)
        #expect(TMDBMatching.similarity("Law & Order", "Law and Order") == 1)
        #expect(TMDBMatching.similarity("The Office", "Office") == 1)
    }
}
