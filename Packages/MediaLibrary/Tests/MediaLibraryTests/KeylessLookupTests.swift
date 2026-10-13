import CoreGraphics
import Foundation
import ImageIO
import MetadataProviders
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import MediaLibrary

extension LibraryTests {
    /// Looking videos up without a TMDB key, against canned TVmaze, Wikipedia
    /// and Wikidata responses (no network).
    @Suite("Lookups without a key", .serialized)
    struct KeylessLookupTests {
        @Test func moviesComeFromWikipediaAndShowsFromTVmaze() async throws {
            let harness = try LookupHarness()
            defer { harness.cleanUp() }
            try harness.write("Heat (1995).mkv")
            try harness.write("Breaking Bad/Season 1/Breaking.Bad.S01E01.mkv")
            try harness.write("Breaking Bad/Season 1/Breaking.Bad.S01E02.mkv")
            try await harness.scan()

            let session = StubURLProtocol.session(routes: Self.routes())
            let settled = try await harness.indexer.lookUpPendingWithoutKey(
                tvmaze: TVmazeClient(session: session),
                wikipedia: WikipediaClient(session: session),
                artworkStore: harness.store
            )
            #expect(settled >= 2)

            let videos = try harness.fetch(Video.self)
            let movie = try #require(videos.first { $0.kind == .movie })
            #expect(movie.matchState == .keyless)
            #expect(movie.title == "Heat")
            #expect(movie.year == 1995)
            #expect(movie.overview?.hasPrefix("Heat is a 1995 American crime film") == true)
            #expect(movie.imdbID == "tt0113277")
            #expect(movie.tmdbID == nil)
            #expect(movie.posterKey != nil)

            let show = try #require(try harness.fetch(TVShow.self).first)
            #expect(show.matchState == .keyless)
            #expect(show.title == "Breaking Bad")
            #expect(show.network == "AMC")
            #expect(show.overview == "Breaking Bad follows Walter White & his partner.")
            #expect(show.posterKey != nil)
            #expect(show.backdropKey != nil)
            #expect(show.cast.first?.name == "Bryan Cranston")

            let episodes = videos.filter { $0.kind == .episode }.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
            #expect(episodes.count == 2)
            #expect(episodes[0].title == "Pilot")
            #expect(episodes[0].overview == "Walt begins.")
            #expect(episodes[0].stillKey != nil)
            #expect(episodes[0].matchState == .keyless)
            #expect(episodes[1].title == "Cat's in the Bag...")
            #expect(episodes[1].stillKey == nil)
        }

        @Test func localArtworkWinsAndUnknownTitlesAreNotFound() async throws {
            let harness = try LookupHarness()
            defer { harness.cleanUp() }
            try harness.write("Heat (1995).mkv")
            try harness.write("Heat (1995)-poster.png", LookupHarness.png())
            try harness.write("Some Film Nobody Knows (2003).mkv")
            try await harness.scan()

            let before = try #require(try harness.fetch(Video.self).first { $0.title == "Heat" })
            let localPoster = try #require(before.posterKey)
            #expect(before.localFields.contains(VideoField.artwork.rawValue))

            let session = StubURLProtocol.session(routes: Self.routes())
            _ = try await harness.indexer.lookUpPendingWithoutKey(
                tvmaze: TVmazeClient(session: session),
                wikipedia: WikipediaClient(session: session),
                artworkStore: harness.store
            )

            let videos = try harness.fetch(Video.self)
            let heat = try #require(videos.first { $0.title == "Heat" })
            #expect(heat.matchState == .keyless)
            #expect(heat.posterKey == localPoster)
            let unknown = try #require(videos.first { $0.title.hasPrefix("Some Film") })
            #expect(unknown.matchState == .notFound)
        }

        // MARK: Canned responses

        static func routes() -> @Sendable (URL) -> (Int, Data) {
            let image = (try? LookupHarness.png()) ?? Data()
            return { url in
                let host = url.host() ?? ""
                let path = url.path()
                let query = url.query(percentEncoded: false) ?? ""
                switch host {
                case "en.wikipedia.org" where query.contains("gsrsearch=Heat"):
                    return (200, Data(wikipediaHeat.utf8))
                case "en.wikipedia.org":
                    return (200, Data(#"{"batchcomplete": true}"#.utf8))
                case "www.wikidata.org":
                    return (200, Data(#"{"claims": {"P345": [{"mainsnak": {"datavalue": {"value": "tt0113277", "type": "string"}}}]}}"#.utf8))
                case "api.tvmaze.com" where path == "/search/shows":
                    return (200, Data(tvmazeSearch.utf8))
                case "api.tvmaze.com" where path == "/shows/169/images":
                    return (200, Data(#"[{"id": 9, "type": "background", "main": true, "resolutions": {"original": {"url": "https://static.tvmaze.com/bg.png"}}}]"#.utf8))
                case "api.tvmaze.com" where path == "/shows/169":
                    return (200, Data(tvmazeShow.utf8))
                case "upload.wikimedia.org", "static.tvmaze.com":
                    return (200, image)
                default:
                    return (404, Data())
                }
            }
        }

        static let wikipediaHeat = """
        {"batchcomplete": true, "query": {"pages": [
          {"pageid": 1, "ns": 0, "title": "Heat (1995 film)", "index": 1, "description": "1995 film by Michael Mann",
           "original": {"source": "https://upload.wikimedia.org/Heat.png", "width": 220, "height": 326},
           "pageprops": {"wikibase_item": "Q472512"},
           "extract": "Heat is a 1995 American crime film written and directed by Michael Mann."},
          {"pageid": 2, "ns": 0, "title": "Heat (soundtrack)", "index": 2, "description": "1995 soundtrack album"}
        ]}}
        """

        static let tvmazeSearch = """
        [{"score": 0.9, "show": {"id": 169, "name": "Breaking Bad", "premiered": "2008-01-20", "weight": 98}}]
        """

        static let tvmazeShow = """
        {"id": 169, "name": "Breaking Bad", "premiered": "2008-01-20", "genres": ["Drama", "Crime"],
         "rating": {"average": 9.2}, "network": {"id": 20, "name": "AMC"},
         "image": {"medium": "https://static.tvmaze.com/m.png", "original": "https://static.tvmaze.com/o.png"},
         "summary": "<p><b>Breaking Bad</b> follows Walter White &amp; his partner.</p>",
         "_embedded": {
           "episodes": [
             {"id": 1, "name": "Pilot", "season": 1, "number": 1, "airdate": "2008-01-20", "runtime": 58,
              "image": {"medium": "https://static.tvmaze.com/e1m.png", "original": "https://static.tvmaze.com/e1.png"}, "summary": "<p>Walt begins.</p>"},
             {"id": 2, "name": "Cat's in the Bag...", "season": 1, "number": 2, "airdate": "2008-01-27", "runtime": 48, "image": null, "summary": null},
             {"id": 3, "name": "Seven Thirty-Seven", "season": 2, "number": 1, "airdate": "2009-03-08"}
           ],
           "seasons": [{"id": 1, "number": 1, "name": "", "premiereDate": "2008-01-20", "image": {"original": "https://static.tvmaze.com/s1.png"}}],
           "cast": [{"person": {"name": "Bryan Cranston", "image": {"medium": "https://static.tvmaze.com/bc.png"}}, "character": {"name": "Walter White"}}]
         }}
        """
    }
}

/// A library in memory over a temporary folder of fake video files.
private struct LookupHarness {
    let container: ModelContainer
    let indexer: LibraryIndexer
    let root: URL
    let sourceID: UUID
    let store: ArtworkStore

    init() throws {
        container = try LibraryStore.makeContainer(inMemory: true)
        indexer = LibraryIndexer(modelContainer: container)
        root = FileManager.default.temporaryDirectory.appending(path: "coreplay-keyless-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ArtworkStore(directory: FileManager.default.temporaryDirectory.appending(path: "coreplay-keyless-art-\(UUID().uuidString)", directoryHint: .isDirectory))
        let context = ModelContext(container)
        let source = Source(name: "Videos", kind: .folder, path: root.path(percentEncoded: false))
        context.insert(source)
        try context.save()
        sourceID = source.id
    }

    func write(_ path: String, _ data: Data = Data(repeating: 7, count: 2_048)) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func scan() async throws {
        _ = try await indexer.scan(sourceID: sourceID, root: root, isSingleFile: false, artworkStore: store) { _ in }
    }

    func fetch<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try ModelContext(container).fetch(FetchDescriptor<Model>())
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: store.directory)
    }

    static func png() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return output as Data
    }
}

/// Answers every request from a routing closure instead of the network.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var route: (@Sendable (URL) -> (Int, Data))?

    static func session(routes: @escaping @Sendable (URL) -> (Int, Data)) -> URLSession {
        lock.withLock { route = routes }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let route = Self.lock.withLock { Self.route }
        let (status, data) = route?(url) ?? (404, Data())
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
