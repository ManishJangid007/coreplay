import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

private let movieKind = VideoKind.movie.rawValue

/// Home's Continue Watching and Up Next rows, as in the TV app.
public struct WatchNowRows: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @State private var continueWatching: [Video] = []
    @State private var upNext: [Video] = []

    public init() {}

    public var body: some View {
        let playback = VideoPlayback(library: library, session: session, actions: actions)
        VStack(alignment: .leading, spacing: 30) {
            if !continueWatching.isEmpty {
                Shelf("Continue Watching") {
                    ForEach(continueWatching) { video in
                        Button {
                            playback.play(video)
                        } label: {
                            VideoStillCell(video: video)
                                .frame(width: 300)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            VideoMenuItems(video: video)
                        }
                    }
                }
            }
            if !upNext.isEmpty {
                Shelf("Up Next") {
                    ForEach(upNext) { video in
                        Button {
                            playback.play(video)
                        } label: {
                            VideoStillCell(video: video)
                                .frame(width: 300)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            VideoMenuItems(video: video)
                        }
                    }
                }
            }
        }
        .task(id: library.revision) {
            continueWatching = library.continueWatching()
            let inProgress = Set(continueWatching.map(\.id))
            upNext = library.upNext().filter { !inProgress.contains($0.id) }
        }
    }
}

/// Home's Watchlist row: movies and shows added with "+".
public struct WatchlistRow: View {
    @Environment(LibraryManager.self) private var library

    public init() {}

    public var body: some View {
        // Reading `watchlist` keeps the row in step with the "+" buttons.
        let entries = library.watchlist.isEmpty ? [] : library.watchlistEntries()
        if !entries.isEmpty {
            Shelf("Watchlist") {
                ForEach(entries) { entry in
                    switch entry {
                    case .movie(let movie):
                        NavigationLink(value: movie) {
                            MoviePosterCell(video: movie)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Watchlist", systemImage: "minus.circle") { library.toggleWatchlist(movie) }
                            Divider()
                            VideoMenuItems(video: movie)
                        }
                    case .show(let show):
                        NavigationLink(value: show) {
                            ShowPosterCell(show: show)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Watchlist", systemImage: "minus.circle") { library.toggleWatchlist(show) }
                            Divider()
                            ShowMenuItems(show: show)
                        }
                    }
                }
            }
        }
    }
}

/// Home's Recently Added Movies and TV Shows rows.
public struct RecentlyAddedVideoRows: View {
    @Query(RecentlyAddedVideoRows.movies) private var movies: [Video]
    @Query(RecentlyAddedVideoRows.shows) private var shows: [TVShow]

    private static var movies: FetchDescriptor<Video> {
        var descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.kindRaw == movieKind }, sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 16
        return descriptor
    }

    private static var shows: FetchDescriptor<TVShow> {
        var descriptor = FetchDescriptor<TVShow>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 16
        return descriptor
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !movies.isEmpty {
                Shelf("Recently Added Movies") {
                    ForEach(movies) { movie in
                        NavigationLink(value: movie) {
                            MoviePosterCell(video: movie)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            VideoMenuItems(video: movie)
                        }
                    }
                }
            }
            if !shows.isEmpty {
                Shelf("Recently Added TV Shows") {
                    ForEach(shows) { show in
                        NavigationLink(value: show) {
                            ShowPosterCell(show: show)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ShowMenuItems(show: show)
                        }
                    }
                }
            }
        }
    }
}

/// A video in search results and lists: small artwork, title and detail.
public struct VideoRow: View {
    @Environment(LibraryManager.self) private var library
    private let video: Video

    public init(video: Video) {
        self.video = video
    }

    public var body: some View {
        HStack(spacing: 12) {
            Group {
                if video.kind == .movie {
                    ArtworkView(url: library.artworkURL(video.posterArtworkKey ?? video.stillArtworkKey, .thumbnail), shape: .poster, maxPixelSize: 160, placeholderSymbol: "film")
                        .frame(width: 40)
                } else {
                    ArtworkView(url: library.artworkURL(video.stillArtworkKey ?? video.posterArtworkKey, .grid), shape: .still, maxPixelSize: 240, placeholderSymbol: video.kind == .episode ? "tv" : "video")
                        .frame(width: 96)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.displayTitle)
                    .lineLimit(1)
                if let detail = library.subtitle(for: video), !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if library.isWatched(video) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Watched"))
            }
        }
        .opacity(video.isAvailable ? 1 : 0.5)
        .contextMenu {
            VideoMenuItems(video: video)
        }
    }
}

/// A show in search results.
public struct ShowRow: View {
    @Environment(LibraryManager.self) private var library
    private let show: TVShow

    public init(show: TVShow) {
        self.show = show
    }

    public var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: library.artworkURL(show.posterArtworkKey, .thumbnail), shape: .poster, maxPixelSize: 160, placeholderSymbol: "tv")
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.title)
                    .lineLimit(1)
                Text([show.year.map(String.init), VideoFormat.seasonCount(show)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            ShowMenuItems(show: show)
        }
    }
}
