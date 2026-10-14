import Foundation
import Testing
@testable import Networking
import PlaybackCore

@MainActor
@Suite("Saved servers and network places")
struct NetworkStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "coreplay-network-\(UUID().uuidString)/Network.json")
    }

    @Test func serversAreKeptAndFound() throws {
        let file = temporaryFile()
        let store = NetworkStore(fileURL: file)
        let nas = SavedServer(name: "", networkProtocol: .smb, host: "nas.local", path: "/Movies", user: "bob", domain: "")
        let films = SavedServer(name: "Films", networkProtocol: .smb, host: "NAS.local", path: "/Movies/Films")
        let ftp = SavedServer(networkProtocol: .ftp, host: "files.example.com", port: 2121)
        store.save(nas)
        store.save(films)
        store.save(ftp)
        #expect(nas.displayName == "Movies")
        #expect(nas.domain == nil)
        #expect(nas.summary == "SMB \u{00B7} nas.local/Movies")
        #expect(nas.url?.absoluteString == "smb://nas.local/Movies/")
        #expect(store.servers.map(\.displayName) == ["files.example.com", "Films", "Movies"])

        // The deepest saved folder a file is in, matching the host whatever its case.
        #expect(store.server(for: URL(string: "smb://nas.local/Movies/Films/Heat.mkv")!)?.id == films.id)
        #expect(store.server(for: URL(string: "smb://nas.local/Movies/Other/Heat.mkv")!)?.id == nas.id)
        #expect(store.server(for: URL(string: "ftp://files.example.com:2121/a.mp4")!)?.id == ftp.id)
        #expect(store.server(for: URL(string: "ftp://files.example.com/a.mp4")!) == nil)
        #expect(store.server(for: URL(string: "sftp://nas.local/Movies/a.mkv")!) == nil)

        // They come back next launch; renaming keeps the same server.
        var renamed = nas
        renamed.name = "Living Room NAS"
        store.save(renamed)
        let reopened = NetworkStore(fileURL: file)
        #expect(reopened.servers.count == 3)
        #expect(reopened.servers.contains { $0.id == nas.id && $0.name == "Living Room NAS" })
        reopened.remove(renamed)
        #expect(NetworkStore(fileURL: file).servers.count == 2)
    }

    @Test func recentStreamsAndResumePointsPersist() throws {
        let file = temporaryFile()
        let store = NetworkStore(fileURL: file)
        let stream = URL(string: "https://example.com/live.m3u8")!
        store.noteStream(stream)
        let video = URL(string: "smb://bob:secret@nas.local/Movies/Heat.mkv")!
        store.setResumePosition(1_234, for: video)
        let reopened = NetworkStore(fileURL: file)
        #expect(reopened.recentStreams.entries.map(\.url) == [stream])
        // Found with or without the login in the address.
        #expect(reopened.resumePosition(for: URL(string: "smb://nas.local/Movies/Heat.mkv")!) == 1_234)
        reopened.setResumePosition(nil, for: video)
        #expect(NetworkStore(fileURL: file).resumePosition(for: video) == nil)
        reopened.forgetStream(stream)
        #expect(NetworkStore(fileURL: file).recentStreams.entries.isEmpty)
        // The file never holds a password.
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("secret"))
    }

    @Test func onlyRecentPlacesAreKept() {
        let store = NetworkStore(fileURL: nil)
        for index in 0..<(NetworkStore.resumeLimit + 5) {
            store.setResumePosition(TimeInterval(index + 1), for: URL(string: "smb://nas/\(index).mkv")!)
        }
        #expect(store.resumePosition(for: URL(string: "smb://nas/0.mkv")!) == nil)
        #expect(store.resumePosition(for: URL(string: "smb://nas/\(NetworkStore.resumeLimit + 4).mkv")!) != nil)
    }
}
