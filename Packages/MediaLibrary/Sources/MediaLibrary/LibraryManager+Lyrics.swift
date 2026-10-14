import Foundation
import MetadataProviders
import PlaybackCore
import SwiftData

extension LibraryManager {
    static let lyricsLookupKey = "metadata.looksUpLyrics"

    public func setLooksUpLyrics(_ looksUp: Bool) {
        looksUpLyrics = looksUp
        UserDefaults.standard.set(looksUp, forKey: Self.lyricsLookupKey)
    }

    /// A library file's content key (the same file has the same key on every device).
    public func contentKey(libraryID: UUID) -> String? {
        mediaFile(id: libraryID)?.contentKey
    }

    /// Something to play for a content key, if this library has the file.
    public func playbackItem(contentKey: String) -> PlaybackItem? {
        guard !contentKey.isEmpty else { return nil }
        var descriptor = FetchDescriptor<MediaFile>(predicate: #Predicate { $0.contentKey == contentKey })
        descriptor.fetchLimit = 1
        guard let file = (try? context.fetch(descriptor))?.first else { return nil }
        return playbackItem(for: file)
    }

    /// The song a library file belongs to.
    public func track(libraryID: UUID) -> Track? {
        mediaFile(id: libraryID)?.track
    }

    /// A song's lyrics: from its tags, an `.lrc` file beside it, or (when
    /// lookups are on) LRCLIB, which are then kept with the song.
    public func lyrics(for track: Track) async -> Lyrics? {
        if let text = track.lyrics, let lyrics = Lyrics(text: text) {
            return lyrics
        }
        if let file = track.file, let url = url(for: file) {
            let sidecar = url.deletingPathExtension().appendingPathExtension("lrc")
            if let text = await Task.detached(priority: .userInitiated, operation: { Self.readText(at: sidecar) }).value,
               let lyrics = Lyrics(text: text) {
                return lyrics
            }
        }
        guard looksUpLyrics, !track.title.isEmpty, !track.artistName.isEmpty else { return nil }
        let result = try? await LRCLIBClient().lyrics(title: track.title, artist: track.artistName, album: track.albumTitle, duration: track.duration)
        guard let text = result?.bestText, let lyrics = Lyrics(text: text) else { return nil }
        if track.lyrics?.isEmpty ?? true {
            track.lyrics = text
            save()
        }
        return lyrics
    }

    /// Lyrics for a file played from outside the library: an `.lrc` beside it.
    public func lyrics(besideFileAt url: URL) async -> Lyrics? {
        guard url.isFileURL else { return nil }
        let sidecar = url.deletingPathExtension().appendingPathExtension("lrc")
        guard let text = await Task.detached(priority: .userInitiated, operation: { Self.readText(at: sidecar) }).value else { return nil }
        return Lyrics(text: text)
    }

    nonisolated static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count < 512_000 else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
