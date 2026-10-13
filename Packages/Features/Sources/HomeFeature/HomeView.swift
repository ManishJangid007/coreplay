import DesignSystem
import MediaLibrary
import MusicFeature
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftData
import SwiftUI
import VideoFeature

/// Home: Apple TV's "Watch Now" plus Apple Music's "Listen Now".
///
/// The hero carousel of movies and shows, what's playing, Continue Watching,
/// Up Next and the watchlist, then Recently Played music and what was added
/// recently.
public struct HomeView: View {
    @Environment(PlaybackSession.self) private var session
    @Environment(LibraryManager.self) private var library
    @Environment(\.appActions) private var actions
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(HomeView.recentlyAdded) private var recentlyAdded: [Album]
    @Query(HomeView.anyVideo) private var anyVideo: [Video]
    @State private var recentlyPlayed: [Album] = []

    private static var recentlyAdded: FetchDescriptor<Album> {
        var descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\Album.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 16
        return descriptor
    }

    private static var anyVideo: FetchDescriptor<Video> {
        var descriptor = FetchDescriptor<Video>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    public init() {}

    private var heroStyle: HeroCarousel.Style {
        #if os(iOS)
        HeroCarousel.Style.forWidth(isCompact: sizeClass == .compact)
        #else
        .fullBleed
        #endif
    }

    private var showsHero: Bool {
        !anyVideo.isEmpty
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsHero {
                    HeroCarousel(content: .everything, style: heroStyle)
                }
                VStack(alignment: .leading, spacing: 30) {
                    if let item = session.currentItem {
                        NowPlayingCard(item: item, controller: session.controller) {
                            actions.showPlayer()
                        }
                        .frame(maxWidth: 900, alignment: .leading)
                    }
                    WatchNowRows()
                    WatchlistRow()
                    if !recentlyPlayed.isEmpty {
                        AlbumShelf(title: "Recently Played", albums: recentlyPlayed)
                    }
                    RecentlyAddedVideoRows()
                    if !recentlyAdded.isEmpty {
                        AlbumShelf(title: "Recently Added Music", albums: recentlyAdded)
                    }
                    if recentlyAdded.isEmpty, anyVideo.isEmpty {
                        welcome
                            .frame(maxWidth: 900, alignment: .leading)
                    }
                }
                .padding(Metrics.contentPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .heroPageChrome(showsHero && heroStyle == .fullBleed)
        .navigationTitle("Home")
        .task(id: library.revision) {
            recentlyPlayed = library.recentlyPlayedAlbums()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    actions.openFiles()
                } label: {
                    Label("Open Files", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    actions.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                BrandLogo(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Brand.appName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("Play Anything")
                        .font(.title2.bold())
                }
            }
            Text("Open movies, shows, music or home videos in any format VLC supports, including MKV, AVI, FLAC and Opus, with every subtitle and audio track.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    actions.addLibraryFolder()
                } label: {
                    Label("Add Folder\u{2026}", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    actions.openFiles()
                } label: {
                    Label("Open Files\u{2026}", systemImage: "doc")
                }
                .buttonStyle(.bordered)
            }
            Text(addFolderHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private let addFolderHint: String = {
    #if os(macOS)
    return "Add a folder to build your library, or drop files onto this window to play them straight away."
    #else
    return "Add a folder to build your library, or open single files to play them straight away. Files you put in Coreplay\u{2019}s folder in the Files app appear automatically."
    #endif
}()

/// A horizontal row of albums, as on Music's Home.
private struct AlbumShelf: View {
    let title: String
    let albums: [Album]

    var body: some View {
        Shelf(title) {
            ForEach(albums) { album in
                NavigationLink(value: album) {
                    AlbumCell(album: album)
                        .frame(width: 160)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A large card for whatever is currently loaded, with its progress.
private struct NowPlayingCard: View {
    let item: PlaybackItem
    let controller: PlaybackController
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                ArtworkView(
                    data: controller.metadata.artworkData,
                    shape: controller.hasVideo ? .still : .square,
                    maxPixelSize: 400
                )
                .frame(width: controller.hasVideo ? 160 : 90)
                .artworkShadow(isProminent: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.isPlaying ? "Now Playing" : "Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(controller.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let duration = controller.duration, duration > 0 {
                        ProgressView(value: min(controller.currentTime / duration, 1))
                            .tint(.primary)
                        Text(PlaybackTimeFormatter.string(from: max(0, duration - controller.currentTime), referenceDuration: duration) + " left")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the player"))
    }
}
