import Foundation
import Testing
@testable import MetadataProviders

@Suite("LRCLIB")
struct LRCLIBTests {
    @Test func asksByTitleArtistAlbumAndLength() throws {
        let request = LRCLIBClient.request(title: "Song 1", artist: "The Harbour Lights", album: "Night Swimming", duration: 213.6)
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/api/get")
        #expect(items.first { $0.name == "track_name" }?.value == "Song 1")
        #expect(items.first { $0.name == "artist_name" }?.value == "The Harbour Lights")
        #expect(items.first { $0.name == "album_name" }?.value == "Night Swimming")
        #expect(items.first { $0.name == "duration" }?.value == "214")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Coreplay") == true)
        let bare = LRCLIBClient.request(title: "x", artist: "y", album: nil, duration: nil)
        #expect(bare.url?.query?.contains("album_name") == false)
    }

    @Test func prefersSyncedWords() throws {
        let both = try LRCLIBClient.decode(Data(#"{"id":1,"syncedLyrics":"[00:01.00]Hi","plainLyrics":"Hi","instrumental":false}"#.utf8))
        #expect(both.bestText == "[00:01.00]Hi")
        let plain = try LRCLIBClient.decode(Data(#"{"syncedLyrics":null,"plainLyrics":"Hello"}"#.utf8))
        #expect(plain.bestText == "Hello")
        let none = try LRCLIBClient.decode(Data(#"{"syncedLyrics":"  ","plainLyrics":null,"instrumental":true}"#.utf8))
        #expect(none.bestText == nil)
        #expect(throws: LRCLIBClient.Failure.self) { try LRCLIBClient.decode(Data("<html>".utf8)) }
    }
}
