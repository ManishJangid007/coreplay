import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

private let movieKind = VideoKind.movie.rawValue
private let homeVideoKind = VideoKind.homeVideo.rawValue

private let posterColumns = [GridItem(.adaptive(minimum: 140, maximum: 210), spacing: 18, alignment: .top)]
private let stillColumns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 18, alignment: .top)]

// MARK: - Movies

/// Every movie, as posters or in Cover Flow, with the TV app's sorting.
public struct MoviesView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case title, recentlyAdded, year

        var id: Self { self }

        var label: String {
            switch self {
            case .title: "Title"
            case .recentlyAdded: "Recently Added"
            case .year: "Release Date"
            }
        }
    }

    @AppStorage("movies.sort") private var sortRaw = Sort.title.rawValue
    @AppStorage("movies.layout") private var layoutRaw = LibraryLayout.grid.rawValue
    @AppStorage("movies.unwatchedOnly") private var unwatchedOnly = false

    public init() {}

    public var body: some View {
        MoviesQueryView(
            sort: Sort(rawValue: sortRaw) ?? .title,
            layout: LibraryLayout(rawValue: layoutRaw) ?? .grid,
            unwatchedOnly: unwatchedOnly
        )
        .navigationTitle("Movies")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                LibraryLayoutPicker(layout: $layoutRaw)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sortRaw) {
                        ForEach(Sort.allCases) { sort in
                            Text(sort.label).tag(sort.rawValue)
                        }
                    }
                    Toggle("Unwatched Only", isOn: $unwatchedOnly)
                } label: {
                    Label("Sort and Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
    }
}

private struct MoviesQueryView: View {
    @Environment(LibraryManager.self) private var library
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query private var movies: [Video]
    @State private var opened: Video?
    let layout: LibraryLayout
    let unwatchedOnly: Bool

    init(sort: MoviesView.Sort, layout: LibraryLayout, unwatchedOnly: Bool) {
        self.layout = layout
        self.unwatchedOnly = unwatchedOnly
        let predicate = #Predicate<Video> { $0.kindRaw == movieKind }
        switch sort {
        case .title:
            _movies = Query(filter: predicate, sort: [SortDescriptor(\Video.sortTitle)])
        case .recentlyAdded:
            _movies = Query(filter: predicate, sort: [SortDescriptor(\Video.dateAdded, order: .reverse), SortDescriptor(\Video.sortTitle)])
        case .year:
            _movies = Query(filter: predicate, sort: [SortDescriptor(\Video.year, order: .reverse), SortDescriptor(\Video.sortTitle)])
        }
    }

    var body: some View {
        let shown = unwatchedOnly ? movies.filter { !library.isWatched($0) } : movies
        Group {
            if movies.isEmpty {
                VideoEmptyState(kind: .movie)
            } else if shown.isEmpty {
                ContentUnavailableView("All Watched", systemImage: "checkmark.circle", description: Text("Every movie in your library has been watched."))
            } else if layout == .coverFlow {
                CoverFlowView(shown, aspectRatio: ArtworkShape.poster.aspectRatio, title: \.displayTitle, subtitle: { $0.year.map(String.init) }, onOpen: { opened = $0 }) { movie in
                    MovieFlowArtwork(video: movie)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HeroCarousel(content: .movies, style: heroStyle)
                        LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
                            ForEach(shown) { movie in
                                NavigationLink(value: movie) {
                                    MoviePosterCell(video: movie)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    VideoMenuItems(video: movie)
                                }
                            }
                        }
                        .padding(Metrics.contentPadding)
                    }
                }
                .heroPageChrome(heroStyle == .fullBleed)
            }
        }
        .navigationDestination(item: $opened) { movie in
            VideoDetailView(video: movie)
        }
    }

    private var heroStyle: HeroCarousel.Style {
        #if os(iOS)
        HeroCarousel.Style.forWidth(isCompact: sizeClass == .compact)
        #else
        .fullBleed
        #endif
    }
}

/// A movie's poster filling a Cover Flow frame.
private struct MovieFlowArtwork: View {
    @Environment(LibraryManager.self) private var library
    let video: Video

    var body: some View {
        if let url = library.artworkURL(video.posterArtworkKey, .grid) {
            FilledArtwork(url: url, maxPixelSize: 700)
                .background(Color(white: 0.2))
        } else {
            GeneratedPoster(imageURL: library.artworkURL(video.stillArtworkKey, .grid), title: video.displayTitle, subtitle: video.year.map(String.init))
        }
    }
}

// MARK: - TV shows

/// Every show, as posters or in Cover Flow.
public struct TVShowsView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case title, recentlyAdded

        var id: Self { self }

        var label: String {
            switch self {
            case .title: "Title"
            case .recentlyAdded: "Recently Added"
            }
        }
    }

    @AppStorage("shows.sort") private var sortRaw = Sort.title.rawValue
    @AppStorage("shows.layout") private var layoutRaw = LibraryLayout.grid.rawValue

    public init() {}

    public var body: some View {
        TVShowsQueryView(sort: Sort(rawValue: sortRaw) ?? .title, layout: LibraryLayout(rawValue: layoutRaw) ?? .grid)
            .navigationTitle("TV Shows")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    LibraryLayoutPicker(layout: $layoutRaw)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $sortRaw) {
                            ForEach(Sort.allCases) { sort in
                                Text(sort.label).tag(sort.rawValue)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
    }
}

private struct TVShowsQueryView: View {
    @Environment(LibraryManager.self) private var library
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query private var shows: [TVShow]
    @State private var opened: TVShow?
    let layout: LibraryLayout

    init(sort: TVShowsView.Sort, layout: LibraryLayout) {
        self.layout = layout
        switch sort {
        case .title:
            _shows = Query(sort: [SortDescriptor(\TVShow.sortTitle)])
        case .recentlyAdded:
            _shows = Query(sort: [SortDescriptor(\TVShow.dateAdded, order: .reverse), SortDescriptor(\TVShow.sortTitle)])
        }
    }

    var body: some View {
        Group {
            if shows.isEmpty {
                VideoEmptyState(kind: .episode)
            } else if layout == .coverFlow {
                CoverFlowView(shows, aspectRatio: ArtworkShape.poster.aspectRatio, title: \.title, subtitle: { VideoFormat.seasonCount($0) }, onOpen: { opened = $0 }) { show in
                    if let url = library.artworkURL(show.posterArtworkKey, .grid) {
                        FilledArtwork(url: url, maxPixelSize: 700)
                            .background(Color(white: 0.2))
                    } else {
                        GeneratedPoster(imageURL: library.artworkURL(show.backdropKey, .grid), title: show.title, symbol: "tv")
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HeroCarousel(content: .shows, style: heroStyle)
                        LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
                            ForEach(shows) { show in
                                NavigationLink(value: show) {
                                    ShowPosterCell(show: show)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    ShowMenuItems(show: show)
                                }
                            }
                        }
                        .padding(Metrics.contentPadding)
                    }
                }
                .heroPageChrome(heroStyle == .fullBleed)
            }
        }
        .navigationDestination(item: $opened) { show in
            ShowDetailView(show: show)
        }
    }

    private var heroStyle: HeroCarousel.Style {
        #if os(iOS)
        HeroCarousel.Style.forWidth(isCompact: sizeClass == .compact)
        #else
        .fullBleed
        #endif
    }
}

// MARK: - Home videos

/// Home videos by month, newest first, as stills. Tapping one plays it.
public struct HomeVideosView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @Query(filter: #Predicate<Video> { $0.kindRaw == homeVideoKind }, sort: \Video.dateAdded, order: .reverse)
    private var videos: [Video]

    public init() {}

    public var body: some View {
        Group {
            if videos.isEmpty {
                VideoEmptyState(kind: .homeVideo)
            } else {
                ScrollView {
                    LazyVGrid(columns: stillColumns, alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                        ForEach(months) { month in
                            Section {
                                ForEach(month.videos) { video in
                                    Button {
                                        VideoPlayback(library: library, session: session, actions: actions).play(video)
                                    } label: {
                                        VideoStillCell(video: video)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!video.isAvailable)
                                    .contextMenu {
                                        VideoMenuItems(video: video)
                                    }
                                }
                            } header: {
                                Text(month.title)
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .background(.background.opacity(0.92))
                            }
                        }
                    }
                    .padding(Metrics.contentPadding)
                }
            }
        }
        .navigationTitle("Home Videos")
    }

    private struct Month: Identifiable {
        let id: String
        let title: String
        let videos: [Video]
    }

    /// Grouped by the month they were recorded (or added).
    private var months: [Month] {
        let calendar = Calendar.current
        let sorted = videos.sorted { $0.sortDate > $1.sortDate }
        var groups: [Month] = []
        for video in sorted {
            let components = calendar.dateComponents([.year, .month], from: video.sortDate)
            let id = "\(components.year ?? 0)-\(components.month ?? 0)"
            if groups.last?.id == id {
                let last = groups.removeLast()
                groups.append(Month(id: id, title: last.title, videos: last.videos + [video]))
            } else {
                groups.append(Month(id: id, title: video.sortDate.formatted(.dateTime.month(.wide).year()), videos: [video]))
            }
        }
        return groups
    }
}

// MARK: - The Videos tab

/// The iPhone's Videos tab: Movies, TV Shows and Home Videos, then what's new.
public struct VideoLibraryView: View {
    @Query(VideoLibraryView.recentMovies) private var recentMovies: [Video]
    @Query(VideoLibraryView.recentShows) private var recentShows: [TVShow]

    private static var recentMovies: FetchDescriptor<Video> {
        var descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.kindRaw == movieKind }, sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var recentShows: FetchDescriptor<TVShow> {
        var descriptor = FetchDescriptor<TVShow>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 12
        return descriptor
    }

    public init() {}

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    MoviesView()
                } label: {
                    Label("Movies", systemImage: "film")
                }
                NavigationLink {
                    TVShowsView()
                } label: {
                    Label("TV Shows", systemImage: "tv")
                }
                NavigationLink {
                    HomeVideosView()
                } label: {
                    Label("Home Videos", systemImage: "video")
                }
            }
            if !recentMovies.isEmpty {
                Section("Recently Added Movies") {
                    posterRow(recentMovies.map { AnyPoster.movie($0) })
                }
            }
            if !recentShows.isEmpty {
                Section("Recently Added Shows") {
                    posterRow(recentShows.map { AnyPoster.show($0) })
                }
            }
        }
        .navigationTitle("Videos")
    }

    private enum AnyPoster: Identifiable {
        case movie(Video)
        case show(TVShow)

        var id: PersistentIdentifier {
            switch self {
            case .movie(let video): video.persistentModelID
            case .show(let show): show.persistentModelID
            }
        }
    }

    private func posterRow(_ posters: [AnyPoster]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(posters) { poster in
                    switch poster {
                    case .movie(let video):
                        NavigationLink(value: video) {
                            MoviePosterCell(video: video).frame(width: 120)
                        }
                        .buttonStyle(.plain)
                    case .show(let show):
                        NavigationLink(value: show) {
                            ShowPosterCell(show: show).frame(width: 120)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

/// Shown where videos would be, until there are some.
struct VideoEmptyState: View {
    let kind: VideoKind
    @Environment(\.appActions) private var actions
    @Environment(LibraryManager.self) private var library

    var body: some View {
        if library.isScanning {
            ContentUnavailableView {
                Label("Adding Your Videos", systemImage: symbol)
            } description: {
                Text("Videos appear here as Coreplay reads your folders.")
            } actions: {
                ProgressView()
            }
        } else {
            EmptyStateView(
                title,
                systemImage: symbol,
                message: message,
                actionTitle: "Add Folder\u{2026}",
                action: { actions.addLibraryFolder() }
            )
        }
    }

    private var title: String {
        switch kind {
        case .movie: "No Movies Yet"
        case .episode: "No TV Shows Yet"
        case .homeVideo: "No Home Videos Yet"
        }
    }

    private var symbol: String {
        switch kind {
        case .movie: "film"
        case .episode: "tv"
        case .homeVideo: "video"
        }
    }

    private var message: String {
        switch kind {
        case .movie:
            "Movies named like \u{201C}Heat (1995).mkv\u{201D}, or kept in a folder you mark as Movies in Sources, appear here with posters and details."
        case .episode:
            "Episodes named like \u{201C}Show S01E02.mkv\u{201D}, or kept in Show/Season 1 folders, are grouped into shows and seasons here."
        case .homeVideo:
            "Videos from your phone or camera, and anything that isn\u{2019}t a movie or an episode, appear here by date."
        }
    }
}
