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

/// The big carousel at the top of Home, Movies, TV Shows and Albums, as in
/// the TV app and Netflix: full artwork, the title, what it is, a synopsis,
/// Play (or Resume) and "+" for the watchlist. It moves on by itself every
/// few seconds; once a movie's page settles, a short silent clip from the
/// movie's own file plays behind the title. Albums get Music's look: the
/// cover, sharp, over a blur of itself.
///
/// Only the current page is drawn. Pages cross-fade (the details slide in),
/// so changing page is smooth however large the artwork is. The clip plays
/// in one surface for the whole carousel, which stays on screen until its
/// player has stopped: a video output must never lose its view while it's
/// still drawing.
public struct HeroCarousel: View {
    public enum Content: Hashable, Sendable {
        /// Movies and shows, a couple of albums, and (in a library with
        /// little else) home videos: Home.
        case everything
        case movies
        case shows
        case music
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
    @State private var index = 0
    @State private var movesForward = true
    @State private var width: CGFloat
    @State private var isHovering = false
    @State private var isOnScreen = true
    /// How far a sideways swipe has gone: the words follow the finger.
    @GestureState(resetTransaction: Transaction(animation: .smooth(duration: 0.35))) private var dragOffset: CGFloat = 0

    private let content: Content
    private let style: Style
    private let isLive: Bool
    private let preview = HeroPreviewPlayer.shared

    public init(content: Content, style: Style) {
        self.content = content
        self.style = style
        self.isLive = true
        _slides = State(initialValue: [])
        _hasLoaded = State(initialValue: false)
        _width = State(initialValue: 0)
    }

    /// Fixed slides that never move on or play clips, for snapshots.
    init(slides: [HeroSlide], style: Style, width: CGFloat) {
        self.content = .everything
        self.style = style
        self.isLive = false
        _slides = State(initialValue: slides)
        _hasLoaded = State(initialValue: true)
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
            guard isLive else { return }
            rebuild()
        }
    }

    private struct RebuildKey: Hashable {
        var revision: Int
        var content: Content
    }

    private func rebuild() {
        let previousID = slides.indices.contains(index) ? slides[index].id : nil
        let built = HeroSlideBuilder.slides(for: content, library: library)
        slides = built
        hasLoaded = true
        index = previousID.flatMap { id in built.firstIndex { $0.id == id } } ?? 0
    }

    private var current: HeroSlide {
        slides[min(max(index, 0), slides.count - 1)]
    }

    // MARK: - Layout

    private var carousel: some View {
        let height = Self.height(for: width, style: style)
        let slide = current
        return Group {
            switch style {
            case .fullBleed: wide(slide, height: height)
            case .card: card(slide, height: height)
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            if slides.count > 1 {
                PageDots(count: slides.count, index: index) { page in
                    show(page)
                }
                .padding(.bottom, style == .fullBleed ? height * 0.12 + 4 : 14)
            }
        }
        .overlay {
            if style == .fullBleed, slides.count > 1 {
                chevrons
            }
        }
        .simultaneousGesture(swipe)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .onScrollVisibilityChange(threshold: 0.4) { isOnScreen = $0 }
        .task(id: AdvanceKey(index: index, isPaused: isPaused, clip: preview.phase(for: slide.id))) {
            await advanceWhenDue()
        }
        .task(id: PreviewKey(slideID: slide.id, isAllowed: canPreview)) {
            await previewWhenSettled()
        }
        .task(id: slides.map(\.id)) {
            await prefetchArtwork()
        }
        .onDisappear {
            preview.stop()
        }
    }

    private func wide(_ slide: HeroSlide, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                Color.black
                HeroBackground(slide: slide, style: .fullBleed)
                    .id(slide.id)
                    .transition(.opacity)
                previewLayer(for: slide)
                HeroScrim(.wide)
            }
            .heroBottomFade()
            .clipped()
            openLink(for: slide)
            HeroDetails(slide: slide, style: .fullBleed, width: width, height: height)
                .modifier(FollowsSwipe(offset: dragOffset))
                .id(slide.id)
                .transition(detailsTransition)
        }
        .overlay(alignment: .bottomTrailing) {
            muteButton(for: slide)
                .padding(.trailing, width > 900 ? 56 : 32)
                .padding(.bottom, height * 0.12 + 40)
        }
    }

    private func card(_ slide: HeroSlide, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Color.black
                HeroBackground(slide: slide, style: .card)
                    .id(slide.id)
                    .transition(.opacity)
                previewLayer(for: slide)
                HeroScrim(.card)
            }
            openLink(for: slide)
            HeroDetails(slide: slide, style: .card, width: width, height: height)
                .modifier(FollowsSwipe(offset: dragOffset))
                .id(slide.id)
                .transition(detailsTransition)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            muteButton(for: slide)
                .padding(12)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .padding(.horizontal, Metrics.contentPadding)
    }

    private var detailsTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: movesForward ? 40 : -40)),
            removal: .opacity
        )
    }

    /// The clip, for whichever page it belongs to. It stays in place while
    /// its player winds down, faded out.
    @ViewBuilder
    private func previewLayer(for slide: HeroSlide) -> some View {
        if preview.isMounted {
            VideoSurface(controller: preview.controller)
                .opacity(preview.isShowingVideo && preview.slideID == slide.id ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: preview.isShowingVideo)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The artwork opens the movie's, show's or album's page.
    @ViewBuilder
    private func openLink(for slide: HeroSlide) -> some View {
        let area = Color.clear.contentShape(Rectangle())
        if isLive {
            switch slide.target {
            case .movie(let video), .homeVideo(let video):
                NavigationLink(value: video) { area }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(slide.title))
                    .accessibilityHint(Text("Shows details"))
            case .show(let show):
                NavigationLink(value: show) { area }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(slide.title))
                    .accessibilityHint(Text("Shows the episodes"))
            case .album(let album):
                NavigationLink(value: album) { area }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(slide.title))
                    .accessibilityHint(Text("Shows the album"))
            }
        }
    }

    @ViewBuilder
    private func muteButton(for slide: HeroSlide) -> some View {
        if preview.isShowingVideo, preview.slideID == slide.id {
            HeroCircleButton(preview.isMuted ? "Unmute" : "Mute", systemImage: preview.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                preview.setMuted(!preview.isMuted, session: session)
            }
            .transition(.opacity)
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

    // MARK: - Changing page

    /// A sideways swipe (or drag) changes page; vertical scrolling goes on.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($dragOffset) { value, offset, _ in
                let across = value.translation.width
                guard slides.count > 1, abs(across) > abs(value.translation.height) else { return }
                offset = across
            }
            .onEnded { value in
                let across = value.translation.width
                guard abs(across) > 60, abs(across) > abs(value.translation.height) * 1.4 else { return }
                step(by: across < 0 ? 1 : -1)
            }
    }

    private func step(by offset: Int) {
        guard slides.count > 1 else { return }
        show((index + offset + slides.count) % slides.count, forward: offset > 0)
    }

    private func show(_ newIndex: Int, forward: Bool? = nil) {
        guard slides.indices.contains(newIndex), newIndex != index else { return }
        let leaving = current.id
        movesForward = forward ?? (newIndex > index)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.7)) {
            index = newIndex
        }
        preview.stop(slideID: leaving)
    }

    // MARK: - Moving on

    private struct AdvanceKey: Hashable {
        var index: Int
        var isPaused: Bool
        var clip: HeroPreviewPlayer.ClipPhase
    }

    /// Off screen, in the background, with Reduce Motion, while a video
    /// plays, or in snapshots, pages only change when asked.
    private var isPaused: Bool {
        !isLive || reduceMotion || !isOnScreen || scenePhase != .active || isWatchingVideo
    }

    /// A video is playing in the player (which covers the carousel on the Mac).
    private var isWatchingVideo: Bool {
        session.controller.isPlaying && session.controller.currentItem?.kind == .video
    }

    /// Eight seconds a page. A clip that's showing holds the page until it
    /// ends; then three seconds more.
    private func advanceWhenDue() async {
        guard slides.count > 1, !isPaused else { return }
        let wait: Duration
        switch preview.phase(for: current.id) {
        case .showing:
            return
        case .finished:
            wait = .seconds(3)
        case .none, .loading:
            wait = .seconds(8)
        }
        try? await Task.sleep(for: wait)
        guard !Task.isCancelled else { return }
        step(by: 1)
    }

    /// Decodes every page's artwork ahead, so changing page never waits for it.
    private func prefetchArtwork() async {
        for slide in slides {
            guard let url = slide.artworkURL else { continue }
            _ = await ArtworkDecoder.decode(contentsOf: url, maxPixelSize: HeroBackground.pixelSize(for: slide))
            if case .album = slide.target {
                _ = await ArtworkDecoder.decode(contentsOf: url, maxPixelSize: HeroDetails.coverPixelSize)
            }
            if Task.isCancelled { return }
        }
    }

    // MARK: - Clips

    private struct PreviewKey: Hashable {
        var slideID: String
        var isAllowed: Bool
    }

    /// Clips play only while nothing else does, and never while the player
    /// has a video open, even paused (see `PlaybackController.playerHasVideo`).
    private var canPreview: Bool {
        guard isLive, playsPreviews, isOnScreen, scenePhase == .active, !session.controller.isPlaying,
              session.controller.currentItem?.kind != .video else { return false }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return false }
        #if os(iOS)
        // Settings ▸ Accessibility ▸ Motion ▸ Auto-Play Video Previews.
        return UIAccessibility.isVideoAutoplayEnabled
        #else
        return true
        #endif
    }

    private func previewWhenSettled() async {
        let slide = current
        guard canPreview, let video = slide.previewVideo else {
            preview.stop()
            return
        }
        // Already playing (or finished) this page's clip.
        if preview.phase(for: slide.id) != .none { return }
        try? await Task.sleep(for: .seconds(1.6))
        // Play may have been pressed meanwhile.
        guard !Task.isCancelled, canPreview, current.id == slide.id else { return }
        preview.start(video, slideID: slide.id, library: library, session: session)
    }
}

/// Moves a page's words with a sideways swipe, fading them as they go.
private struct FollowsSwipe: ViewModifier {
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset * 0.45)
            .opacity(1 - min(abs(offset) / 480, 0.55))
    }
}

// MARK: - A page's pieces

/// The artwork behind a page: the picture filling the space, or for an
/// album, a blur of its cover.
struct HeroBackground: View {
    @Environment(LibraryManager.self) private var library
    let slide: HeroSlide
    let style: HeroCarousel.Style

    /// Blurs don't need detail, so album art is decoded small.
    static func pixelSize(for slide: HeroSlide) -> Int {
        if case .album = slide.target { return 300 }
        return 2_000
    }

    var body: some View {
        switch slide.target {
        case .album:
            FilledArtwork(url: slide.artworkURL, maxPixelSize: Self.pixelSize(for: slide))
                .blur(radius: 50, opaque: true)
                .saturation(1.3)
                .overlay(Color.black.opacity(0.28))
        default:
            FilledArtwork(url: slide.artworkURL, maxPixelSize: Self.pixelSize(for: slide))
        }
    }
}

/// The words and buttons of a page (and an album's cover).
struct HeroDetails: View {
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session
    @Environment(\.appActions) private var actions
    let slide: HeroSlide
    let style: HeroCarousel.Style
    let width: CGFloat
    let height: CGFloat

    static let coverPixelSize = 900

    var body: some View {
        switch style {
        case .fullBleed: wide
        case .card: card
        }
    }

    private var wide: some View {
        HStack(alignment: .bottom, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    if let badge = slide.badge {
                        HeroBadge(badge)
                    }
                    HeroTitle(slide.title, size: min(max(width * 0.05, 44), 72))
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
            .frame(maxWidth: 640, alignment: .leading)
            Spacer(minLength: 0)
            if case .album = slide.target {
                cover(side: min(height * 0.56, 340))
                    .padding(.bottom, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, width > 900 ? 56 : 32)
        .padding(.bottom, height * 0.12 + 40)
    }

    private var card: some View {
        VStack(spacing: 10) {
            if case .album = slide.target {
                Spacer(minLength: 0)
                cover(side: min(width * 0.5, 210))
                    .padding(.bottom, 8)
            }
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

    private func cover(side: CGFloat) -> some View {
        ArtworkView(url: slide.artworkURL, shape: .square, maxPixelSize: Self.coverPixelSize, placeholderSymbol: "music.note")
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 12) {
            switch slide.target {
            case .album(let album):
                Button {
                    playAlbum(album, shuffled: false)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(minWidth: style == .card ? 150 : 0)
                }
                .buttonStyle(HeroPlayButtonStyle())
                HeroCircleButton("Shuffle", systemImage: "shuffle") {
                    playAlbum(album, shuffled: true)
                }
            default:
                if let play = slide.play {
                    Button {
                        HeroPreviewPlayer.shared.stop()
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
        case .homeVideo, .album:
            EmptyView()
        }
    }

    private func playAlbum(_ album: Album, shuffled: Bool) {
        HeroPreviewPlayer.shared.stop()
        let items = library.playbackItems(for: album.orderedTracks)
        guard !items.isEmpty else { return }
        Task {
            if shuffled {
                await session.playShuffled(items)
            } else {
                await session.play(items, startingAt: 0, shuffled: false)
            }
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
        case album(Album)
    }

    /// What the Play button plays (videos).
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
        switch content {
        case .music:
            return albumSlides(library: library, limit: limit, now: now)
        case .movies, .shows:
            return videoSlides(for: content, library: library, limit: limit, now: now)
        case .everything:
            var slides = videoSlides(for: .everything, library: library, limit: 6, now: now)
            // Home is also Listen Now: a couple of albums, third and sixth.
            let albums = albumSlides(library: library, limit: 2, now: now)
            for (offset, album) in albums.enumerated() {
                slides.insert(album, at: min(2 + offset * 3, slides.count))
            }
            if slides.count < 3 {
                // A library of mostly home videos still gets a carousel.
                for video in recentVideos(of: .homeVideo, library: library, limit: 3 - slides.count) where video.isAvailable {
                    slides.append(homeVideoSlide(video, library: library))
                }
            }
            return slides
        }
    }

    private static func videoSlides(for content: HeroCarousel.Content, library: LibraryManager, limit: Int, now: Date) -> [HeroSlide] {
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

        return FeaturedPicker.pick(candidates, limit: limit, now: now).compactMap { id -> HeroSlide? in
            if let movie = movies[id] {
                return movieSlide(movie, id: id, library: library, now: now)
            }
            if let show = shows[id] {
                return showSlide(show, id: id, library: library, now: now)
            }
            return nil
        }
    }

    private static func albumSlides(library: LibraryManager, limit: Int, now: Date) -> [HeroSlide] {
        var descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 300
        let albums = (try? library.context.fetch(descriptor)) ?? []
        guard !albums.isEmpty else { return [] }
        // What's been playing lately counts as "in progress", most recent first.
        let recent = library.recentlyPlayedAlbums(limit: 6)
        var lastPlayed: [PersistentIdentifier: Date] = [:]
        for (offset, album) in recent.enumerated() {
            lastPlayed[album.persistentModelID] = now.addingTimeInterval(-Double(offset) * 60)
        }
        var byID: [String: Album] = [:]
        let candidates = albums.map { album -> FeaturedPicker.Candidate in
            let id = "album:\(album.id.uuidString)"
            byID[id] = album
            let played = lastPlayed[album.persistentModelID]
            return FeaturedPicker.Candidate(
                id: id,
                dateAdded: album.dateAdded,
                lastPlayed: played,
                isInProgress: played != nil,
                hasBackdrop: album.artworkKey != nil,
                hasArtwork: album.artworkKey != nil
            )
        }
        return FeaturedPicker.pick(candidates, limit: limit, now: now).compactMap { id in
            byID[id].map { albumSlide($0, id: id, library: library, isPlayed: lastPlayed[$0.persistentModelID] != nil, now: now) }
        }
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
            // A disc opens at its menu: no clip.
            previewVideo: movie.file?.isDisc == true ? nil : movie
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
            previewVideo: video.file?.isDisc == true ? nil : video
        )
    }

    static func albumSlide(_ album: Album, id: String, library: LibraryManager, isPlayed: Bool, now: Date) -> HeroSlide {
        let songs = album.tracks.count
        var summary = songs == 1 ? "1 song" : "\(songs) songs"
        let minutes = Int((album.totalDuration / 60).rounded())
        if minutes > 0 {
            summary += minutes >= 60 ? ", \(minutes / 60) hr \(minutes % 60) min" : ", \(minutes) min"
        }
        return HeroSlide(
            id: id,
            target: .album(album),
            title: album.title,
            badge: FeaturedPicker.isNew(album.dateAdded, now: now) && !isPlayed ? "New" : nil,
            kindLine: line([album.isCompilation ? "Compilation" : "Album", album.artistName, album.genreName, album.year.map(String.init)]),
            overview: summary,
            artworkURL: library.artworkURL(album.artworkKey, .large),
            play: nil,
            previewVideo: nil
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
    /// A clip that shows nothing by then is given up on.
    static let startTimeout: Duration = .seconds(8)

    enum ClipPhase: Hashable, Sendable {
        case none
        case loading
        case showing
        case finished
    }

    let controller = PlaybackController(purpose: .preview)
    /// The page whose clip is loaded (playing, or finished and faded out).
    private(set) var slideID: String?
    /// Frames are on screen, so the video can fade in over the artwork.
    private(set) var isShowingVideo = false
    /// The page whose clip has played to its end (or given up).
    private(set) var finishedSlideID: String?
    private(set) var isMuted = true
    /// The clip's surface must stay on screen: true from the start of a clip
    /// until its player has completely stopped.
    private(set) var isMounted = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var clipStart: TimeInterval = 0
    @ObservationIgnored private var clipEnd: TimeInterval = 0

    private init() {
        controller.setFillMode(.fill)
        controller.setMuted(true)
    }

    func phase(for slideID: String) -> ClipPhase {
        if finishedSlideID == slideID { return .finished }
        guard self.slideID == slideID else { return .none }
        return isShowingVideo ? .showing : .loading
    }

    /// Where a clip starts: about a sixth of the way in, past the opening
    /// credits and well before anything gets spoiled. Short videos play from the start.
    nonisolated static func clipStart(duration: TimeInterval?) -> TimeInterval {
        guard let duration, duration.isFinite, duration > 0 else { return 120 }
        if duration < 180 { return 0 }
        return min(max(duration * 0.18, 60), duration - 90)
    }

    func start(_ video: Video, slideID: String, library: LibraryManager, session: PlaybackSession) {
        // A disc opens at its menu, so it has no clip to play.
        guard video.file?.isDisc != true,
              var item = library.playbackItem(for: video, fromStart: true) else { return }
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
        isMounted = true
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
        if let slideID, slideID != self.slideID, slideID != finishedSlideID { return }
        guard self.slideID != nil || finishedSlideID != nil || task != nil else { return }
        generation += 1
        let current = generation
        task?.cancel()
        task = nil
        isShowingVideo = false
        self.slideID = nil
        finishedSlideID = nil
        unmountWhenStopped(generation: current)
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

    /// Fades the video in once frames arrive, and out at the end of the clip
    /// (or when nothing has shown up after a few seconds).
    private func watch(generation current: Int) async {
        let started = ContinuousClock.now
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
            if !isShowingVideo, ContinuousClock.now - started > Self.startTimeout {
                finish(current)
                return
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
        slideID = nil
        // Let the picture fade out before the player goes.
        unmountWhenStopped(generation: current, after: .milliseconds(900))
    }

    /// Stops the player, then takes the surface away, unless a new clip
    /// started meanwhile.
    private func unmountWhenStopped(generation current: Int, after delay: Duration = .zero) {
        let controller = controller
        Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self, current == self.generation else { return }
            await controller.stop()
            if current == self.generation {
                self.isMounted = false
            }
        }
    }
}

// MARK: - The app's carousel for library pages

extension LibraryHeroProvider {
    /// The hero carousel, for the library pages that don't know about it
    /// (Albums lives in MusicFeature, which can't see VideoFeature).
    public static let carousels = LibraryHeroProvider { kind, isCompact in
        switch kind {
        case .music:
            AnyView(HeroCarousel(content: .music, style: HeroCarousel.Style.forWidth(isCompact: isCompact)))
        }
    }
}

extension HeroCarousel.Style {
    /// Full width on the iPad and the Mac; a card on the iPhone.
    public static func forWidth(isCompact: Bool) -> HeroCarousel.Style {
        isCompact ? .card : .fullBleed
    }
}
