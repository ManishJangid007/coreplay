import Foundation
import Testing
@testable import PlaybackCore

@Suite("Playlist files")
struct PlaylistFileTests {
    let playlist = URL(filePath: "/Music/Mixes/Road Trip.m3u")

    @Test func formatsFromExtensions() {
        #expect(PlaylistFile.format(of: URL(filePath: "/a/b.M3U")) == .m3u)
        #expect(PlaylistFile.format(of: URL(filePath: "/a/b.m3u8")) == .m3u)
        // An HLS stream is media, not a playlist file.
        #expect(PlaylistFile.format(of: URL(string: "https://example.com/live.m3u8")!) == nil)
        #expect(PlaylistFile.format(of: URL(filePath: "/a/b.pls")) == .pls)
        #expect(PlaylistFile.format(of: URL(filePath: "/a/b.xspf")) == .xspf)
        #expect(PlaylistFile.format(of: URL(filePath: "/a/b.cue")) == .cue)
        #expect(PlaylistFile.format(of: URL(filePath: "/a/b.mp3")) == nil)
    }

    @Test func extendedM3U() {
        let text = "\u{FEFF}#EXTM3U\n#EXTINF:215,Daft Punk - Get Lucky\n../Daft Punk/Get Lucky.mp3\n\n#EXTINF:-1 tvg-name=\"Radio\",Radio Paradise\nhttps://stream.example.com/rp.aac\n/Volumes/Music/Song.flac\nC:\\Users\\me\\Music\\Old Song.mp3\n# a comment\n"
        let entries = PlaylistFile.parse(Data(text.utf8), format: .m3u, playlistURL: playlist)
        #expect(entries.count == 4)
        #expect(entries[0].url.path(percentEncoded: false) == "/Music/Daft Punk/Get Lucky.mp3")
        #expect(entries[0].artist == "Daft Punk")
        #expect(entries[0].title == "Get Lucky")
        #expect(entries[0].duration == 215)
        #expect(entries[1].url.absoluteString == "https://stream.example.com/rp.aac")
        #expect(entries[1].title == "Radio Paradise")
        #expect(entries[1].duration == nil)
        #expect(entries[2].url.path(percentEncoded: false) == "/Volumes/Music/Song.flac")
        // A Windows drive path: looked for next to the playlist.
        #expect(entries[3].url.path(percentEncoded: false) == "/Music/Mixes/Old Song.mp3")
    }

    @Test func latin1M3U() {
        let bytes: [UInt8] = Array("Caf".utf8) + [0xE9] + Array(".mp3\n".utf8)
        let entries = PlaylistFile.parse(Data(bytes), format: .m3u, playlistURL: playlist)
        #expect(entries.first?.url.lastPathComponent == "Café.mp3")
    }

    @Test func pls() {
        let text = "[playlist]\nFile1=song one.mp3\nTitle1=Song One\nLength1=200\nFile2=http://radio.example.com:8000/stream\nTitle2=\nLength2=-1\nNumberOfEntries=2\nVersion=2\n"
        let entries = PlaylistFile.parse(Data(text.utf8), format: .pls, playlistURL: playlist)
        #expect(entries.count == 2)
        #expect(entries[0].url.path(percentEncoded: false) == "/Music/Mixes/song one.mp3")
        #expect(entries[0].title == "Song One")
        #expect(entries[0].duration == 200)
        #expect(entries[1].url.absoluteString == "http://radio.example.com:8000/stream")
        #expect(entries[1].title == nil)
    }

    @Test func xspf() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <playlist version="1" xmlns="http://xspf.org/ns/0/">
          <trackList>
            <track><location>file:///Music/A%20Song.flac</location><title>A Song</title><creator>Someone</creator><duration>183000</duration></track>
            <track><location>Other%20Song.ogg</location></track>
            <track><title>No location</title></track>
          </trackList>
        </playlist>
        """
        let entries = PlaylistFile.parse(Data(xml.utf8), format: .xspf, playlistURL: URL(filePath: "/Music/Mixes/list.xspf"))
        #expect(entries.count == 2)
        #expect(entries[0].url.path(percentEncoded: false) == "/Music/A Song.flac")
        #expect(entries[0].title == "A Song")
        #expect(entries[0].artist == "Someone")
        #expect(entries[0].duration == 183)
        #expect(entries[1].url.path(percentEncoded: false) == "/Music/Mixes/Other Song.ogg")
    }

    @Test func cueSheetSplitsOneFileIntoTracks() {
        let text = """
        PERFORMER "The Band"
        TITLE "Live"
        FILE "Live Album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Opening"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Second"
            PERFORMER "Guest"
            INDEX 00 03:58:00
            INDEX 01 04:00:37
          TRACK 03 AUDIO
            TITLE "Last"
            INDEX 01 08:30:00
        FILE "Encore.wav" WAVE
          TRACK 04 AUDIO
            TITLE "Encore"
            INDEX 01 00:00:00
        """
        let entries = PlaylistFile.parse(Data(text.utf8), format: .cue, playlistURL: URL(filePath: "/Music/Live/Live.cue"))
        #expect(entries.count == 4)
        #expect(entries[0].url.path(percentEncoded: false) == "/Music/Live/Live Album.flac")
        #expect(entries[0].title == "Opening")
        #expect(entries[0].artist == "The Band")
        #expect(entries[0].start == 0)
        #expect(entries[0].end == 240 + 37.0 / 75)
        #expect(entries[1].artist == "Guest")
        #expect(entries[1].start == 240 + 37.0 / 75)
        #expect(entries[1].end == 510)
        // The last track of a file runs to its end.
        #expect(entries[2].end == nil)
        #expect(entries[3].url.lastPathComponent == "Encore.wav")
        #expect(entries[3].start == 0)
        #expect(PlaylistFile.cueTime("01:02:75") == nil)

        // Each track plays as a segment of its file, and they run on into each other.
        let items = entries.map(\.playbackItem)
        #expect(items[0].segment == PlaybackSegment(start: 0, end: 240 + 37.0 / 75))
        #expect(items[0].segment!.continues(into: items[1].segment!))
        #expect(!items[2].segment!.continues(into: items[3].segment ?? PlaybackSegment(start: 0)))
        #expect(items[2].segment?.duration(fileDuration: 600) == 90)
        #expect(items[3].segment == nil)
        #expect(items[1].title == "Second")
    }
}
