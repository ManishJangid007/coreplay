import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// A show's page, as in the TV app: the backdrop and title, a button for
/// the episode to watch next, seasons, and each season's episodes with their
/// stills and watched state.
public struct ShowDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var selectedSeason: Int?
    private let show: TVShow
    private let focusing: Video?

    /// - Parameter focusing: An episode whose season should show first.
    public init(show: TVShow, focusing: Video? = nil) {
        self.show = show
        self.focusing = focusing
    }

    private var playback: VideoPlayback {
        VideoPlayback(library: library, session: session, actions: actions)
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    public var body: some View {
        let seasons = show.orderedSeasons.filter { !$0.episodes.isEmpty }
        let season = seasons.first { $0.number == selectedSeason } ?? seasons.first
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(seasonCount: seasons.count { $0.number > 0 })
                VStack(alignment: .leading, spacing: 22) {
                    if let overview = show.overview {
                        Text(overview)
                            .frame(maxWidth: 760, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if seasons.count > 1 {
                        seasonPicker(seasons, selected: season?.number)
                    }
                    if let season {
                        SeasonEpisodes(season: season, isCompact: isCompact)
                    }
                    if !show.cast.isEmpty {
                        CastShelf(cast: show.cast)
                    }
                    if let credit = MetadataCredit.forShow(show) {
                        MetadataCreditView(credit: credit)
                    }
                }
                .padding(Metrics.contentPadding)
                .padding(.top, 8)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(show.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShowMenuItems(show: show)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .onAppear {
            if selectedSeason == nil {
                selectedSeason = focusing?.seasonNumber ?? library.nextUp(in: show)?.video.seasonNumber ?? seasons.first?.number
            }
        }
    }

    private func hero(seasonCount: Int) -> some View {
        let next = library.nextUp(in: show)
        return ZStack(alignment: .bottomLeading) {
            HeroBackdrop(imageURL: library.artworkURL(show.backdropKey ?? show.posterArtworkKey, .large), height: isCompact ? 400 : 500)
            VStack(alignment: .leading, spacing: 10) {
                Text(show.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(infoLine(seasonCount: seasonCount))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                if let next {
                    HStack(spacing: 12) {
                        Button {
                            playback.play(next.video)
                        } label: {
                            Label(buttonTitle(next), systemImage: "play.fill")
                                .frame(minWidth: 130)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        if let remaining = library.watchState(for: next.video)?.remaining {
                            Text(VideoFormat.remaining(remaining))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .foregroundStyle(.white)
            .padding(Metrics.contentPadding)
            .padding(.bottom, 8)
        }
    }

    private func buttonTitle(_ next: (video: Video, isResume: Bool)) -> String {
        let label = next.video.episodeLabel ?? ""
        return next.isResume ? "Resume \(label)" : "Play \(label)"
    }

    private func infoLine(seasonCount: Int) -> String {
        var parts: [String] = []
        if let year = show.year { parts.append(String(year)) }
        if !show.genres.isEmpty { parts.append(show.genres.prefix(2).joined(separator: ", ")) }
        if let rating = show.contentRating { parts.append(rating) }
        if seasonCount > 0 { parts.append(seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons") }
        if let network = show.network { parts.append(network) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func seasonPicker(_ seasons: [Season], selected: Int?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seasons) { season in
                    let isSelected = season.number == selected
                    Button {
                        withAnimation(Motion.quick) {
                            selectedSeason = season.number
                        }
                    } label: {
                        Text(season.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary), in: Capsule())
                            .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// A season's episodes: still, number, title, synopsis, progress.
private struct SeasonEpisodes: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    let season: Season
    let isCompact: Bool

    var body: some View {
        let episodes = season.orderedEpisodes
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(season.displayTitle)
                    .font(.title2.bold())
                Spacer()
                Menu {
                    Button("Mark Season as Watched", systemImage: "checkmark.circle") { library.markWatched(episodes) }
                    Button("Mark Season as Unwatched", systemImage: "eye.slash") { library.markUnwatched(episodes) }
                } label: {
                    Label("Season Options", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if let overview = season.overview {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(episodes) { episode in
                    Button {
                        VideoPlayback(library: library, session: session, actions: actions).play(episode)
                    } label: {
                        EpisodeRow(episode: episode, stillWidth: isCompact ? 150 : 240)
                    }
                    .buttonStyle(.plain)
                    .disabled(!episode.isAvailable)
                    .contextMenu {
                        VideoMenuItems(video: episode, showsGoToShow: false)
                    }
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    @Environment(LibraryManager.self) private var library
    let episode: Video
    let stillWidth: CGFloat

    var body: some View {
        let state = library.watchState(for: episode)
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(url: library.artworkURL(episode.stillArtworkKey, .large), shape: .still, maxPixelSize: 640, placeholderSymbol: "tv")
                .overlay(alignment: .bottom) {
                    if let progress = state?.progress {
                        StillProgressBar(progress: progress)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if state?.isWatched == true {
                        WatchedMark().padding(5)
                    }
                }
                .frame(width: stillWidth)
                .artworkShadow(isProminent: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(numberLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let overview = episode.overview {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let detail = detailLine(state) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .opacity(episode.isAvailable ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(state?.isWatched == true ? "Watched" : ""))
    }

    private var numberLine: String {
        guard let number = episode.episodeNumber else { return "Episode" }
        if let last = episode.lastEpisodeNumber, last > number {
            return "Episodes \(number)\u{2013}\(last)"
        }
        return "Episode \(number)"
    }

    private func detailLine(_ state: WatchState?) -> String? {
        var parts: [String] = []
        if let remaining = state?.remaining {
            parts.append(VideoFormat.remaining(remaining))
        } else if let runtime = VideoFormat.runtime(episode.duration) {
            parts.append(runtime)
        }
        if let aired = episode.releaseDate {
            parts.append(aired)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}
