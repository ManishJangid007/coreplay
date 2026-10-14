import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// A movie's (or home video's) page, as Netflix and the TV app show them:
/// the picture fills the whole page behind everything, and the title, what
/// it is, Play or Resume, the synopsis and who's in it sit over it. The cast
/// and the details follow as the page scrolls, over the darkened picture.
public struct VideoDetailView: View {
    @Environment(LibraryManager.self) private var library
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var scrollOffset: CGFloat = 0
    private let video: Video

    public init(video: Video) {
        self.video = video
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var sidePadding: CGFloat {
        isCompact ? Metrics.contentPadding : 48
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VideoDetailHeader(video: video, isCompact: isCompact, sidePadding: sidePadding)
                        .frame(minHeight: max(proxy.size.height * 0.8, isCompact ? 520 : 560), alignment: .bottomLeading)
                    VStack(alignment: .leading, spacing: 30) {
                        if !video.cast.isEmpty {
                            CastShelf(cast: video.cast)
                        }
                        VideoDetailsSection(video: video)
                    }
                    .padding(.horizontal, sidePadding)
                    .padding(.top, 34)
                    .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .background {
                DetailBackdrop(
                    url: library.artworkURL(Self.wideArtworkKey(video), .large),
                    fallbackURL: library.artworkURL(video.posterArtworkKey, .large),
                    dimming: min(max(scrollOffset / 420, 0), 1)
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.colorScheme, .dark)
        .navigationTitle(video.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }

    /// A wide picture for the page: a backdrop, the chosen artwork, a still
    /// or a frame. Without one, the poster is shown blurred.
    static func wideArtworkKey(_ video: Video) -> String? {
        video.backdropKey ?? video.customArtworkKey ?? video.stillKey ?? video.thumbnailKey
    }
}

/// The words and buttons over a movie's picture: what it is, the title, a
/// line of details, badges, Play or Resume and the other actions, the
/// synopsis and who's in it.
struct VideoDetailHeader: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @State private var showsFullOverview = false
    let video: Video
    let isCompact: Bool
    let sidePadding: CGFloat

    private var playback: VideoPlayback {
        VideoPlayback(library: library, session: session, actions: actions)
    }

    var body: some View {
        let state = library.watchState(for: video)
        VStack(alignment: .leading, spacing: 14) {
            Text(video.kind == .homeVideo ? "Home Video" : "Movie")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.7))
            HeroTitle(video.displayTitle, size: isCompact ? 44 : 66)
            if let line = infoLine, !line.isEmpty {
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            VideoBadges(file: video.file)
            buttons(state)
                .padding(.vertical, 4)
            if let overview = video.overview ?? video.tagline {
                overviewText(overview)
            }
            credits
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 680, alignment: .leading)
        .padding(.horizontal, sidePadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoLine: String? {
        switch video.kind {
        case .homeVideo:
            var parts: [String] = []
            if let date = video.file?.recordedDate {
                parts.append(date.formatted(date: .long, time: .shortened))
            }
            if let runtime = VideoFormat.runtime(video.duration) {
                parts.append(runtime)
            }
            return parts.joined(separator: " \u{00B7} ")
        default:
            return VideoFormat.movieLine(video)
        }
    }

    private func buttons(_ state: WatchState?) -> some View {
        HStack(spacing: 12) {
            Button {
                playback.play(video)
            } label: {
                Label(state?.isInProgress == true ? "Resume" : "Play", systemImage: "play.fill")
                    .frame(minWidth: isCompact ? 120 : 96)
            }
            .buttonStyle(HeroPlayButtonStyle(progress: state?.progress))
            .disabled(!video.isAvailable)

            if state?.isInProgress == true {
                HeroCircleButton("Play from Beginning", systemImage: "arrow.counterclockwise") {
                    playback.play(video, fromStart: true)
                }
            }
            if video.kind == .movie {
                let isOnList = library.isOnWatchlist(video)
                HeroCircleButton(isOnList ? "Remove from Watchlist" : "Add to Watchlist", systemImage: isOnList ? "checkmark" : "plus") {
                    library.toggleWatchlist(video)
                }
            }
            let isWatched = state?.isWatched == true
            HeroCircleButton(isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: isWatched ? "eye.slash" : "eye") {
                if isWatched {
                    library.markUnwatched([video])
                } else {
                    library.markWatched([video])
                }
            }
            Menu {
                VideoMenuItems(video: video)
            } label: {
                HeroCircleLabel(systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More"))

            if !isCompact, let remaining = state?.remaining {
                Text(VideoFormat.remaining(remaining))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func overviewText(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overview)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
            if overview.count > 240 {
                Button("More") {
                    showsFullOverview = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.bold))
                .popover(isPresented: $showsFullOverview) {
                    OverviewPopover(title: video.displayTitle, text: overview)
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    @ViewBuilder
    private var credits: some View {
        let names = video.cast.prefix(4).map(\.name)
        if !names.isEmpty || !video.directors.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if !names.isEmpty {
                    Text("Starring \(names.joined(separator: ", "))")
                }
                if !video.directors.isEmpty {
                    Text("\(video.directors.count == 1 ? "Director" : "Directors") \(video.directors.joined(separator: ", "))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(2)
        }
    }
}

/// The picture behind a detail page, filling it: shaded on the left for the
/// words, darkening towards the bottom for the rows below, and further as
/// the page scrolls (`dimming`, 0 to 1).
struct DetailBackdrop: View {
    /// A wide picture.
    let url: URL?
    /// Shown blurred when there's no wide picture (a poster).
    let fallbackURL: URL?
    var dimming: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
            if let url {
                FilledArtwork(url: url, maxPixelSize: 2_000)
            } else if let fallbackURL {
                FilledArtwork(url: fallbackURL, maxPixelSize: 500)
                    .blur(radius: 40, opaque: true)
                    .opacity(0.9)
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.8), location: 0),
                    .init(color: .black.opacity(0.45), location: 0.45),
                    .init(color: .clear, location: 0.8),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.4), location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.85), location: 0.8),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Color.black.opacity(0.7 * dimming)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The people in a movie or show, with their photos.
struct CastShelf: View {
    let cast: [CastMember]

    var body: some View {
        Shelf("Cast & Crew") {
            ForEach(cast) { person in
                VStack(spacing: 6) {
                    ArtworkView(url: person.imageURL, shape: .square, maxPixelSize: 240, placeholderSymbol: "person.fill")
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())
                    VStack(spacing: 1) {
                        Text(person.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        if let role = person.role {
                            Text(role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(width: 104)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Information about the release and the file, like the TV app's "Information" section.
struct VideoDetailsSection: View {
    @Environment(LibraryManager.self) private var library
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.title2.bold())
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
            if let credit = MetadataCredit.forVideo(video) {
                MetadataCreditView(credit: credit)
            }
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if let original = video.originalTitle, original != video.title {
            rows.append(("Original Title", original))
        }
        if !video.genres.isEmpty {
            rows.append(("Genre", video.genres.joined(separator: ", ")))
        }
        if let released = video.releaseDate {
            rows.append((video.kind == .episode ? "Aired" : "Released", released))
        }
        if !video.directors.isEmpty {
            rows.append((video.directors.count == 1 ? "Director" : "Directors", video.directors.joined(separator: ", ")))
        }
        if let studio = video.studio {
            rows.append(("Studio", studio))
        }
        if let edition = video.edition {
            rows.append(("Edition", edition))
        }
        if let rating = video.rating {
            rows.append(("Rating", String(format: "%.1f / 10", rating)))
        }
        if let file = video.file {
            if let date = file.recordedDate, video.kind == .homeVideo {
                rows.append(("Recorded", date.formatted(date: .complete, time: .shortened)))
            }
            var picture: [String] = []
            if let width = file.width, let height = file.height { picture.append("\(width) \u{00D7} \(height)") }
            if let codec = file.videoCodec { picture.append(codec) }
            if let rate = file.frameRate { picture.append(String(format: "%g fps", rate)) }
            if let range = file.dynamicRange?.badge { picture.append(range) }
            if !picture.isEmpty { rows.append(("Video", picture.joined(separator: ", "))) }
            var sound: [String] = []
            if let codec = file.audioCodec { sound.append(codec) }
            if let channels = file.channels { sound.append(channels >= 8 ? "7.1" : channels >= 6 ? "5.1" : channels == 1 ? "Mono" : "Stereo") }
            if file.hasAtmos { sound.append("Dolby Atmos") }
            if !sound.isEmpty { rows.append(("Audio", sound.joined(separator: ", "))) }
            if let languages = VideoFormat.languages(file.audioLanguages) { rows.append(("Languages", languages)) }
            if let subtitles = VideoFormat.languages(file.subtitleLanguages) { rows.append(("Subtitles", subtitles)) }
            rows.append(("File", file.fileName))
            rows.append(("Size", VideoFormat.fileSize(file.fileSize)))
            if !file.isAvailable {
                rows.append(("Status", "Not available \u{2014} connect the drive it\u{2019}s on"))
            }
        }
        return rows
    }
}
