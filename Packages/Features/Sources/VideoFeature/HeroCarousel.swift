import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// The big carousel at the top of Home, Movies and TV Shows, as in the TV app
/// and Netflix: full-bleed artwork, the title, what it is, a synopsis, Play
/// (or Resume) and "+" for the watchlist. It moves on by itself; once a
/// movie's page settles, a short silent clip from the movie's own file plays
/// behind the title.
///
/// On the iPhone it's a tall card under the large title; on the iPad and the
/// Mac it fills the width, under the toolbar (see `heroPageChrome(_:)`).
public struct HeroCarousel: View {
    public enum Content: Hashable, Sendable {
        /// Movies and shows (and, in a library with little else, home videos).
        case everything
        case movies
        case shows
    }

    public enum Style: Hashable, Sendable {
        /// Edge to edge, under the toolbar: iPad and Mac.
        case fullBleed
        /// A tall card with margins: iPhone.
        case card
    }

    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PlaybackPreferences.playsPreviewsKey) private var playsPreviews = true
    @State private var slides: [HeroSlide]
    @State private var hasLoaded: Bool
    @State private var currentID: String?
    @State private var width: CGFloat
    @State private var isHovering = false
    @State private var isOnScreen = true

    private let content: Content
    private let style: Style
    private let rebuildsSlides: Bool
    private let preview = HeroPreviewPlayer.shared

    public init(content: Content, style: Style) {
        self.content = content
        self.style = style
        self.rebuildsSlides = true
        _slides = State(initialValue: [])
        _hasLoaded = State(initialValue: false)
        _width = State(initialValue: 0)
    }

    /// Fixed slides, for snapshots.
    init(slides: [HeroSlide], style: Style, width: CGFloat) {
        self.content = .everything
        self.style = style
        self.rebuildsSlides = false
        _slides = State(initialValue: slides)
        _hasLoaded = State(initialValue: true)
        _currentID = State(initialValue: slides.first?.id)
        _width = State(initialValue: width)
    }

    /// The carousel's height at a given width.
    static func height(for width: CGFloat, style: Style) -> CGFloat {
        switch style {
        case .fullBleed: min(max(width * 0.5, 460), 720)
        case .card: min(max((width - 2 * Metrics.contentPadding) * 1.25, 380), 580)
        }
    }

    public var body: some View {
        Group {
            if !hasLoaded {
                // The artwork's space, held while the slides are worked out.
                Color.black.opacity(style == .fullBleed ? 0.85 : 0)
                    .frame(height: Self.height(for: width, style: style))
                    .heroBottomFade()
            } else if slides.isEmpty {
                Color.clear.frame(height: 0)
            } else {
                carousel
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .task(id: RebuildKey(revision: library.revision, content: content)) {
            guard rebuildsSlides else { return }
            rebuild()
        }
    }

    private struct RebuildKey: Hashable {
        var revision: Int
        var content: Content
    }

    private func rebuild() {
        let built = HeroSlideBuilder.slides(for: content, library: library)
        slides = built
        hasLoaded = true
        if currentID == nil || !built.contains(where: { $0.id == currentID }) {
            currentID = built.first?.id
        }
    }

    // MARK: - Carousel

    private var currentIndex: Int {
        slides.firstIndex { $0.id == currentID } ?? 0
    }

    private var carousel: some View {
        ZStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(slides) { slide in
                        HeroPage(slide: slide, style: style, isCurrent: slide.id == currentID, preview: preview)
                            .containerRelativeFrame(.horizontal)
                            .id(slide.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)

            if style == .fullBleed, slides.count > 1 {
                chevrons
            }
        }
        .frame(height: Self.height(for: width, style: style))
        .overlay(alignment: .bottom) {
            if slides.count > 1 {
                PageDots(count: slides.count, index: currentIndex) { page in
                    show(page)
                }
                .padding(.bottom, dotsBottomPadding)
            }
        }
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .onScrollVisibilityChange(threshold: 0.4) { isOnScreen = $0 }
        .task(id: AdvanceKey(
            currentID: currentID,
            isPaused: isHovering || !isOnScreen || scenePhase != .active,
            previewSlide: preview.slideID,
            finishedSlide: preview.finishedSlideID
        )) {
            await advanceWhenDue()
        }
        .task(id: PreviewKey(currentID: currentID, isAllowed: canPreview)) {
            await previewWhenSettled()
        }
        .onChange(of: currentID) { old, _ in
            if let old {
                preview.stop(slideID: old)
            }
        }
        .onDisappear {
            preview.stop()
        }
    }

    private var dotsBottomPadding: CGFloat {
        switch style {
        case .fullBleed: Self.height(for: width, style: style) * 0.12 + 4
        case .card: 14
        }
    }

    private var chevrons: some View {
        HStack {
            GlassIconButton("Previous", systemImage: "chevron.backward") { step(by: -1) }
            Spacer()
            GlassIconButton("Next", systemImage: "chevron.forward") { step(by: 1) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .opacity(showsChevrons ? 1 : 0)
        .allowsHitTesting(showsChevrons)
        .animation(.easeInOut(duration: 0.2), value: showsChevrons)
    }

    private var showsChevrons: Bool {
        #if os(macOS)
        isHovering
        #else
        true
        #endif
    }

    private func step(by offset: Int) {
        guard !slides.isEmpty else { return }
        show((currentIndex + offset + slides.count) % slides.count)
    }

    private func show(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.6)) {
            currentID = slides[index].id
        }
    }

    // MARK: - Moving on and previews

    private struct AdvanceKey: Hashable {
        var currentID: String?
        var isPaused: Bool
        var previewSlide: String?
        var finishedSlide: String?
    }

    /// Nine seconds a page; a page playing a clip waits for it to finish.
    /// With Reduce Motion on, pages only change when asked.
    private func advanceWhenDue() async {
        guard slides.count > 1, rebuildsSlides, !reduceMotion, !isHovering, isOnScreen, scenePhase == .active else { return }
        let isPreviewing = preview.slideID != nil && preview.slideID == currentID
        let hasFinished = preview.finishedSlideID != nil && preview.finishedSlideID == currentID
        if isPreviewing, !hasFinished { return }
        try? await Task.sleep(for: hasFinished ? .seconds(3) : .seconds(9))
        guard !Task.isCancelled else { return }
        step(by: 1)
    }

    private struct PreviewKey: Hashable {
        var currentID: String?
        var isAllowed: Bool
    }

    private var canPreview: Bool {
        guard rebuildsSlides, playsPreviews, isOnScreen, scenePhase == .active, !session.controller.isPlaying else { return false }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return false }
        #if os(iOS)
        // Settings ▸ Accessibility ▸ Motion ▸ Auto-Play Video Previews.
        return UIAccessibility.isVideoAutoplayEnabled
        #else
        return true
        #endif
    }

    private func previewWhenSettled() async {
        guard canPreview, let id = currentID, let slide = slides.first(where: { $0.id == id }), let video = slide.previewVideo else {
            preview.stop()
            return
        }
        // Already playing (or finished) this page's clip.
        if preview.slideID == id { return }
        try? await Task.sleep(for: .seconds(1.6))
        guard !Task.isCancelled else { return }
        preview.start(video, slideID: id, library: library, session: session)
    }
}

// MARK: - Page

/// One page of the carousel.
struct HeroPage: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    let slide: HeroSlide
    let style: HeroCarousel.Style
    let isCurrent: Bool
    let preview: HeroPreviewPlayer
    /// Snapshots draw the page without its navigation link.
    var linksToDetails = true

    private var isPreviewing: Bool {
        isCurrent && preview.slideID == slide.id
    }

    var body: some View {
        switch style {
        case .fullBleed: wide
        case .card: card
        }
    }

    // MARK: Layouts

    private var wide: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .bottomLeading) {
                openLink {
                    artwork
                        .overlay { HeroScrim(.wide) }
                        .heroBottomFade()
                }
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let badge = slide.badge {
                            HeroBadge(badge)
                        }
                        HeroTitle(slide.title, size: min(max(proxy.size.width * 0.05, 44), 72))
                        Text(slide.kindLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        if let overview = slide.overview {
                            Text(overview)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(3)
                                .frame(maxWidth: 560, alignment: .leading)
                        }
                    }
                    .allowsHitTesting(false)
                    buttons
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.leading, proxy.size.width > 900 ? 56 : 32)
                .padding(.bottom, height * 0.12 + 40)
            }
            .overlay(alignment: .bottomTrailing) {
                muteButton
                    .padding(.trailing, proxy.size.width > 900 ? 56 : 32)
                    .padding(.bottom, height * 0.12 + 40)
            }
        }
    }

    private var card: some View {
        ZStack(alignment: .bottom) {
            openLink {
                artwork
                    .overlay { HeroScrim(.card) }
            }
            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    if let badge = slide.badge {
                        HeroBadge(badge)
                    }
                    HeroTitle(slide.title, size: 40, alignment: .center)
                    Text(slide.kindLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .allowsHitTesting(false)
                buttons
                    .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            muteButton.padding(12)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .padding(.horizontal, Metrics.contentPadding)
    }

    // MARK: Pieces

    private var artwork: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.24), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            FilledArtwork(url: slide.artworkURL, maxPixelSize: 2_000)
            if isPreviewing {
                VideoSurface(controller: preview.controller)
                    .opacity(preview.isShowingVideo ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: preview.isShowingVideo)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
    }

    /// The whole page opens the movie's or show's page.
    @ViewBuilder
    private func openLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if !linksToDetails {
            label()
        } else {
            link(label: label)
        }
    }

    @ViewBuilder
    private func link<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        switch slide.target {
        case .movie(let video), .homeVideo(let video):
            NavigationLink(value: video, label: label)
                .buttonStyle(.plain)
                .accessibilityLabel(Text(slide.title))
                .accessibilityHint(Text("Shows details"))
        case .show(let show):
            NavigationLink(value: show, label: label)
                .buttonStyle(.plain)
                .accessibilityLabel(Text(slide.title))
                .accessibilityHint(Text("Shows the episodes"))
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if let play = slide.play {
                Button {
                    preview.stop()
                    VideoPlayback(library: library, session: session, actions: actions).play(play.video)
                } label: {
                    Label(play.title, systemImage: "play.fill")
                        .frame(minWidth: style == .card ? 150 : 0)
                }
                .buttonStyle(HeroPlayButtonStyle(progress: play.progress))
                .disabled(!play.video.isAvailable)
            }
            watchlistButton
            if style == .fullBleed, let remaining = slide.play?.remaining {
                Text(VideoFormat.remaining(remaining))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var watchlistButton: some View {
        switch slide.target {
        case .movie(let video):
            let isOnList = library.isOnWatchlist(video)
            HeroCircleButton(isOnList ? "Remove from Watchlist" : "Add to Watchlist", systemImage: isOnList ? "checkmark" : "plus") {
                library.toggleWatchlist(video)
            }
        case .show(let show):
            let isOnList = library.isOnWatchlist(show)
            HeroCircleButton(isOnList ? "Remove from Watchlist" : "Add to Watchlist", systemImage: isOnList ? "checkmark" : "plus") {
                library.toggleWatchlist(show)
            }
        case .homeVideo:
            EmptyView()
        }
    }

    @ViewBuilder
    private var muteButton: some View {
        if isPreviewing, preview.isShowingVideo {
            HeroCircleButton(preview.isMuted ? "Unmute" : "Mute", systemImage: preview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                preview.setMuted(!preview.isMuted, session: session)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Slides

/// What one page of the carousel shows.
struct HeroSlide: Identifiable {
    enum Target {
        case movie(Video)
        case show(TVShow)
        case homeVideo(Video)
    }

    /// What the Play button plays.
    struct Play {
        let video: Video
        let title: String
        let progress: Double?
        let remaining: TimeInterval?
    }

    let id: String
    let target: Target
    let title: String
    /// "New" or "New Episodes".
    let badge: String?
    /// "Movie · Drama, Thriller · 2019 · 2 hr 12 min".
    let kindLine: String
    let overview: String?
    let artworkURL: URL?
    let play: Play?
    /// The video whose clip plays behind the title (movies and home videos).
    let previewVideo: Video?
}

/// Builds the carousel's slides from the library with `FeaturedPicker`.
@MainActor
enum HeroSlideBuilder {
    static let limit = 8

    static func slides(for content: HeroCarousel.Content, library: LibraryManager, now: Date = .now) -> [HeroSlide] {
        var movies: [String: Video] = [:]
        var shows: [String: TVShow] = [:]
        var candidates: [FeaturedPicker.Candidate] = []

        if content != .shows {
            for movie in recentVideos(of: .movie, library: library, limit: 300) where movie.isAvailable {
                let id = "movie:\(movie.id.uuidString)"
                let state = library.watchState(for: movie)
                movies[id] = movie
                candidates.append(FeaturedPicker.Candidate(
                    id: id,
                    dateAdded: movie.dateAdded,
                    lastPlayed: state?.lastPlayedDate,
                    isInProgress: state?.isInProgress ?? false,
                    isFinished: state?.isWatched ?? false,
                    hasBackdrop: movie.backdropKey != nil,
                    hasArtwork: movie.backdropArtworkKey != nil || movie.posterArtworkKey != nil
                ))
            }
        }
        if content != .movies {
            for show in recentShows(library: library, limit: 200) {
                let episodes = show.episodes.filter(\.isAvailable)
                guard !episodes.isEmpty else { continue }
                let id = "show:\(show.id.uuidString)"
                let states = episodes.compactMap { library.watchState(for: $0) }
                shows[id] = show
                candidates.append(FeaturedPicker.Candidate(
                    id: id,
                    dateAdded: episodes.map(\.dateAdded).max() ?? show.dateAdded,
                    lastPlayed: states.compactMap(\.lastPlayedDate).max(),
                    isInProgress: states.contains(where: \.isInProgress),
                    isFinished: states.count(where: \.isWatched) == episodes.count,
                    hasBackdrop: show.backdropKey != nil,
                    hasArtwork: show.backdropKey != nil || show.posterArtworkKey != nil || episodes.contains { $0.stillArtworkKey != nil }
                ))
            }
        }

        var slides = FeaturedPicker.pick(candidates, limit: limit, now: now).compactMap { id -> HeroSlide? in
            if let movie = movies[id] {
                return movieSlide(movie, id: id, library: library, now: now)
            }
            if let show = shows[id] {
                return showSlide(show, id: id, library: library, now: now)
            }
            return nil
        }
        if content == .everything, slides.count < 3 {
            // A library of mostly home videos still gets a carousel.
            for video in recentVideos(of: .homeVideo, library: library, limit: 3 - slides.count) where video.isAvailable {
                slides.append(homeVideoSlide(video, library: library))
            }
        }
        return slides
    }

    static func movieSlide(_ movie: Video, id: String, library: LibraryManager, now: Date) -> HeroSlide {
        let state = library.watchState(for: movie)
        return HeroSlide(
            id: id,
            target: .movie(movie),
            title: movie.displayTitle,
            badge: FeaturedPicker.isNew(movie.dateAdded, now: now) && state == nil ? "New" : nil,
            kindLine: line(["Movie", genres(movie.genres), movie.year.map(String.init), VideoFormat.runtime(movie.duration)]),
            overview: movie.overview ?? movie.tagline,
            artworkURL: library.artworkURL(movie.backdropArtworkKey ?? movie.posterArtworkKey, .large),
            play: HeroSlide.Play(
                video: movie,
                title: state?.isInProgress == true ? "Resume" : "Play",
                progress: state?.progress,
                remaining: state?.remaining
            ),
            previewVideo: movie
        )
    }

    static func showSlide(_ show: TVShow, id: String, library: LibraryManager, now: Date) -> HeroSlide {
        let next = library.nextUp(in: show)
        let states = show.episodes.compactMap { library.watchState(for: $0) }
        let lastPlayed = states.compactMap(\.lastPlayedDate).max()
        let newest = show.episodes.map(\.dateAdded).max() ?? show.dateAdded
        var badge: String?
        if FeaturedPicker.isNew(newest, now: now) {
            if let lastPlayed {
                badge = newest > lastPlayed ? "New Episodes" : nil
            } else {
                badge = "New"
            }
        }
        var play: HeroSlide.Play?
        if let next {
            let state = library.watchState(for: next.video)
            play = HeroSlide.Play(
                video: next.video,
                title: ShowPlayTitle.title(for: next, hasStarted: lastPlayed != nil),
                progress: state?.progress,
                remaining: state?.remaining
            )
        }
        let artworkKey = show.backdropKey
            ?? next?.video.stillArtworkKey
            ?? show.posterArtworkKey
            ?? show.orderedEpisodes.first?.stillArtworkKey
        return HeroSlide(
            id: id,
            target: .show(show),
            title: show.title,
            badge: badge,
            kindLine: line(["TV Show", genres(show.genres), VideoFormat.seasonCount(show), show.contentRating]),
            overview: show.overview,
            artworkURL: library.artworkURL(artworkKey, .large),
            play: play,
            previewVideo: nil
        )
    }

    static func homeVideoSlide(_ video: Video, library: LibraryManager) -> HeroSlide {
        let state = library.watchState(for: video)
        let date = (video.file?.recordedDate ?? video.dateAdded).formatted(date: .long, time: .omitted)
        return HeroSlide(
            id: "home:\(video.id.uuidString)",
            target: .homeVideo(video),
            title: video.displayTitle,
            badge: nil,
            kindLine: line(["Home Video", date, VideoFormat.runtime(video.duration)]),
            overview: nil,
            artworkURL: library.artworkURL(video.stillArtworkKey ?? video.posterArtworkKey, .large),
            play: HeroSlide.Play(
                video: video,
                title: state?.isInProgress == true ? "Resume" : "Play",
                progress: state?.progress,
                remaining: state?.remaining
            ),
            previewVideo: video
        )
    }

    private static func recentVideos(of kind: VideoKind, library: LibraryManager, limit: Int) -> [Video] {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<Video>(
            predicate: #Predicate { $0.kindRaw == kindRaw },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? library.context.fetch(descriptor)) ?? []
    }

    private static func recentShows(library: LibraryManager, limit: Int) -> [TVShow] {
        var descriptor = FetchDescriptor<TVShow>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? library.context.fetch(descriptor)) ?? []
    }

    private static func genres(_ genres: [String]) -> String? {
        genres.isEmpty ? nil : genres.prefix(2).joined(separator: ", ")
    }

    private static func line(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

/// "Resume S1, E5", "Play S1, E6" or "Play First Episode", for a show's
/// main button.
enum ShowPlayTitle {
    static func title(for next: (video: Video, isResume: Bool), hasStarted: Bool) -> String {
        let label = next.video.episodeLabel ?? ""
        if next.isResume {
            return label.isEmpty ? "Resume" : "Resume \(label)"
        }
        if !hasStarted {
            return "Play First Episode"
        }
        return label.isEmpty ? "Play" : "Play \(label)"
    }
}

// MARK: - Preview clips

/// Plays the hero carousel's silent clips in a second, chrome-less
/// controller (see `PlaybackController.Purpose.preview`). One for the whole
/// app, so only one clip ever plays.
@MainActor
@Observable
final class HeroPreviewPlayer {
    static let shared = HeroPreviewPlayer()

    /// How long a clip plays before the picture fades back to the artwork.
    static let clipLength: TimeInterval = 30

    let controller = PlaybackController(purpose: .preview)
    /// The page whose clip is loaded (playing, or finished and faded out).
    private(set) var slideID: String?
    /// Frames are on screen, so the video can fade in over the artwork.
    private(set) var isShowingVideo = false
    /// The page whose clip has played to its end.
    private(set) var finishedSlideID: String?
    private(set) var isMuted = true

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var clipStart: TimeInterval = 0
    @ObservationIgnored private var clipEnd: TimeInterval = 0

    private init() {
        controller.setFillMode(.fill)
        controller.setMuted(true)
    }

    /// Where a clip starts: about a sixth of the way in, past the opening
    /// credits and well before anything gets spoiled. Short videos play from the start.
    nonisolated static func clipStart(duration: TimeInterval?) -> TimeInterval {
        guard let duration, duration.isFinite, duration > 0 else { return 120 }
        if duration < 180 { return 0 }
        return min(max(duration * 0.18, 60), duration - 90)
    }

    func start(_ video: Video, slideID: String, library: LibraryManager, session: PlaybackSession) {
        guard var item = library.playbackItem(for: video, fromStart: true) else { return }
        let start = Self.clipStart(duration: video.duration)
        item.startPosition = start > 0 ? start : nil
        item.externalSubtitleURLs = []
        item.playsAudio = !isMuted
        clipStart = start
        clipEnd = start + Self.clipLength

        generation += 1
        let current = generation
        self.slideID = slideID
        finishedSlideID = nil
        isShowingVideo = false
        session.preparePreviewAudio()
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            self.controller.setMuted(self.isMuted)
            self.controller.setFillMode(.fill)
            await self.controller.load(item)
            await self.watch(generation: current)
        }
    }

    /// Stops the clip. With `slideID`, only if that page's clip is the one loaded.
    func stop(slideID: String? = nil) {
        if let slideID, slideID != self.slideID { return }
        guard self.slideID != nil || task != nil else { return }
        generation += 1
        task?.cancel()
        task = nil
        isShowingVideo = false
        self.slideID = nil
        finishedSlideID = nil
        let controller = controller
        Task { await controller.stop() }
    }

    func setMuted(_ muted: Bool, session: PlaybackSession) {
        isMuted = muted
        guard !muted, controller.activeEngine == .vlc, var item = controller.currentItem, !item.playsAudio else {
            controller.setMuted(muted)
            return
        }
        // VLC opened no audio output for the silent clip: reopen it with
        // sound where it is.
        session.preparePreviewAudio()
        item.playsAudio = true
        item.startPosition = controller.currentTime
        let current = generation
        isShowingVideo = false
        task?.cancel()
        controller.setMuted(false)
        task = Task { [weak self] in
            guard let self else { return }
            await self.controller.load(item)
            await self.watch(generation: current)
        }
    }

    /// Fades the video in once frames arrive, and out at the end of the clip.
    private func watch(generation current: Int) async {
        while !Task.isCancelled, current == generation {
            let state = controller.state
            if state.error != nil || state == .ended {
                finish(current)
                return
            }
            let time = controller.currentTime
            if !isShowingVideo, state == .playing, controller.hasVideo, time >= clipStart + 0.25 {
                isShowingVideo = true
            }
            if time >= clipEnd {
                finish(current)
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func finish(_ current: Int) {
        guard current == generation else { return }
        isShowingVideo = false
        finishedSlideID = slideID
        let controller = controller
        Task { [weak self] in
            // Let the picture fade out before the player goes.
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, current == self.generation else { return }
            await controller.stop()
        }
    }
}

// MARK: - Page chrome

extension View {
    /// A page that starts with a full-width hero runs it under the toolbar.
    public func heroPageChrome(_ isActive: Bool) -> some View {
        modifier(HeroPageChrome(isActive: isActive))
    }
}

private struct HeroPageChrome: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .ignoresSafeArea(edges: .top)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                #endif
        } else {
            content
        }
    }
}

extension HeroCarousel.Style {
    /// Full width on the iPad and the Mac; a card on the iPhone.
    public static func forWidth(isCompact: Bool) -> HeroCarousel.Style {
        isCompact ? .card : .fullBleed
    }
}
