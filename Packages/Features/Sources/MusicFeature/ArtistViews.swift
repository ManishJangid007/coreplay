import DesignSystem
import MediaLibrary
import NowPlaying
import SwiftData
import SwiftUI

/// Every artist, alphabetically (ignoring "The"), like Music's Artists list.
public struct ArtistsView: View {
    @Query(sort: \Artist.sortName) private var artists: [Artist]

    public init() {}

    public var body: some View {
        Group {
            if artists.isEmpty {
                MusicEmptyState()
            } else {
                List(artists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Artists")
    }
}

struct ArtistRow: View {
    @Environment(LibraryManager.self) private var library
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            ArtistPortrait(artworkURL: library.artworkURL(artist.artworkKey, .thumbnail), size: 44)
            Text(artist.name)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

/// Artists show in circles. Without a photo of the artist, their artwork stands in.
struct ArtistPortrait: View {
    let artworkURL: URL?
    let size: CGFloat

    var body: some View {
        ArtworkView(url: artworkURL, shape: .square, maxPixelSize: Int(size * 3), placeholderSymbol: "music.mic")
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// An artist page: their albums, albums they appear on, and their songs.
public struct ArtistDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @State private var editingTrack: Track?
    private let artist: Artist

    public init(artist: Artist) {
        self.artist = artist
    }

    public var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        let albums = artist.sortedAlbums
        let appearsOn = appearsOnAlbums(excluding: albums)
        let songs = artist.tracks.sorted { lhs, rhs in
            if lhs.albumTitle != rhs.albumTitle { return lhs.albumTitle < rhs.albumTitle }
            return Album.trackOrder(lhs, rhs)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 16) {
                    ArtistPortrait(artworkURL: library.artworkURL(artist.artworkKey, .large), size: 180)
                        .artworkShadow()
                    Text(artist.name)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    if !songs.isEmpty {
                        PlayShuffleButtons(
                            onPlay: { playback.play(songs, shuffled: false) },
                            onShuffle: { playback.shuffle(songs) }
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                if !albums.isEmpty {
                    section("Albums") {
                        AlbumGrid(albums: albums)
                    }
                }
                if !appearsOn.isEmpty {
                    section("Appears On") {
                        AlbumGrid(albums: appearsOn)
                    }
                }
                if !songs.isEmpty {
                    section("Songs") {
                        LazyVStack(spacing: 0) {
                            ForEach(songs) { track in
                                Button {
                                    playback.play(songs, startingAt: track)
                                } label: {
                                    TrackRow(track: track, isCurrent: playback.isCurrent(track))
                                }
                                .buttonStyle(.plain)
                                .disabled(!track.isAvailable)
                                .contextMenu {
                                    TrackMenuItems(tracks: [track], onEditInfo: { editingTrack = track })
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(Metrics.contentPadding)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(artist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editingTrack) { track in
            TrackEditView(track: track)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    /// Albums by others (compilations, collaborations) that include this artist.
    private func appearsOnAlbums(excluding own: [Album]) -> [Album] {
        let ownIDs = Set(own.map(\.persistentModelID))
        var seen = Set<PersistentIdentifier>()
        var result: [Album] = []
        for track in artist.tracks {
            guard let album = track.album, !ownIDs.contains(album.persistentModelID),
                  seen.insert(album.persistentModelID).inserted else { continue }
            result.append(album)
        }
        return result.sorted { $0.sortTitle < $1.sortTitle }
    }
}
