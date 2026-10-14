import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MetadataProviders

// Shapes follow OpenSubtitles' REST API documentation
// (https://opensubtitles.stoplight.io/docs/opensubtitles-api).

@Suite("OpenSubtitles")
struct OpenSubtitlesTests {
    @Test func fileHash() throws {
        // Size plus the little-endian words of the first and last 64 KB.
        var head = Data(repeating: 0, count: 65_536)
        head[0] = 1
        var tail = Data(repeating: 0, count: 65_536)
        tail[8] = 0x10
        #expect(OpenSubtitlesClient.hash(size: 0x20000, head: head, tail: tail) == "0000000000020011")
        // Wraps around rather than overflowing.
        let full = Data(repeating: 0xFF, count: 16)
        #expect(OpenSubtitlesClient.hash(size: 2, head: full, tail: Data()) == "0000000000000000")

        let url = FileManager.default.temporaryDirectory.appending(path: "coreplay-hash-\(UUID().uuidString).bin")
        try Data(repeating: 0, count: 200_000).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try OpenSubtitlesClient.hash(ofFileAt: url) == String(format: "%016llx", UInt64(200_000)))
    }

    @Test func searchParametersAreSortedAndLowerCase() {
        let query = OpenSubtitlesClient.Query(movieHash: "8E245D9679D31E12", title: "Breaking Bad", parentIMDbID: "tt0903747", season: 1, episode: 2, languages: ["fr", "EN"])
        let names = query.queryItems.map(\.name)
        #expect(names == ["episode_number", "languages", "moviehash", "parent_imdb_id", "query", "season_number"])
        let values = Dictionary(uniqueKeysWithValues: query.queryItems.map { ($0.name, $0.value ?? "") })
        #expect(values["parent_imdb_id"] == "903747")
        #expect(OpenSubtitlesClient.Query(imdbID: "tt0113277").queryItems.first?.value == "113277")
        #expect(values["languages"] == "en,fr")
        #expect(values["moviehash"] == "8e245d9679d31e12")
        #expect(values["query"] == "breaking bad")
    }

    @Test func requestsCarryTheKeyAndToken() {
        let client = OpenSubtitlesClient(apiKey: "key-123")
        let request = client.request(url: OpenSubtitlesClient.baseURL.appending(path: "download"), method: "POST", token: "tok", body: Data("{}".utf8))
        #expect(request.value(forHTTPHeaderField: "Api-Key") == "key-123")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == OpenSubtitlesClient.userAgent)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.absoluteString == "https://api.opensubtitles.com/api/v1/download")
    }

    @Test func resultsPutExactMatchesFirst() throws {
        let json = """
        {"total_pages": 1, "total_count": 3, "page": 1, "data": [
          {"id": "1", "type": "subtitle", "attributes": {"language": "en", "download_count": 9000, "hearing_impaired": false,
            "machine_translated": false, "ai_translated": false, "from_trusted": true, "moviehash_match": false,
            "release": "Heat.1995.REMASTERED.1080p.BluRay", "files": [{"file_id": 11, "cd_number": 1, "file_name": "Heat.en.srt"}]}},
          {"id": "2", "type": "subtitle", "attributes": {"language": "en", "download_count": 12, "hearing_impaired": true,
            "from_trusted": false, "moviehash_match": true, "release": "Heat.1995.1080p.WEB",
            "files": [{"file_id": 22, "file_name": "Heat.sdh.srt"}]}},
          {"id": "3", "type": "subtitle", "attributes": {"language": "en", "download_count": 99999, "machine_translated": true,
            "release": "Heat", "files": [{"file_id": 33}]}}
        ]}
        """
        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
        let subtitles = OpenSubtitlesClient.subtitles(from: response)
        #expect(subtitles.map(\.id) == [22, 11, 33])
        #expect(subtitles[0].matchesFile)
        #expect(subtitles[0].isHearingImpaired)
        #expect(subtitles[1].release == "Heat.1995.REMASTERED.1080p.BluRay")
        #expect(subtitles[2].isMachineTranslated)
        #expect(subtitles[2].release == "Heat")
    }

    @Test func failures() throws {
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: OpenSubtitlesClient.baseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
        #expect(throws: OpenSubtitlesClient.Failure.notAuthorized) {
            try OpenSubtitlesClient.check(response(401), data: Data())
        }
        #expect(throws: OpenSubtitlesClient.Failure.quotaExceeded(resetTime: "23 hours and 59 minutes")) {
            try OpenSubtitlesClient.check(response(406), data: Data(#"{"requests": 6, "remaining": -1, "reset_time": "23 hours and 59 minutes"}"#.utf8))
        }
        #expect(throws: OpenSubtitlesClient.Failure.rateLimited) {
            try OpenSubtitlesClient.check(response(429), data: Data())
        }
        try OpenSubtitlesClient.check(response(200), data: Data())
    }
}
