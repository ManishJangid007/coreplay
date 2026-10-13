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

    public init() {}

    public var body: some View {
        AlbumsQueryView(sort: Sort(rawValue: sortRaw) ?? .title)
            .navigationTitle("Albums")
            .toolbar {
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
    @Query private var albums: [Album]

    init(sort: AlbumsView.Sort) {
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
        if albums.isEmpty {
            MusicEmptyState()
        } else {
            ScrollView {
                AlbumGrid(albums: albums)
                    .padding(Metrics.contentPadding)
            }
        }
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

    private func header(_ tracks: [Track]) -> some View {
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
        ForEach(tracks) { track in
            Button {
                playback.play(all, startingAt: track)
            } label: {
                AlbumTrackRow(
                    track: track,
                    showsArtist: album.isCompilation || track.artistName.localizedCaseInsensitiveCompare(album.artistName) != .orderedSame,
                    isCurrent: playback.isCurrent(track)
                )
            }
            .buttonStyle(.plain)
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

/// A row on an album page: number, title, duration.
struct AlbumTrackRow: View {
    let track: Track
    let showsArtist: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isCurrent {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(Text("Now playing"))
                } else {
                    Text(track.trackNumber.map(String.init) ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body.monospacedDigit())
            .frame(minWidth: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                if showsArtist {
                    Text(track.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(MusicFormat.duration(track.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(track.isAvailable ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(track.isAvailable ? "" : "Not available"))
    }
}
