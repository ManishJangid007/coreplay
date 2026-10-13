import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MetadataProviders

// Responses below follow the shapes documented by TVmaze
// (https://www.tvmaze.com/api) and the MediaWiki query API (formatversion=2).

@Suite("TVmaze")
struct TVmazeTests {
    @Test func decodesSearchResults() throws {
        let json = """
        [
          {"score": 0.91, "show": {"id": 169, "url": "https://www.tvmaze.com/shows/169/breaking-bad", "name": "Breaking Bad",
            "language": "English", "genres": ["Drama", "Crime", "Thriller"], "premiered": "2008-01-20", "runtime": 60,
            "rating": {"average": 9.2}, "weight": 98, "network": {"id": 20, "name": "AMC"}, "webChannel": null,
            "externals": {"tvrage": 18164, "thetvdb": 81189, "imdb": "tt0903747"},
            "image": {"medium": "https://static.tvmaze.com/m.jpg", "original": "https://static.tvmaze.com/o.jpg"},
            "summary": "<p><b>Breaking Bad</b> follows protagonist Walter White &amp; his partner.</p>"}},
          {"score": 0.4, "show": {"id": 9999, "name": "Breaking Bad: Original Minisodes", "premiered": "2009-02-17", "weight": 20}}
        ]
        """
        let results = try JSONDecoder().decode([TVmazeSearchResult].self, from: Data(json.utf8))
        #expect(results.count == 2)
        let show = results[0].show
        #expect(show.name == "Breaking Bad")
        #expect(show.year == 2008)
        #expect(show.network?.name == "AMC")
        #expect(show.externals?.imdb == "tt0903747")
        #expect(show.image?.best == URL(string: "https://static.tvmaze.com/o.jpg"))
        #expect(show.plainSummary == "Breaking Bad follows protagonist Walter White & his partner.")
        #expect(results[1].show.network == nil)
    }

    @Test func decodesShowWithEpisodesSeasonsAndCast() throws {
        let json = """
        {"id": 169, "name": "Breaking Bad", "premiered": "2008-01-20", "genres": ["Drama"],
         "image": {"medium": "m.jpg", "original": "o.jpg"}, "summary": "<p>Chemistry.</p>",
         "_embedded": {
           "episodes": [
             {"id": 12192, "name": "Pilot", "season": 1, "number": 1, "airdate": "2008-01-20", "runtime": 60,
              "image": {"medium": "e1m.jpg", "original": "e1o.jpg"}, "summary": "<p>Walt begins.</p>"},
             {"id": 12193, "name": "Cat's in the Bag...", "season": 1, "number": 2, "airdate": "2008-01-27", "runtime": 60, "image": null, "summary": null},
             {"id": 99999, "name": "Special", "season": 2, "number": null, "airdate": "2009-02-01"}
           ],
           "seasons": [
             {"id": 1, "number": 1, "name": "", "premiereDate": "2008-01-20", "image": {"medium": "s1m.jpg", "original": "s1o.jpg"}, "summary": null}
           ],
           "cast": [
             {"person": {"id": 1, "name": "Bryan Cranston", "image": {"medium": "bc.jpg", "original": "bco.jpg"}}, "character": {"id": 1, "name": "Walter White"}}
           ]
         }}
        """
        let details = try JSONDecoder().decode(TVmazeShowDetails.self, from: Data(json.utf8))
        #expect(details.show.name == "Breaking Bad")
        #expect(details.episodes.count == 3)
        #expect(details.episodes[0].image?.best?.absoluteString == "e1o.jpg")
        #expect(details.episodes[1].image == nil)
        #expect(details.episodes[2].number == nil)
        #expect(details.seasons.first?.image?.original == "s1o.jpg")
        #expect(details.cast.first?.person.name == "Bryan Cranston")
        #expect(details.cast.first?.character?.name == "Walter White")
    }

    @Test func picksTheBackground() throws {
        let json = """
        [{"id": 1, "type": "poster", "main": true, "resolutions": {"original": {"url": "p.jpg", "width": 680, "height": 1000}}},
         {"id": 2, "type": "background", "main": false, "resolutions": {"original": {"url": "b2.jpg"}}},
         {"id": 3, "type": "background", "main": true, "resolutions": {"original": {"url": "b3.jpg", "width": 1920, "height": 1080}}}]
        """
        let images = try JSONDecoder().decode([TVmazeImage].self, from: Data(json.utf8))
        #expect(TVmazeImage.background(in: images)?.absoluteString == "b3.jpg")
        #expect(TVmazeImage.background(in: Array(images.prefix(2)))?.absoluteString == "b2.jpg")
        #expect(TVmazeImage.background(in: Array(images.prefix(1))) == nil)
    }

    @Test func matchesByTitleAndYear() {
        let shows = [
            TVmazeShow(id: 1, name: "The Office", premiered: "2005-03-24", weight: 99),
            TVmazeShow(id: 2, name: "The Office", premiered: "2001-07-09", weight: 90),
            TVmazeShow(id: 3, name: "Office Ladies", premiered: "2019-10-16", weight: 60),
        ]
        #expect(TVmazeMatching.bestShow(shows, title: "The Office", year: 2001)?.id == 2)
        #expect(TVmazeMatching.bestShow(shows, title: "The Office", year: nil)?.id == 1)
        #expect(TVmazeMatching.bestShow(shows, title: "Something Else", year: nil) == nil)
    }

    @Test func stripsHTML() {
        #expect(HTMLText.plain("<p>One &amp; two</p><p>Three<br>four</p>") == "One & two\n\nThree four")
        #expect(HTMLText.plain("<p><i>Quoted</i> &quot;text&quot; it&#39;s</p>") == "Quoted \"text\" it\u{2019}s")
        #expect(HTMLText.plain("") == nil)
        #expect(HTMLText.plain(nil) == nil)
        #expect(HTMLText.plain("<p></p>") == nil)
    }

    @Test func buildsRequests() {
        let request = TVmazeClient().request("search/shows", query: [URLQueryItem(name: "q", value: "Doctor Who")])
        #expect(request.url?.host() == "api.tvmaze.com")
        #expect(request.url?.path() == "/search/shows")
        #expect(request.url?.query()?.contains("q=Doctor%20Who") == true)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Coreplay") == true)
    }
}

@Suite("Wikipedia")
struct WikipediaTests {
    @Test func decodesSearchPages() throws {
        let json = """
        {"batchcomplete": true, "continue": {"gsroffset": 8, "continue": "gsroffset||"},
         "query": {"pages": [
           {"pageid": 2, "ns": 0, "title": "Heat (soundtrack)", "index": 2, "description": "1995 soundtrack album"},
           {"pageid": 1, "ns": 0, "title": "Heat (1995 film)", "index": 1, "description": "1995 film by Michael Mann",
            "descriptionsource": "local",
            "thumbnail": {"source": "https://upload.wikimedia.org/thumb/Heat.jpg", "width": 220, "height": 326},
            "original": {"source": "https://upload.wikimedia.org/Heat.jpg", "width": 220, "height": 326},
            "pageprops": {"wikibase_item": "Q472512"},
            "extract": "Heat is a 1995 American crime film written and directed by Michael Mann."}
         ]}}
        """
        let response = try JSONDecoder().decode(WikipediaQueryResponse.self, from: Data(json.utf8))
        let pages = response.query?.pages ?? []
        #expect(pages.count == 2)
        let heat = try #require(pages.first { $0.pageid == 1 })
        #expect(heat.pageprops?.wikibaseItem == "Q472512")
        #expect(heat.posterURL?.absoluteString == "https://upload.wikimedia.org/Heat.jpg")
        #expect(WikipediaFilms.best(pages, title: "Heat", year: 1995)?.pageid == 1)
        #expect(heat.url?.absoluteString == "https://en.wikipedia.org/wiki/Heat_(1995_film)")
    }

    @Test func parsesTitles() {
        let heat = WikipediaFilms.parseTitle("Heat (1995 film)")
        #expect(heat.title == "Heat")
        #expect(heat.year == 1995)
        #expect(heat.saysFilm)
        let plain = WikipediaFilms.parseTitle("Blade Runner 2049")
        #expect(plain.title == "Blade Runner 2049")
        #expect(plain.year == nil)
        #expect(!plain.saysFilm)
        #expect(WikipediaFilms.parseTitle("Crash (2004 film)").year == 2004)
        #expect(WikipediaFilms.parseTitle("Mercury (planet)").saysFilm == false)
    }

    @Test func recognisesFilms() {
        let film = WikipediaPage(pageid: 1, title: "Inception", description: "2010 film by Christopher Nolan")
        let series = WikipediaPage(pageid: 2, title: "Star Wars", description: "American epic space opera film series")
        let person = WikipediaPage(pageid: 3, title: "Christopher Nolan", description: "British-American film director (born 1970)")
        let book = WikipediaPage(pageid: 4, title: "Dune (novel)", description: "1965 science fiction novel by Frank Herbert")
        let undescribed = WikipediaPage(pageid: 5, title: "Primer", extract: "Primer is a 2004 American science fiction film written by Shane Carruth.")
        let disambiguation = WikipediaPage(pageid: 6, title: "Heat", description: "Topics referred to by the same term", pageprops: .init(disambiguation: ""))
        #expect(WikipediaFilms.isFilm(film))
        #expect(!WikipediaFilms.isFilm(series))
        #expect(!WikipediaFilms.isFilm(person))
        #expect(!WikipediaFilms.isFilm(book))
        #expect(WikipediaFilms.isFilm(undescribed))
        #expect(!WikipediaFilms.isFilm(disambiguation))
    }

    @Test func readsYears() {
        #expect(WikipediaFilms.year(of: WikipediaPage(pageid: 1, title: "Heat (1995 film)")) == 1995)
        #expect(WikipediaFilms.year(of: WikipediaPage(pageid: 1, title: "Inception", description: "2010 film by Christopher Nolan")) == 2010)
        #expect(WikipediaFilms.year(of: WikipediaPage(pageid: 1, title: "Primer", extract: "Primer is a 2004 American science fiction film.")) == 2004)
        #expect(WikipediaFilms.year(of: WikipediaPage(pageid: 1, title: "Untitled")) == nil)
    }

    @Test func matchesOnlyCloseTitlesAndYears() {
        let pages = [
            WikipediaPage(pageid: 10, title: "The Thing (1982 film)", index: 1, description: "1982 film by John Carpenter"),
            WikipediaPage(pageid: 11, title: "The Thing (2011 film)", index: 2, description: "2011 film by Matthijs van Heijningen Jr."),
            WikipediaPage(pageid: 12, title: "The Thing from Another World", index: 3, description: "1951 film by Christian Nyby"),
        ]
        #expect(WikipediaFilms.best(pages, title: "The Thing", year: 2011)?.pageid == 11)
        #expect(WikipediaFilms.best(pages, title: "The Thing", year: 1982)?.pageid == 10)
        #expect(WikipediaFilms.best(pages, title: "The Thing", year: 1999) == nil)
        #expect(WikipediaFilms.best(pages, title: "Totally Different", year: nil) == nil)
    }

    @Test func cleansSynopses() {
        let page = WikipediaPage(pageid: 1, title: "Amélie", extract: "Amélie (French: Le Fabuleux Destin d'Amélie Poulain; pronounced [ameli]) is a 2001 romantic comedy film. ")
        #expect(WikipediaFilms.synopsis(page) == "Amélie is a 2001 romantic comedy film.")
        #expect(WikipediaFilms.synopsis(WikipediaPage(pageid: 2, title: "Empty", extract: " ")) == nil)
    }

    @Test func decodesWikidataClaims() throws {
        let json = """
        {"claims": {"P345": [
          {"mainsnak": {"snaktype": "value", "property": "P345", "datavalue": {"value": "tt0113277", "type": "string"}}, "type": "statement", "rank": "normal"}
        ]}}
        """
        let response = try JSONDecoder().decode(WikidataClaimsResponse.self, from: Data(json.utf8))
        #expect(response.claims["P345"]?.first?.mainsnak.datavalue?.value == "tt0113277")

        let odd = """
        {"claims": {"P345": [{"mainsnak": {"snaktype": "somevalue"}}, {"mainsnak": {"datavalue": {"value": {"amount": "+1"}, "type": "quantity"}}}]}}
        """
        let oddResponse = try JSONDecoder().decode(WikidataClaimsResponse.self, from: Data(odd.utf8))
        #expect(oddResponse.claims["P345"]?.compactMap(\.mainsnak.datavalue?.value).isEmpty == true)
    }

    @Test func buildsRequests() {
        let request = WikipediaClient().request(WikipediaClient.apiURL, query: WikipediaClient.pageQuery + [URLQueryItem(name: "gsrsearch", value: "Heat 1995 film")])
        let query = request.url?.query() ?? ""
        #expect(request.url?.host() == "en.wikipedia.org")
        #expect(query.contains("pilicense=any"))
        #expect(query.contains("formatversion=2"))
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Coreplay") == true)
    }
}
