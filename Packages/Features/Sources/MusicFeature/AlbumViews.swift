import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// Every album, as a grid, with Music's sort options.
public struct AlbumsView: View {
    public enum Sort: String, CaseIterable, Identifiable {
        case title, artist, recentlyAdded, year

        public var id: Self { self }

        var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .recentlyAdded: "Recently Added"
            case .year: "Year"
            }
        }
    }

    @AppStorage("albums.sort") private var sortRaw = Sort.title.rawValue
    @AppStorage("albums.layout") private var layoutRaw = LibraryLayout.grid.rawValue

    public init() {}

    public var body: some View {
        AlbumsQueryView(sort: Sort(rawValue: sortRaw) ?? .title, layout: LibraryLayout(rawValue: layoutRaw) ?? .grid)
            .navigationTitle("Albums")
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

private struct AlbumsQueryView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.libraryHero) private var libraryHero
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query private var albums: [Album]
    @State private var opened: Album?
    let layout: LibraryLayout

    init(sort: AlbumsView.Sort, layout: LibraryLayout) {
        self.layout = layout
        switch sort {
        case .title:
            _albums = Query(sort: [SortDescriptor(\Album.sortTitle)])
        case .artist:
            _albums = Query(sort: [SortDescriptor(\Album.sortArtistName), SortDescriptor(\Album.year), SortDescriptor(\Album.sortTitle)])
        case .recentlyAdded:
            _albums = Query(sort: [SortDescriptor(\Album.dateAdded, order: .reverse), SortDescriptor(\Album.sortTitle)])
        case .year:
            _albums = Query(sort: [SortDescriptor(\Album.year, order: .reverse), SortDescriptor(\Album.sortTitle)])
        }
    }

    var body: some View {
        Group {
            if albums.isEmpty {
                MusicEmptyState()
            } else if layout == .coverFlow {
                CoverFlowView(albums, title: \.title, subtitle: { $0.artistName }, onOpen: { opened = $0 }) { album in
                    FilledArtwork(url: library.artworkURL(album.artworkKey, .large), maxPixelSize: 800)
                        .background {
                            LinearGradient(colors: [Color(white: 0.3), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                        }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Music's big carousel: what's new and what you've been playing.
                        libraryHero?.make(.music, isCompact)
                        AlbumGrid(albums: albums)
                            .padding(Metrics.contentPadding)
                    }
                }
                .heroPageChrome(libraryHero != nil && !isCompact)
            }
        }
        .navigationDestination(item: $opened) { album in
            AlbumDetailView(album: album)
        }
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
}

/// A grid of album cells that open the album page.
public struct AlbumGrid: View {
    private let albums: [Album]

    public init(albums: [Album]) {
        self.albums = albums
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 18, alignment: .top)],
            alignment: .leading,
            spacing: 24
        ) {
            ForEach(albums) { album in
                NavigationLink(value: album) {
                    AlbumCell(album: album)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    AlbumMenuItems(album: album)
                }
            }
        }
    }
}

/// Artwork, title and artist, like an album in Music's grid.
public struct AlbumCell: View {
    @Environment(LibraryManager.self) private var library
    private let album: Album

    public init(album: Album) {
        self.album = album
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: library.artworkURL(album.artworkKey, .grid), shape: .square, maxPixelSize: 480, placeholderSymbol: "music.note")
                .artworkShadow(isProminent: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the album"))
    }
}

/// Play, Shuffle, Play Next and Play Later for a whole album.
struct AlbumMenuItems: View {
    let album: Album
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session

    var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        Button("Play", systemImage: "play") {
            playback.play(album.orderedTracks, shuffled: false)
        }
        Button("Shuffle", systemImage: "shuffle") {
            playback.shuffle(album.tracks)
        }
        Divider()
        TrackMenuItems(tracks: album.orderedTracks)
    }
}

/// An album page: large artwork, Play and Shuffle, and the track list
/// grouped by disc.
public struct AlbumDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @State private var editingTrack: Track?
    private let album: Album

    public init(album: Album) {
        self.album = album
    }

    private var playback: MusicPlayback {
        MusicPlayback(library: library, session: session)
    }

    public var body: some View {
        let tracks = album.orderedTracks
        List {
            header(tracks)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 20, trailing: 20))
            if album.hasMultipleDiscs {
                ForEach(discs(tracks)) { disc in
                    Section {
                        rows(disc.tracks, all: tracks)
                    } header: {
                        Text("Disc \(disc.number)")
                    }
                }
            } else {
                rows(tracks, all: tracks)
            }
            footer(tracks)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(alignment: .top) {
            // A wash of the cover behind the header, fading into the page.
            FilledArtwork(url: library.artworkURL(album.artworkKey, .large), maxPixelSize: 600)
                .frame(height: 460)
                .blur(radius: 70)
                .opacity(0.55)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .navigationTitle(album.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    AlbumMenuItems(album: album)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(item: $editingTrack) { track in
            TrackEditView(track: track)
        }
    }

    /// Beside the cover when there's room, as on Music for the Mac and iPad;
    /// stacked under it on an iPhone.
    private func header(_ tracks: [Track]) -> some View {
        ViewThatFits(in: .horizontal) {
            wideHeader(tracks)
                .frame(minWidth: 660)
            compactHeader(tracks)
        }
    }

    private func wideHeader(_ tracks: [Track]) -> some View {
        HStack(alignment: .bottom, spacing: 28) {
            ArtworkView(url: library.artworkURL(album.artworkKey, .large), shape: .square, maxPixelSize: 900, placeholderSymbol: "music.note")
                .frame(width: 250, height: 250)
                .artworkShadow()
            VStack(alignment: .leading, spacing: 8) {
                Text(album.isCompilation ? "COMPILATION" : "ALBUM")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(album.title)
                    .font(.system(size: 40, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                artistLink
                    .font(.title3.weight(.semibold))
                if let details = details(tracks) {
                    Text("\(details) \u{00B7} \(MusicFormat.summary(songs: tracks.count, seconds: album.totalDuration))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                PlayShuffleButtons(
                    onPlay: { playback.play(tracks, shuffled: false) },
                    onShuffle: { playback.shuffle(tracks) }
                )
                .frame(maxWidth: 340)
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var artistLink: some View {
        if let artist = album.artist {
            NavigationLink(value: artist) {
                Text(album.artistName)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } else {
            Text(album.artistName)
                .foregroundStyle(Color.accentColor)
        }
    }

    private func compactHeader(_ tracks: [Track]) -> some View {
        VStack(spacing: 14) {
            ArtworkView(url: library.artworkURL(album.artworkKey, .large), shape: .square, maxPixelSize: 900, placeholderSymbol: "music.note")
                .frame(maxWidth: 300)
                .artworkShadow()
            VStack(spacing: 4) {
                Text(album.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let artist = album.artist {
                    NavigationLink(value: artist) {
                        Text(album.artistName)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(album.artistName)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                if let details = details(tracks) {
                    Text(details)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            PlayShuffleButtons(
                onPlay: { playback.play(tracks, shuffled: false) },
                onShuffle: { playback.shuffle(tracks) }
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// "ROCK · 1997 · LOSSLESS"
    private func details(_ tracks: [Track]) -> String? {
        var parts: [String] = []
        if let genre = album.genreName { parts.append(genre) }
        if let year = album.year { parts.append(String(year)) }
        if let badge = tracks.lazy.compactMap({ $0.file?.qualityBadge }).first { parts.append(badge) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private func rows(_ tracks: [Track], all: [Track]) -> some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            Button {
                playback.play(all, startingAt: track)
            } label: {
                ChartTrackRow(
                    track: track,
                    number: track.trackNumber ?? index + 1,
                    showsArtwork: false,
                    showsArtist: album.isCompilation || track.artistName.localizedCaseInsensitiveCompare(album.artistName) != .orderedSame,
                    isCurrent: playback.isCurrent(track),
                    isStriped: index.isMultiple(of: 2)
                )
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
            .disabled(!track.isAvailable)
            .contextMenu {
                TrackMenuItems(tracks: [track], onEditInfo: { editingTrack = track }, showsGoToAlbum: false)
            }
            #if os(iOS)
            .swipeActions(edge: .leading) {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    playback.playNext([track])
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .trailing) {
                Button("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") {
                    playback.playLater([track])
                }
                .tint(.orange)
            }
            #endif
        }
    }

    private func footer(_ tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MusicFormat.summary(songs: tracks.count, seconds: album.totalDuration))
            if album.isCompilation {
                Text("Compilation")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private struct Disc: Identifiable {
        let number: Int
        let tracks: [Track]
        var id: Int { number }
    }

    private func discs(_ tracks: [Track]) -> [Disc] {
        let grouped = Dictionary(grouping: tracks) { $0.discNumber ?? 1 }
        return grouped.keys.sorted().map { Disc(number: $0, tracks: grouped[$0] ?? []) }
    }
}
