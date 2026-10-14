import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// A show's page, as in the TV app and Netflix: the show's picture fills the
/// page behind the title, what it's about and one button that carries on
/// where you left off ("Resume S1, E5", "Play S1, E6" or "Play First
/// Episode"); then a season menu over a row of wide episode cards that starts
/// at the episode you're up to, the cast, and the details.
public struct ShowDetailView: View {
    @Environment(LibraryManager.self) private var library
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var selectedSeason: Int?
    @State private var scrollOffset: CGFloat = 0
    private let show: TVShow
    private let focusing: Video?

    /// - Parameter focusing: An episode whose season should show first.
    public init(show: TVShow, focusing: Video? = nil) {
        self.show = show
        self.focusing = focusing
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
        let next = library.nextUp(in: show)
        let hasStarted = show.episodes.contains { library.watchState(for: $0)?.lastPlayedDate != nil }
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ShowHero(show: show, next: next, hasStarted: hasStarted, seasonCount: seasons.count { $0.number > 0 }, isCompact: isCompact)
                        .frame(minHeight: max(proxy.size.height * 0.74, isCompact ? 480 : 540), alignment: .bottom)
                    VStack(alignment: .leading, spacing: 34) {
                        if isCompact {
                            ShowSummary(show: show)
                        }
                        if let season {
                            SeasonEpisodesSection(
                                seasons: seasons,
                                season: season,
                                selectedSeason: $selectedSeason,
                                upNext: hasStarted ? next : nil,
                                isCompact: isCompact
                            )
                        }
                        if !show.cast.isEmpty {
                            CastShelf(cast: show.cast)
                        }
                        ShowAboutSection(show: show, seasonCount: seasons.count { $0.number > 0 })
                    }
                    .padding(.horizontal, isCompact ? Metrics.contentPadding : 48)
                    .padding(.top, 30)
                    .padding(.bottom, 48)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .background {
                DetailBackdrop(
                    url: library.artworkURL(wideArtworkKey(next: next), .large),
                    fallbackURL: library.artworkURL(show.posterArtworkKey, .large),
                    dimming: min(max(scrollOffset / 420, 0), 1)
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.colorScheme, .dark)
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
                selectedSeason = focusing?.seasonNumber ?? next?.video.seasonNumber ?? seasons.first?.number
            }
        }
    }

    /// The show's backdrop, else a still of the episode you're up to (or the
    /// first). Without either, the poster is shown blurred.
    private func wideArtworkKey(next: (video: Video, isResume: Bool)?) -> String? {
        show.backdropKey ?? next?.video.stillArtworkKey ?? show.orderedEpisodes.first?.stillArtworkKey
    }
}

// MARK: - Header

/// The top of a show's page, over the page's picture: title, synopsis,
/// badges and the button that carries on watching.
struct ShowHero: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    let show: TVShow
    let next: (video: Video, isResume: Bool)?
    let hasStarted: Bool
    let seasonCount: Int
    let isCompact: Bool
    @State private var showsFullOverview = false

    var body: some View {
        Group {
            if isCompact {
                compactDetails
            } else {
                wideDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wideDetails: some View {
        HStack(alignment: .bottom, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                HeroTitle(show.title, size: 64)
                Text(kindLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if let overview = show.overview {
                    overviewView(overview)
                }
                HStack(spacing: 10) {
                    if !infoLine.isEmpty {
                        Text(infoLine)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    VideoBadges(file: badgeFile)
                        .environment(\.colorScheme, .dark)
                }
                buttons
                    .padding(.top, 4)
            }
            .frame(maxWidth: 640, alignment: .leading)
            Spacer(minLength: 0)
            if let starring {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Starring")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(starring)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 48)
        .padding(.bottom, 12)
    }

    private var compactDetails: some View {
        VStack(spacing: 10) {
            HeroTitle(show.title, size: 44, alignment: .center)
            Text(kindLine)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            VideoBadges(file: badgeFile)
                .environment(\.colorScheme, .dark)
            buttons
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.contentPadding)
        .padding(.bottom, 8)
    }

    private func overviewView(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overview)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(3)
            if overview.count > 200 {
                Button("More") {
                    showsFullOverview = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .popover(isPresented: $showsFullOverview) {
                    OverviewPopover(title: show.title, text: overview)
                }
            }
        }
        .frame(maxWidth: 580, alignment: .leading)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if let next {
                let state = library.watchState(for: next.video)
                Button {
                    VideoPlayback(library: library, session: session, actions: actions).play(next.video)
                } label: {
                    Label(ShowPlayTitle.title(for: next, hasStarted: hasStarted), systemImage: "play.fill")
                        .frame(minWidth: isCompact ? 170 : 0)
                }
                .buttonStyle(HeroPlayButtonStyle(progress: state?.progress))
                .disabled(!next.video.isAvailable)
                if !isCompact, let remaining = state?.remaining {
                    Text(VideoFormat.remaining(remaining))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            let isOnList = library.isOnWatchlist(show)
            HeroCircleButton(isOnList ? "Remove from Watchlist" : "Add to Watchlist", systemImage: isOnList ? "checkmark" : "plus") {
                library.toggleWatchlist(show)
            }
        }
    }

    private var kindLine: String {
        var parts = ["TV Show"]
        if !show.genres.isEmpty {
            parts.append(show.genres.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var infoLine: String {
        var parts: [String] = []
        if let year = show.year { parts.append(String(year)) }
        if seasonCount > 0 { parts.append(seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons") }
        if let rating = show.contentRating { parts.append(rating) }
        if let network = show.network { parts.append(network) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var starring: String? {
        let names = show.cast.prefix(3).map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// The badges of the episode you'd play next (or the first).
    private var badgeFile: MediaFile? {
        next?.video.file ?? show.orderedEpisodes.first?.file
    }
}

/// The whole synopsis, from "More".
struct OverviewPopover: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.bold())
                Text(text)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .frame(idealWidth: 460, maxWidth: 520, maxHeight: 440)
        .presentationCompactAdaptation(.sheet)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// On the iPhone the synopsis and cast sit under the header.
private struct ShowSummary: View {
    let show: TVShow
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let overview = show.overview {
                Text(overview)
                    .font(.callout)
                    .lineLimit(isExpanded ? nil : 4)
                if overview.count > 180 {
                    Button(isExpanded ? "Less" : "More") {
                        withAnimation(Motion.quick) {
                            isExpanded.toggle()
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            let names = show.cast.prefix(3).map(\.name)
            if !names.isEmpty {
                Text("Starring \(names.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Episodes

/// The season menu, then the season's episodes as wide cards in a row that
/// opens at the episode you're up to.
struct SeasonEpisodesSection: View {
    @Environment(LibraryManager.self) private var library
    let seasons: [Season]
    let season: Season
    @Binding var selectedSeason: Int?
    /// The episode to continue with, highlighted and scrolled to.
    let upNext: (video: Video, isResume: Bool)?
    let isCompact: Bool

    private var cardWidth: CGFloat {
        isCompact ? 280 : 340
    }

    var body: some View {
        let episodes = season.orderedEpisodes
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                seasonTitle
                Text(episodes.count == 1 ? "1 Episode" : "\(episodes.count) Episodes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                    .lineLimit(3)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(episodes) { episode in
                            EpisodeCard(episode: episode, width: cardWidth, highlight: highlight(for: episode))
                                .id(episode.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .task(id: ScrollTarget(season: season.number, episode: upNext?.video.id)) {
                    guard let target = upNext?.video, episodes.contains(where: { $0.id == target.id }) else { return }
                    // Let the row lay out first.
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.4)) {
                        proxy.scrollTo(target.id, anchor: .leading)
                    }
                }
            }
        }
    }

    private struct ScrollTarget: Hashable {
        var season: Int
        var episode: UUID?
    }

    @ViewBuilder
    private var seasonTitle: some View {
        if seasons.count > 1 {
            Menu {
                Picker("Season", selection: Binding(get: { season.number }, set: { selectedSeason = $0 })) {
                    ForEach(seasons) { season in
                        Text(season.displayTitle).tag(season.number)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(season.displayTitle)
                        .font(.title2.bold())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Season"))
            .accessibilityValue(Text(season.displayTitle))
        } else {
            Text(season.displayTitle)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func highlight(for episode: Video) -> String? {
        guard let upNext, upNext.video.id == episode.id else { return nil }
        return upNext.isResume ? "Continue" : "Up Next"
    }
}

/// A wide episode card: the still (with progress), the number, title,
/// synopsis, a play line and a menu.
struct EpisodeCard: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    let episode: Video
    let width: CGFloat
    /// "Continue" or "Up Next" on the episode you're up to.
    let highlight: String?

    var body: some View {
        let state = library.watchState(for: episode)
        let playback = VideoPlayback(library: library, session: session, actions: actions)
        VStack(alignment: .leading, spacing: 10) {
            Button {
                playback.play(episode)
            } label: {
                still(state)
            }
            .buttonStyle(.plain)
            .disabled(!episode.isAvailable)
            .accessibilityLabel(Text("Play \(episode.displayTitle)"))

            VStack(alignment: .leading, spacing: 3) {
                Text(numberLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(episode.overview ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
            }

            HStack(spacing: 10) {
                Button {
                    playback.play(episode)
                } label: {
                    Label(playLine(state), systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!episode.isAvailable)
                if state?.isWatched == true {
                    Label("Watched", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    VideoMenuItems(video: episode, showsGoToShow: false)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("More for \(episode.displayTitle)"))
            }
            .foregroundStyle(.primary)
        }
        .frame(width: width, alignment: .leading)
        .opacity(episode.isAvailable ? 1 : 0.5)
        .contextMenu {
            VideoMenuItems(video: episode, showsGoToShow: false)
        }
    }

    private func still(_ state: WatchState?) -> some View {
        ArtworkView(url: library.artworkURL(episode.stillArtworkKey, .large), shape: .still, maxPixelSize: 720, placeholderSymbol: "tv")
            .overlay(alignment: .bottom) {
                if let progress = state?.progress {
                    StillProgressBar(progress: progress)
                }
            }
            .overlay(alignment: .topTrailing) {
                if state?.isWatched == true {
                    WatchedMark().padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if let highlight {
                    Text(highlight)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .overlay {
                if highlight != nil {
                    RoundedRectangle(cornerRadius: ArtworkShape.still.cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .artworkShadow(isProminent: false)
    }

    private var numberLine: String {
        guard let number = episode.episodeNumber else { return "Episode" }
        if episode.seasonNumber == 0 {
            return "Special \(number)"
        }
        if let last = episode.lastEpisodeNumber, last > number {
            return "Episodes \(number)\u{2013}\(last)"
        }
        return "Episode \(number)"
    }

    private func playLine(_ state: WatchState?) -> String {
        if let remaining = state?.remaining {
            return VideoFormat.remaining(remaining)
        }
        return VideoFormat.runtime(episode.duration) ?? "Play"
    }
}

// MARK: - About

/// The full synopsis and the show's details.
private struct ShowAboutSection: View {
    let show: TVShow
    let seasonCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let overview = show.overview {
                Text(overview)
                    .frame(maxWidth: 760, alignment: .leading)
                    .textSelection(.enabled)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(row.1)
                            .textSelection(.enabled)
                    }
                    .font(.callout)
                }
            }
            if let credit = MetadataCredit.forShow(show) {
                MetadataCreditView(credit: credit)
            }
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if !show.genres.isEmpty {
            rows.append(("Genre", show.genres.joined(separator: ", ")))
        }
        if let year = show.year {
            rows.append(("First Aired", String(year)))
        }
        if let network = show.network {
            rows.append(("Network", network))
        }
        if seasonCount > 0 {
            rows.append(("Seasons", String(seasonCount)))
        }
        rows.append(("Episodes", String(show.episodes.count)))
        if let rating = show.contentRating {
            rows.append(("Rated", rating))
        }
        if let score = show.rating {
            rows.append(("Rating", String(format: "%.1f / 10", score)))
        }
        return rows
    }
}
