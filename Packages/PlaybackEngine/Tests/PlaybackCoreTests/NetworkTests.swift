import Foundation
import Testing
@testable import PlaybackCore

@Suite("Network shares")
struct NetworkShareTests {
    @Test func buildsShareURLsWithoutLogins() throws {
        let url = try #require(NetworkAddress.url(protocol: .smb, host: "nas.local", path: "Movies/Films 2024"))
        #expect(url.absoluteString == "smb://nas.local/Movies/Films%202024/")
        // The default port is left out, any other kept.
        #expect(NetworkAddress.url(protocol: .ftp, host: "files.example.com", port: 21)?.absoluteString == "ftp://files.example.com/")
        #expect(NetworkAddress.url(protocol: .sftp, host: "10.0.0.2", port: 2222, path: "/home/me")?.absoluteString == "sftp://10.0.0.2:2222/home/me/")
        #expect(NetworkAddress.url(protocol: .nfs, host: "fe80::1")?.absoluteString == "nfs://[fe80::1]/")
        #expect(NetworkAddress.url(protocol: .smb, host: " ") == nil)
        #expect(NetworkAddress.url(protocol: .smb, host: "my nas") == nil)
    }

    @Test func readsTypedAddresses() throws {
        let typed = try #require(NetworkAddress.parse("smb://bob@nas.local/Movies", defaultProtocol: .ftp))
        #expect(typed.networkProtocol == .smb)
        #expect(typed.host == "nas.local")
        #expect(typed.user == "bob")
        #expect(typed.path == "/Movies")
        #expect(typed.url?.absoluteString == "smb://nas.local/Movies/")

        let bare = try #require(NetworkAddress.parse("192.168.1.5", defaultProtocol: .sftp))
        #expect(bare.networkProtocol == .sftp)
        #expect(bare.host == "192.168.1.5")
        #expect(bare.path == "")
        #expect(bare.user == nil)

        let windows = try #require(NetworkAddress.parse(#"\\SERVER\Share\Films"#, defaultProtocol: .nfs))
        #expect(windows.networkProtocol == .smb)
        #expect(windows.host == "SERVER")
        #expect(windows.path == "/Share/Films")

        let ipv6 = try #require(NetworkAddress.parse("ftp://[fe80::1]:2121/pub", defaultProtocol: .smb))
        #expect(ipv6.host == "fe80::1")
        #expect(ipv6.port == 2121)
        #expect(ipv6.url?.absoluteString == "ftp://[fe80::1]:2121/pub/")

        #expect(NetworkAddress.parse("http://example.com", defaultProtocol: .smb) == nil)
        #expect(NetworkAddress.parse("   ", defaultProtocol: .smb) == nil)
    }

    @Test func stripsLoginsAndNamesPlaces() throws {
        let url = try #require(URL(string: "smb://bob:secret@nas.local:4455/Movies/Heat.mkv"))
        #expect(NetworkAddress.withoutLogin(url).absoluteString == "smb://nas.local:4455/Movies/Heat.mkv")
        #expect(NetworkAddress.server(of: url) == "nas.local:4455")
        #expect(NetworkAddress.name(of: url) == "Heat.mkv")
        #expect(NetworkAddress.displayPath(url) == "nas.local:4455 \u{203A} Movies \u{203A} Heat.mkv")
        let top = try #require(URL(string: "smb://nas.local/"))
        #expect(NetworkAddress.name(of: top) == "nas.local")
        #expect(NetworkAddress.isShare(top))
        #expect(!NetworkAddress.isShare(URL(string: "https://example.com/a.mp4")!))
        let child = NetworkAddress.child(named: "Season 1", of: top, isFolder: true)
        #expect(child.absoluteString == "smb://nas.local/Season%201/")
    }

    @Test func credentialsBecomeVLCOptions() throws {
        let credential = NetworkCredential(user: "bob", password: "p@ss word", domain: " WORKGROUP ")
        #expect(credential.domain == "WORKGROUP")
        #expect(credential.vlcOptions(for: URL(string: "smb://nas/")!) == [":smb-user=bob", ":smb-pwd=p@ss word", ":smb-domain=WORKGROUP"])
        #expect(credential.vlcOptions(for: URL(string: "ftp://host/")!) == [":ftp-user=bob", ":ftp-pwd=p@ss word"])
        #expect(credential.vlcOptions(for: URL(string: "sftp://host/")!) == [":sftp-user=bob", ":sftp-pwd=p@ss word"])
        #expect(credential.vlcOptions(for: URL(string: "nfs://host/")!).isEmpty)
        #expect(NetworkCredential(user: "a", password: "b", domain: "").domain == nil)
    }

    @Test func entriesAreClassifiedAndSorted() {
        let folder = URL(string: "smb://nas/TV/")!
        func entry(_ name: String, folder isFolder: Bool = false) -> NetworkEntry {
            NetworkEntry(name: name, url: NetworkAddress.child(named: name, of: folder, isFolder: isFolder), isFolder: isFolder, size: 10)
        }
        let entries = [
            entry("Episode 10.mkv"), entry("Episode 2.mkv"), entry("Episode 2.en.srt"), entry("Specials", folder: true),
            entry("theme.flac"), entry("cover.jpg"), entry("list.m3u"), entry("live.m3u8"), entry("notes.txt"),
        ]
        #expect(NetworkEntry.sorted(entries).map(\.name) == [
            "Specials", "cover.jpg", "Episode 2.en.srt", "Episode 2.mkv", "Episode 10.mkv", "list.m3u", "live.m3u8", "notes.txt", "theme.flac",
        ])
        let kinds = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.kind) })
        #expect(kinds["Episode 2.mkv"] == .video)
        #expect(kinds["theme.flac"] == .audio)
        #expect(kinds["Episode 2.en.srt"] == .subtitle)
        #expect(kinds["Specials"] == .folder)
        #expect(kinds["cover.jpg"] == .image)
        #expect(kinds["list.m3u"] == .playlist)
        #expect(kinds["live.m3u8"] == .video)
        #expect(kinds["notes.txt"] == .other)
        #expect(entries.first { $0.isFolder }?.size == nil)
        // Subtitles go with the video of the same name.
        let video = entries[1]
        #expect(NetworkEntry.subtitles(for: video, in: entries).map(\.lastPathComponent) == ["Episode 2.en.srt"])
        #expect(NetworkEntry.subtitles(for: entries[0], in: entries).isEmpty)
        #expect(NetworkEntry.isHidden(name: ".DS_Store"))
        #expect(NetworkEntry.isHidden(name: "@eaDir"))
        #expect(NetworkEntry.isHidden(name: "$recycle.bin"))
        #expect(!NetworkEntry.isHidden(name: "Movies"))
    }

    @Test func itemsCarryTheirCredentialSeparately() {
        var item = PlaybackItem(url: URL(string: "smb://nas.local/Movies/Heat.mkv")!)
        #expect(item.title == "Heat")
        #expect(item.kind == .video)
        #expect(item.credential == nil)
        item.credential = NetworkCredential(user: "bob", password: "x")
        #expect(!item.url.absoluteString.contains("bob"))
        // Shares go to VLC: AVFoundation can't open them.
        let decision = EngineRouter().quickDecision(for: item)
        #expect(decision?.engine == .vlc)
    }
}

@Suite("Network streams")
struct NetworkStreamTests {
    @Test func readsPastedAddresses() {
        #expect(StreamAddress.url(from: " https://example.com/live/index.m3u8 ")?.absoluteString == "https://example.com/live/index.m3u8")
        #expect(StreamAddress.url(from: "example.com/live.m3u8")?.absoluteString == "http://example.com/live.m3u8")
        #expect(StreamAddress.url(from: "localhost:8080/stream")?.absoluteString == "http://localhost:8080/stream")
        #expect(StreamAddress.url(from: "<rtsp://cam.local:554/h264>")?.absoluteString == "rtsp://cam.local:554/h264")
        #expect(StreamAddress.url(from: "udp://@239.0.0.1:1234")?.absoluteString == "udp://@239.0.0.1:1234")
        #expect(StreamAddress.url(from: "rtmp://live.example.com/app/key")?.scheme == "rtmp")
        #expect(StreamAddress.url(from: "http://example.com/a file.mp4")?.absoluteString == "http://example.com/a%20file.mp4")
        #expect(StreamAddress.url(from: "") == nil)
        #expect(StreamAddress.url(from: "hello") == nil)
        #expect(StreamAddress.url(from: "/Users/me/Movies/a.mkv") == nil)
        #expect(StreamAddress.url(from: "file:///etc/hosts") == nil)
        #expect(StreamAddress.url(from: "javascript:alert(1)") == nil)
        #expect(StreamAddress.url(from: "http://") == nil)
    }

    @Test func namesKinds() {
        func kind(_ text: String) -> StreamAddress.Kind? { StreamAddress.url(from: text).map(StreamAddress.kind(of:)) }
        #expect(kind("https://example.com/live/index.m3u8") == .hls)
        #expect(kind("https://example.com/manifest.mpd") == .dash)
        #expect(kind("https://example.com/film.mp4") == .http)
        #expect(kind("rtsp://cam.local/h264") == .rtsp)
        #expect(kind("rtmps://example.com/app") == .rtmp)
        #expect(kind("rtp://@239.0.0.1:5004") == .rtp)
        #expect(kind("udp://@:1234") == .udp)
        #expect(kind("mmsh://example.com/radio") == .mms)
        #expect(kind("srt://example.com:9000") == .srt)
        #expect(kind("smb://nas.local/Movies/Heat.mkv") == .share)
        #expect(StreamAddress.title(for: URL(string: "https://example.com/live/index.m3u8")!) == "index.m3u8 on example.com")
        #expect(StreamAddress.title(for: URL(string: "rtsp://cam.local")!) == "cam.local")
    }

    @Test func recentStreamsStayShortAndPrivate() throws {
        var recent = RecentStreams()
        for index in 0..<25 {
            recent.add(URL(string: "https://example.com/\(index).m3u8")!)
        }
        #expect(recent.entries.count == RecentStreams.limit)
        #expect(recent.entries.first?.url.lastPathComponent == "24.m3u8")
        recent.add(URL(string: "https://example.com/10.m3u8")!)
        #expect(recent.entries.first?.url.lastPathComponent == "10.m3u8")
        #expect(recent.entries.count == RecentStreams.limit)
        recent.add(URL(string: "rtsp://admin:secret@cam.local/h264")!)
        #expect(!recent.entries.contains { $0.url.host == "cam.local" })
        let data = try JSONEncoder().encode(recent)
        #expect(try JSONDecoder().decode(RecentStreams.self, from: data) == recent)
        recent.remove(URL(string: "https://example.com/10.m3u8")!)
        #expect(recent.entries.first?.url.lastPathComponent == "24.m3u8")
    }
}
