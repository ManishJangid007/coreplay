import Foundation
import MetadataProviders
import SwiftData

/// Finds or creates the artist, album and genre a track belongs to, within
/// one model context, and removes groups nothing refers to any more.
///
/// The scanner (in its own context) and Edit Info (in the main context) both
/// use it, so grouping rules live in one place.
final class LibraryGrouper {
    static let variousArtists = "Various Artists"
    static let unknownArtist = "Unknown Artist"
    static let unknownAlbum = "Unknown Album"

    let context: ModelContext
    private var artists: [String: Artist] = [:]
    private var albums: [String: Album] = [:]
    private var genres: [String: Genre] = [:]

    init(context: ModelContext) {
        self.context = context
    }

    /// Albums are grouped by album artist and title; compilations by title alone.
    static func albumKey(title: String, artistName: String, isCompilation: Bool) -> String {
        let titleKey = NameNormalizer.groupKey(title)
        return isCompilation ? "compilation|\(titleKey)" : "\(NameNormalizer.groupKey(artistName))|\(titleKey)"
    }

    func artist(named name: String, sortName: String? = nil) -> Artist {
        let key = NameNormalizer.groupKey(name)
        if let cached = artists[key] {
            return cached
        }
        var descriptor = FetchDescriptor<Artist>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            artists[key] = existing
            return existing
        }
        let artist = Artist()
        artist.key = key
        artist.name = name
        artist.sortName = NameNormalizer.sortKey(sortName ?? name)
        context.insert(artist)
        artists[key] = artist
        return artist
    }

    func album(title: String, artistName: String, isCompilation: Bool, sortTitle: String? = nil, sortArtist: String? = nil) -> Album {
        let key = Self.albumKey(title: title, artistName: artistName, isCompilation: isCompilation)
        if let cached = albums[key] {
            return cached
        }
        var descriptor = FetchDescriptor<Album>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            albums[key] = existing
            return existing
        }
        let album = Album()
        album.key = key
        album.title = title
        album.sortTitle = NameNormalizer.sortKey(sortTitle ?? title)
        album.artistName = artistName
        album.sortArtistName = NameNormalizer.sortKey(sortArtist ?? artistName)
        album.isCompilation = isCompilation
        context.insert(album)
        album.artist = artist(named: artistName, sortName: sortArtist)
        albums[key] = album
        return album
    }

    func genre(named name: String) -> Genre {
        let key = NameNormalizer.groupKey(name)
        if let cached = genres[key] {
            return cached
        }
        var descriptor = FetchDescriptor<Genre>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            genres[key] = existing
            return existing
        }
        let genre = Genre()
        genre.key = key
        genre.name = name
        context.insert(genre)
        genres[key] = genre
        return genre
    }

    /// Points `track` at the artist, album and genre its current values call for.
    func attach(_ track: Track, sortArtist: String? = nil, sortAlbum: String? = nil, sortAlbumArtist: String? = nil) {
        let trackArtist = artist(named: track.artistName, sortName: sortArtist)
        if track.artist?.persistentModelID != trackArtist.persistentModelID {
            track.artist = trackArtist
        }

        let albumArtistName = track.isCompilation ? Self.variousArtists : track.albumArtistName
        let trackAlbum = album(title: track.albumTitle, artistName: albumArtistName, isCompilation: track.isCompilation, sortTitle: sortAlbum, sortArtist: sortAlbumArtist)
        if track.album?.persistentModelID != trackAlbum.persistentModelID {
            track.album = trackAlbum
        }
        if trackAlbum.year == nil {
            trackAlbum.year = track.year
        }
        if trackAlbum.genreName == nil {
            trackAlbum.genreName = track.genreName
        }
        if trackAlbum.artworkKey == nil, let artworkKey = track.artworkKey {
            trackAlbum.artworkKey = artworkKey
        }
        if let albumArtist = trackAlbum.artist, albumArtist.artworkKey == nil {
            albumArtist.artworkKey = trackAlbum.artworkKey
        }
        if trackArtist.artworkKey == nil {
            trackArtist.artworkKey = trackAlbum.artworkKey
        }

        if let genreName = track.genreName {
            let trackGenre = genre(named: genreName)
            if track.genre?.persistentModelID != trackGenre.persistentModelID {
                track.genre = trackGenre
            }
        } else if track.genre != nil {
            track.genre = nil
        }
    }

    /// Deletes albums without tracks, then artists without albums or tracks,
    /// then genres without tracks.
    func removeOrphans() throws {
        try context.save()
        for album in try context.fetch(FetchDescriptor<Album>()) where album.tracks.isEmpty {
            albums.removeValue(forKey: album.key)
            context.delete(album)
        }
        try context.save()
        for artist in try context.fetch(FetchDescriptor<Artist>()) where artist.albums.isEmpty && artist.tracks.isEmpty {
            artists.removeValue(forKey: artist.key)
            context.delete(artist)
        }
        for genre in try context.fetch(FetchDescriptor<Genre>()) where genre.tracks.isEmpty {
            genres.removeValue(forKey: genre.key)
            context.delete(genre)
        }
        try context.save()
    }
}
