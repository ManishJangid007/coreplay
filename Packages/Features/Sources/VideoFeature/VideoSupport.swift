import DesignSystem
import MediaLibrary
import MusicFeature
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Plays library videos the way the TV app does: resume where you stopped,
/// and episodes carry on into the next one.
@MainActor
struct VideoPlayback {
    let library: LibraryManager
    let session: PlaybackSession
    let actions: AppActions

    func play(_ video: Video, fromStart: Bool = false) {
        let items = library.playbackItems(startingWith: video, fromStart: fromStart)
        guard !items.isEmpty else { return }
        Task {
            await session.play(items, startingAt: 0, shuffled: false)
        }
        actions.showPlayer()
    }

    func play(_ show: TVShow) {
        guard let next = library.nextUp(in: show) else { return }
        play(next.video)
    }
}

extension View {
    /// Registers movie, show and home video pages for a navigation stack.
    public func videoDestinations() -> some View {
        navigationDestination(for: Video.self) { video in
            VideoDestination(video: video)
        }
        .navigationDestination(for: TVShow.self) { show in
            ShowDetailView(show: show)
        }
    }

    /// Every library page: music and video.
    public func libraryDestinations() -> some View {
        musicDestinations()
            .videoDestinations()
            .videoSheets()
    }
}

/// Episodes open on their show's page; movies and home videos on their own.
private struct VideoDestination: View {
    let video: Video

    var body: some View {
        if video.kind == .episode, let show = video.show {
            ShowDetailView(show: show, focusing: video)
        } else {
            VideoDetailView(video: video)
        }
    }
}

// MARK: - Sheets

/// Edit Info, Fix Match and Choose Artwork, presented from anywhere a video
/// or show appears.
public enum VideoSheet: Identifiable {
    case editVideo(Video)
    case fixVideo(Video)
    case videoArtwork(Video)
    case editShow(TVShow)
    case fixShow(TVShow)
    case showArtwork(TVShow)

    public var id: String {
        switch self {
        case .editVideo(let video): "edit-\(video.id)"
        case .fixVideo(let video): "fix-\(video.id)"
        case .videoArtwork(let video): "art-\(video.id)"
        case .editShow(let show): "edit-show-\(show.id)"
        case .fixShow(let show): "fix-show-\(show.id)"
        case .showArtwork(let show): "art-show-\(show.id)"
        }
    }
}

/// Presents `VideoSheet`s for the views below it (see `videoSheets()`).
@MainActor
@Observable
public final class VideoSheetController {
    public var sheet: VideoSheet?

    public init() {}

    public func present(_ sheet: VideoSheet) {
        self.sheet = sheet
    }
}

extension EnvironmentValues {
    @Entry public var videoSheets: VideoSheetController? = nil
}

private struct VideoSheetsModifier: ViewModifier {
    @State private var controller = VideoSheetController()

    func body(content: Content) -> some View {
        @Bindable var controller = controller
        content
            .environment(\.videoSheets, controller)
            .sheet(item: $controller.sheet) { sheet in
                switch sheet {
                case .editVideo(let video): VideoInfoEditor(video: video)
                case .fixVideo(let video): FixMatchView(target: .video(video))
                case .videoArtwork(let video): ArtworkPickerView(target: .video(video))
                case .editShow(let show): ShowInfoEditor(show: show)
                case .fixShow(let show): FixMatchView(target: .show(show))
                case .showArtwork(let show): ArtworkPickerView(target: .show(show))
                }
            }
    }
}

extension View {
    /// Lets the views inside present Edit Info, Fix Match and Choose Artwork.
    public func videoSheets() -> some View {
        modifier(VideoSheetsModifier())
    }
}

// MARK: - Cells

/// A 2:3 poster with a title underneath, as in the TV app's grids.
struct PosterCell: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    /// A frame or backdrop for a made-up poster when there's no real one.
    let fallbackURL: URL?
    var progress: Double?
    var isWatched = false
    var symbol = "film"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let artworkURL {
                    ArtworkView(url: artworkURL, shape: .poster, maxPixelSize: 520, placeholderSymbol: symbol)
                } else {
                    GeneratedPoster(imageURL: fallbackURL, title: title, subtitle: subtitle, symbol: symbol)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    StillProgressBar(progress: progress)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    WatchedMark().padding(6)
                }
            }
            .artworkShadow(isProminent: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isWatched ? "Watched" : ""))
    }
}

/// A 16:9 still with its progress, title and a detail line.
struct StillCell: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    var progress: Double?
    var isWatched = false
    var corner: String?
    var symbol = "play.rectangle"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: artworkURL, shape: .still, maxPixelSize: 720, placeholderSymbol: symbol)
                .overlay(alignment: .bottom) {
                    if let progress {
                        StillProgressBar(progress: progress)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isWatched {
                        WatchedMark().padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if progress == nil, let corner {
                        Text(corner)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .artworkShadow(isProminent: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isWatched ? "Watched" : ""))
    }
}

/// A movie's poster cell, with watched state.
struct MoviePosterCell: View {
    @Environment(LibraryManager.self) private var library
    let video: Video

    var body: some View {
        let state = library.watchState(for: video)
        PosterCell(
            title: video.displayTitle,
            subtitle: video.year.map(String.init),
            artworkURL: library.artworkURL(video.posterArtworkKey, .grid),
            fallbackURL: library.artworkURL(video.stillArtworkKey, .grid),
            progress: state?.progress,
            isWatched: state?.isWatched ?? false
        )
        .opacity(video.isAvailable ? 1 : 0.5)
    }
}

/// A show's poster cell.
struct ShowPosterCell: View {
    @Environment(LibraryManager.self) private var library
    let show: TVShow

    var body: some View {
        PosterCell(
            title: show.title,
            subtitle: VideoFormat.seasonCount(show) ?? show.year.map(String.init),
            artworkURL: library.artworkURL(show.posterArtworkKey, .grid),
            fallbackURL: library.artworkURL(show.backdropKey ?? show.orderedEpisodes.first?.stillArtworkKey, .grid),
            symbol: "tv"
        )
    }
}

/// A video as a 16:9 still: Continue Watching, Up Next, home videos.
struct VideoStillCell: View {
    @Environment(LibraryManager.self) private var library
    let video: Video
    /// Show the show's name above the episode, as Home's rows do.
    var showsShowName = true

    var body: some View {
        let state = library.watchState(for: video)
        StillCell(
            title: title,
            subtitle: subtitle(state),
            artworkURL: library.artworkURL(video.stillArtworkKey ?? video.posterArtworkKey, .large),
            progress: state?.progress,
            isWatched: state?.isWatched ?? false,
            corner: VideoFormat.shortDuration(video.duration),
            symbol: video.kind == .homeVideo ? "video" : "play.rectangle"
        )
        .opacity(video.isAvailable ? 1 : 0.5)
    }

    private var title: String {
        if video.kind == .episode, showsShowName, let show = video.showTitle {
            return show
        }
        return video.displayTitle
    }

    private func subtitle(_ state: WatchState?) -> String? {
        if let remaining = state?.remaining {
            let left = VideoFormat.remaining(remaining)
            if video.kind == .episode, showsShowName, let label = video.episodeLabel {
                return "\(label) \u{00B7} \(left)"
            }
            return left
        }
        switch video.kind {
        case .episode:
            if showsShowName {
                return [video.episodeLabel, video.title.isEmpty ? nil : video.title].compactMap { $0 }.joined(separator: " \u{00B7} ")
            }
            return video.episodeLabel
        case .movie:
            return video.year.map(String.init)
        case .homeVideo:
            return video.file?.recordedDate?.formatted(date: .abbreviated, time: .omitted)
                ?? video.dateAdded.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - Badges

/// 4K, HDR, Dolby Vision, Dolby Atmos, 5.1 and CC, as the TV app shows them.
struct VideoBadges: View {
    let file: MediaFile?

    var body: some View {
        if let file {
            HStack(spacing: 6) {
                if let resolution = file.resolutionBadge {
                    MediaBadge(resolution)
                }
                if let range = file.dynamicRange?.badge {
                    MediaBadge(range)
                }
                if file.hasAtmos {
                    MediaBadge("Dolby Atmos")
                } else if let channels = file.channels, channels >= 6 {
                    MediaBadge(channels >= 8 ? "7.1" : "5.1")
                }
                if file.hasSDHSubtitles {
                    MediaBadge("SDH")
                } else if file.hasSubtitles {
                    MediaBadge("CC")
                }
            }
        }
    }
}

// MARK: - Menus

/// Play, watched state, and the editing sheets, for any video.
struct VideoMenuItems: View {
    let video: Video
    var showsGoToShow = true
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @Environment(\.videoSheets) private var sheets

    var body: some View {
        let playback = VideoPlayback(library: library, session: session, actions: actions)
        let state = library.watchState(for: video)
        if state?.isInProgress == true {
            Button("Resume", systemImage: "play.fill") { playback.play(video) }
            Button("Play from Beginning", systemImage: "arrow.counterclockwise") { playback.play(video, fromStart: true) }
        } else {
            Button("Play", systemImage: "play.fill") { playback.play(video) }
        }
        Divider()
        if state?.isWatched == true {
            Button("Mark as Unwatched", systemImage: "eye.slash") { library.markUnwatched([video]) }
        } else {
            Button("Mark as Watched", systemImage: "checkmark.circle") { library.markWatched([video]) }
        }
        if video.kind == .movie {
            if library.isOnWatchlist(video) {
                Button("Remove from Watchlist", systemImage: "minus.circle") { library.toggleWatchlist(video) }
            } else {
                Button("Add to Watchlist", systemImage: "plus.circle") { library.toggleWatchlist(video) }
            }
        }
        if showsGoToShow, video.kind == .episode, let show = video.show {
            NavigationLink(value: show) {
                Label("Go to Show", systemImage: "tv")
            }
        }
        Divider()
        Button("Edit Info\u{2026}", systemImage: "pencil") { sheets?.present(.editVideo(video)) }
        Button("Choose Artwork\u{2026}", systemImage: "photo") { sheets?.present(.videoArtwork(video)) }
        if video.kind != .homeVideo, library.hasMetadataKey {
            Button("Fix Match\u{2026}", systemImage: "magnifyingglass") {
                if video.kind == .episode, let show = video.show {
                    sheets?.present(.fixShow(show))
                } else {
                    sheets?.present(.fixVideo(video))
                }
            }
            Button("Look Up Again", systemImage: "arrow.clockwise") { library.lookUpAgain(video) }
        }
        #if os(macOS)
        if let file = video.file, let url = library.url(for: file) {
            Divider()
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        #endif
    }
}

/// Watched state and editing for a whole show.
struct ShowMenuItems: View {
    let show: TVShow
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @Environment(\.videoSheets) private var sheets

    var body: some View {
        let playback = VideoPlayback(library: library, session: session, actions: actions)
        Button("Play", systemImage: "play.fill") { playback.play(show) }
        Divider()
        if library.isOnWatchlist(show) {
            Button("Remove from Watchlist", systemImage: "minus.circle") { library.toggleWatchlist(show) }
        } else {
            Button("Add to Watchlist", systemImage: "plus.circle") { library.toggleWatchlist(show) }
        }
        Button("Mark Show as Watched", systemImage: "checkmark.circle") { library.markWatched(show.episodes) }
        Button("Mark Show as Unwatched", systemImage: "eye.slash") { library.markUnwatched(show.episodes) }
        Divider()
        Button("Edit Info\u{2026}", systemImage: "pencil") { sheets?.present(.editShow(show)) }
        Button("Choose Artwork\u{2026}", systemImage: "photo") { sheets?.present(.showArtwork(show)) }
        if library.hasMetadataKey {
            Button("Fix Match\u{2026}", systemImage: "magnifyingglass") { sheets?.present(.fixShow(show)) }
            Button("Look Up Again", systemImage: "arrow.clockwise") { library.lookUpAgain(show) }
        }
    }
}

// MARK: - Formatting

enum VideoFormat {
    /// "2 hr 12 min", "47 min".
    static func runtime(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds >= 60 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return rest > 0 ? "\(hours) hr \(rest) min" : "\(hours) hr"
        }
        return "\(minutes) min"
    }

    /// "1:42:10" on still corners.
    static func shortDuration(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return PlaybackTimeFormatter.string(from: seconds, referenceDuration: seconds)
    }

    /// "1 hr 12 min left".
    static func remaining(_ seconds: TimeInterval) -> String {
        "\(runtime(max(seconds, 60)) ?? "1 min") left"
    }

    static func seasonCount(_ show: TVShow) -> String? {
        let count = show.seasons.count { $0.number > 0 }
        guard count > 0 else { return nil }
        return count == 1 ? "1 Season" : "\(count) Seasons"
    }

    /// "2019 · 2 hr 12 min · PG-13".
    static func movieLine(_ video: Video) -> String {
        var parts: [String] = []
        if let year = video.year { parts.append(String(year)) }
        if let runtime = runtime(video.duration) { parts.append(runtime) }
        if let rating = video.contentRating { parts.append(rating) }
        if !video.genres.isEmpty { parts.append(video.genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func languages(_ codes: String?) -> String? {
        guard let codes, !codes.isEmpty else { return nil }
        let names = codes.split(separator: ",").map { code in
            Locale.current.localizedString(forLanguageCode: String(code)) ?? String(code)
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
}

// MARK: - Credits

/// Where a page's details came from, as their licences ask.
enum MetadataCredit: Equatable {
    case tmdb
    case wikipedia
    case tvmaze

    static func forVideo(_ video: Video) -> MetadataCredit? {
        switch video.matchState {
        case .matched, .manual:
            if video.tmdbID != nil { return .tmdb }
            return video.kind == .episode ? .tvmaze : .wikipedia
        case .keyless:
            return video.kind == .episode ? .tvmaze : .wikipedia
        case .pending, .notFound, .local:
            return nil
        }
    }

    static func forShow(_ show: TVShow) -> MetadataCredit? {
        switch show.matchState {
        case .matched, .manual:
            return show.tmdbID != nil ? .tmdb : .tvmaze
        case .keyless:
            return .tvmaze
        case .pending, .notFound, .local:
            return nil
        }
    }
}

struct MetadataCreditView: View {
    let credit: MetadataCredit

    var body: some View {
        switch credit {
        case .tmdb:
            Text("Details and artwork from TMDB.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .wikipedia:
            Text("Details and poster from [Wikipedia](https://en.wikipedia.org), shared under CC BY-SA.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .tint(.secondary)
        case .tvmaze:
            Text("Details and artwork from [TVmaze](https://www.tvmaze.com), shared under CC BY-SA.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .tint(.secondary)
        }
    }
}
