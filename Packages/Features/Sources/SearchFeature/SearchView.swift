import DesignSystem
import MediaLibrary
import MusicFeature
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI
import VideoFeature

/// One search across the library, grouped by type, with scopes like Apple Music.
public struct SearchView: View {
    public enum Scope: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case music = "Music"
        case videos = "Videos"

        public var id: String { rawValue }
    }

    @State private var query = ""
    @State private var scope: Scope = .all

    public init() {}

    public var body: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if text.isEmpty {
                EmptyStateView(
                    "Search Your Library",
                    systemImage: "magnifyingglass",
                    message: "Find artists, albums, songs, movies, shows and home videos."
                )
            } else {
                SearchResults(text: text, scope: scope)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: Text("Movies, Shows, Artists, Albums and More"))
        .searchScopes($scope) {
            ForEach(Scope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
    }
}

private struct SearchResults: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Query private var artists: [Artist]
    @Query private var albums: [Album]
    @Query private var tracks: [Track]
    @Query private var movies: [Video]
    @Query private var shows: [TVShow]
    @Query private var episodes: [Video]
    @Query private var homeVideos: [Video]
    private let text: String
    private let scope: SearchView.Scope

    init(text: String, scope: SearchView.Scope) {
        self.text = text
        self.scope = scope

        var artistQuery = FetchDescriptor<Artist>(
            predicate: #Predicate { $0.name.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\.sortName)]
        )
        artistQuery.fetchLimit = 6
        _artists = Query(artistQuery)

        var albumQuery = FetchDescriptor<Album>(
            predicate: #Predicate { $0.title.localizedStandardContains(text) || $0.artistName.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        albumQuery.fetchLimit = 12
        _albums = Query(albumQuery)

        var trackQuery = FetchDescriptor<Track>(
            predicate: #Predicate {
                $0.title.localizedStandardContains(text)
                    || $0.artistName.localizedStandardContains(text)
                    || $0.albumTitle.localizedStandardContains(text)
            },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        trackQuery.fetchLimit = 30
        _tracks = Query(trackQuery)

        let movieKind = VideoKind.movie.rawValue
        var movieQuery = FetchDescriptor<Video>(
            predicate: #Predicate { $0.kindRaw == movieKind && $0.title.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        movieQuery.fetchLimit = 12
        _movies = Query(movieQuery)

        var showQuery = FetchDescriptor<TVShow>(
            predicate: #Predicate { $0.title.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        showQuery.fetchLimit = 8
        _shows = Query(showQuery)

        let episodeKind = VideoKind.episode.rawValue
        var episodeQuery = FetchDescriptor<Video>(
            predicate: #Predicate { $0.kindRaw == episodeKind && $0.title.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        episodeQuery.fetchLimit = 20
        _episodes = Query(episodeQuery)

        let homeKind = VideoKind.homeVideo.rawValue
        var homeQuery = FetchDescriptor<Video>(
            predicate: #Predicate { $0.kindRaw == homeKind && $0.title.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        homeQuery.fetchLimit = 20
        _homeVideos = Query(homeQuery)
    }

    private var showsMusic: Bool { scope != .videos }
    private var showsVideos: Bool { scope != .music }

    var body: some View {
        let hasMusic = showsMusic && !(artists.isEmpty && albums.isEmpty && tracks.isEmpty)
        let hasVideos = showsVideos && !(movies.isEmpty && shows.isEmpty && episodes.isEmpty && homeVideos.isEmpty)
        if !hasMusic && !hasVideos {
            ContentUnavailableView.search(text: text)
        } else {
            List {
                if showsVideos, !movies.isEmpty {
                    Section("Movies") {
                        ForEach(movies) { movie in
                            NavigationLink(value: movie) {
                                VideoRow(video: movie)
                            }
                        }
                    }
                }
                if showsVideos, !shows.isEmpty {
                    Section("TV Shows") {
                        ForEach(shows) { show in
                            NavigationLink(value: show) {
                                ShowRow(show: show)
                            }
                        }
                    }
                }
                if showsMusic, !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists) { artist in
                            NavigationLink(value: artist) {
                                Label(artist.name, systemImage: "music.mic")
                            }
                        }
                    }
                }
                if showsMusic, !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumResultRow(album: album)
                            }
                        }
                    }
                }
                if showsMusic, !tracks.isEmpty {
                    Section("Songs") {
                        ForEach(tracks) { track in
                            Button {
                                play(track)
                            } label: {
                                TrackRow(track: track, isCurrent: session.currentItem?.libraryID == track.file?.id)
                            }
                            .buttonStyle(.plain)
                            .disabled(!track.isAvailable)
                        }
                    }
                }
                if showsVideos, !episodes.isEmpty {
                    Section("Episodes") {
                        ForEach(episodes) { episode in
                            NavigationLink(value: episode) {
                                VideoRow(video: episode)
                            }
                        }
                    }
                }
                if showsVideos, !homeVideos.isEmpty {
                    Section("Home Videos") {
                        ForEach(homeVideos) { video in
                            NavigationLink(value: video) {
                                VideoRow(video: video)
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    /// Like Music, a song found by search plays on its own.
    private func play(_ track: Track) {
        guard let item = library.playbackItem(for: track) else { return }
        Task {
            await session.play(item)
        }
    }

}

private struct AlbumResultRow: View {
    @Environment(LibraryManager.self) private var library
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: library.artworkURL(album.artworkKey, .thumbnail), shape: .square, maxPixelSize: 140, placeholderSymbol: "square.stack")
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .lineLimit(1)
                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
