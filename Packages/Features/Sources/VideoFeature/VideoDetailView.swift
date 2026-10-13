import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// A movie's (or home video's) page, as in the TV app: the backdrop with the
/// title over it, Play or Resume, badges, the synopsis, cast and details.
public struct VideoDetailView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    @Environment(\.videoSheets) private var sheets
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    private let video: Video

    public init(video: Video) {
        self.video = video
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
        let state = library.watchState(for: video)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(state)
                VStack(alignment: .leading, spacing: 24) {
                    if let tagline = video.tagline {
                        Text(tagline)
                            .font(.title3.italic())
                            .foregroundStyle(.secondary)
                    }
                    if let overview = video.overview {
                        Text(overview)
                            .font(.body)
                            .frame(maxWidth: 760, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if !video.cast.isEmpty {
                        CastShelf(cast: video.cast)
                    }
                    VideoDetailsSection(video: video)
                }
                .padding(Metrics.contentPadding)
                .padding(.top, 8)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(video.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    VideoMenuItems(video: video)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    // MARK: Hero

    private func hero(_ state: WatchState?) -> some View {
        let height: CGFloat = isCompact ? 420 : 520
        return ZStack(alignment: .bottomLeading) {
            HeroBackdrop(imageURL: library.artworkURL(video.backdropArtworkKey ?? video.posterArtworkKey, .large), height: height)
            HStack(alignment: .bottom, spacing: 24) {
                if !isCompact, video.kind == .movie {
                    poster
                        .frame(width: 180)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(video.displayTitle)
                        .font(.largeTitle.bold())
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    if let line = infoLine, !line.isEmpty {
                        Text(line)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    VideoBadges(file: video.file)
                        .environment(\.colorScheme, .dark)
                    buttons(state)
                        .padding(.top, 6)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(Metrics.contentPadding)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let url = library.artworkURL(video.posterArtworkKey, .large) {
            ArtworkView(url: url, shape: .poster, maxPixelSize: 600)
                .artworkShadow()
        } else {
            GeneratedPoster(imageURL: library.artworkURL(video.stillArtworkKey, .grid), title: video.displayTitle, subtitle: video.year.map(String.init))
                .artworkShadow()
        }
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
                    .frame(minWidth: 110)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!video.isAvailable)

            if state?.isInProgress == true {
                Button {
                    playback.play(video, fromStart: true)
                } label: {
                    Label("Play from Beginning", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help("Play from Beginning")
            }

            Button {
                if state?.isWatched == true {
                    library.markUnwatched([video])
                } else {
                    library.markWatched([video])
                }
            } label: {
                Label(state?.isWatched == true ? "Watched" : "Mark as Watched", systemImage: state?.isWatched == true ? "checkmark.circle.fill" : "checkmark.circle")
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .help(state?.isWatched == true ? "Mark as Unwatched" : "Mark as Watched")

            if let remaining = state?.remaining {
                Text(VideoFormat.remaining(remaining))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
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
            if video.matchState == .matched || video.matchState == .manual {
                Text("Details and artwork from TMDB.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
