import DesignSystem
import MediaLibrary
import NowPlaying
import SwiftData
import SwiftUI

/// Genres from the files' tags, as coloured tiles with their covers.
public struct GenresView: View {
    @Query(sort: \Genre.key) private var genres: [Genre]

    public init() {}

    public var body: some View {
        Group {
            if genres.isEmpty {
                MusicEmptyState()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18)], spacing: 18) {
                        ForEach(genres) { genre in
                            NavigationLink(value: genre) {
                                GenreTile(genre: genre)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Metrics.contentPadding)
                }
            }
        }
        .navigationTitle("Genres")
    }
}

/// A genre's albums, with Play and Shuffle for all its songs.
public struct GenreDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    private let genre: Genre

    public init(genre: Genre) {
        self.genre = genre
    }

    public var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        let albums = genre.albums
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlayShuffleButtons(
                    onPlay: { playback.play(albums.flatMap(\.orderedTracks).filter { $0.genre?.persistentModelID == genre.persistentModelID }, shuffled: false) },
                    onShuffle: { playback.shuffle(genre.tracks) }
                )
                .frame(maxWidth: .infinity)
                AlbumGrid(albums: albums)
            }
            .padding(Metrics.contentPadding)
        }
        .navigationTitle(genre.name)
    }
}
