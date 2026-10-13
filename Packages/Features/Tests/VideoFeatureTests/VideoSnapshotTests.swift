#if os(macOS)
import AppKit
import DesignSystem
import Foundation
import ImageIO
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import VideoFeature

/// Renders the hero carousel and the show page to PNG files in
/// `build/snapshots`, from a small made-up library, and checks what the
/// carousel chooses to feature. (ImageRenderer draws SwiftUI only: Liquid
/// Glass is flat and scroll views are left out of these pictures.)
@MainActor
@Suite("Hero and show page", .serialized)
struct VideoSnapshotTests {
    private static var outputFolder: URL {
        // Tests/VideoFeatureTests/VideoSnapshotTests.swift → repository root.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "build/snapshots", directoryHint: .isDirectory)
    }

    // MARK: - What the carousel features

    @Test func carouselFeaturesNewMoviesAndShowsInProgress() throws {
        let fixture = try Fixture()
        let slides = HeroSlideBuilder.slides(for: .everything, library: fixture.library)
        let movie = try #require(slides.first { $0.title == "The Midnight Garden" })
        #expect(movie.badge == "New")
        #expect(movie.play?.title == "Play")
        #expect(movie.kindLine == "Movie \u{00B7} Drama, Mystery \u{00B7} 2024 \u{00B7} 2 hr 4 min")
        #expect(movie.previewVideo != nil)

        let show = try #require(slides.first { $0.title == "Quiet Harbour" })
        #expect(show.play?.title == "Resume S1, E5")
        #expect(show.play?.progress != nil)
        #expect(show.previewVideo == nil)
        #expect(show.kindLine.hasPrefix("TV Show \u{00B7} Comedy, Drama"))

        // Movies shows only movies; TV Shows only shows.
        #expect(HeroSlideBuilder.slides(for: .movies, library: fixture.library).allSatisfy { $0.id.hasPrefix("movie:") })
        #expect(HeroSlideBuilder.slides(for: .shows, library: fixture.library).allSatisfy { $0.id.hasPrefix("show:") })
    }

    @Test func showButtonTitles() throws {
        let fixture = try Fixture()
        let first = try #require(fixture.show.orderedEpisodes.first)
        #expect(ShowPlayTitle.title(for: (first, false), hasStarted: false) == "Play First Episode")
        #expect(ShowPlayTitle.title(for: (first, false), hasStarted: true) == "Play S1, E1")
        #expect(ShowPlayTitle.title(for: (first, true), hasStarted: true) == "Resume S1, E1")
    }

    @Test func watchlistTogglesAndLists() throws {
        let fixture = try Fixture()
        let library = fixture.library
        #expect(!library.isOnWatchlist(fixture.movie))
        library.toggleWatchlist(fixture.movie)
        library.toggleWatchlist(fixture.show)
        #expect(library.isOnWatchlist(fixture.movie))
        #expect(library.watchlistEntries().map(\.id) == [WatchlistEntry.show(fixture.show).id, WatchlistEntry.movie(fixture.movie).id])
        library.toggleWatchlist(fixture.movie)
        #expect(!library.isOnWatchlist(fixture.movie))
        #expect(library.watchlistEntries().count == 1)
    }

    @Test func previewClipsStartPastTheOpening() {
        #expect(HeroPreviewPlayer.clipStart(duration: 7_440) == 7_440 * 0.18)
        #expect(HeroPreviewPlayer.clipStart(duration: 95) == 0)
        #expect(HeroPreviewPlayer.clipStart(duration: 200) == 60)
        #expect(HeroPreviewPlayer.clipStart(duration: nil) == 120)
    }

    // MARK: - Pictures

    @Test func heroPages() async throws {
        let fixture = try Fixture()
        let slides = HeroSlideBuilder.slides(for: .everything, library: fixture.library)
        try await fixture.warmArtwork(sizes: [2_000])
        for slide in slides.prefix(2) {
            let name = slide.id.hasPrefix("show:") ? "hero-wide-show" : "hero-wide-movie"
            let page = HeroPage(slide: slide, style: .fullBleed, isCurrent: true, preview: HeroPreviewPlayer.shared, linksToDetails: false)
                .overlay(alignment: .bottom) {
                    PageDots(count: 5, index: 1) { _ in }
                        .padding(.bottom, 640 * 0.12 + 4)
                }
                .frame(width: 1_280, height: 640)
            try render(fixture.environment(page), name: name, scheme: .dark)
            try render(fixture.environment(page), name: name + "-light", scheme: .light)
        }
        if let show = slides.first(where: { $0.id.hasPrefix("show:") }) {
            let card = HeroPage(slide: show, style: .card, isCurrent: true, preview: HeroPreviewPlayer.shared, linksToDetails: false)
                .frame(width: 393, height: HeroCarousel.height(for: 393, style: .card))
                .padding(.vertical, 20)
            try render(fixture.environment(card), name: "hero-card", scheme: .light)
        }
    }

    @Test func showPage() async throws {
        let fixture = try Fixture()
        try await fixture.warmArtwork(sizes: [2_000, 720])
        let next = fixture.library.nextUp(in: fixture.show)
        let episodes = fixture.show.orderedSeasons.first?.orderedEpisodes ?? []
        let wide = VStack(alignment: .leading, spacing: 24) {
            ShowHero(show: fixture.show, next: next, hasStarted: true, seasonCount: 2, isCompact: false)
            HStack(alignment: .top, spacing: 18) {
                ForEach(episodes.dropFirst(3).prefix(3)) { episode in
                    EpisodeCard(episode: episode, width: 340, highlight: episode.id == next?.video.id ? "Continue" : nil)
                }
            }
            .padding(.horizontal, Metrics.contentPadding)
        }
        .padding(.bottom, 24)
        .frame(width: 1_200)
        try render(fixture.environment(wide), name: "show-page", scheme: .dark)
        try render(fixture.environment(wide), name: "show-page-light", scheme: .light)

        let compact = VStack(alignment: .leading, spacing: 20) {
            ShowHero(show: fixture.show, next: next, hasStarted: true, seasonCount: 2, isCompact: true)
            if let current = next?.video {
                EpisodeCard(episode: current, width: 280, highlight: "Continue")
                    .padding(.horizontal, Metrics.contentPadding)
            }
        }
        .padding(.bottom, 20)
        .frame(width: 393)
        try render(fixture.environment(compact), name: "show-page-compact", scheme: .dark)
    }

    private func render(_ view: some View, name: String, scheme: ColorScheme) throws {
        let content = view
            .background(scheme == .dark ? Color(white: 0.07) : Color.white)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "\(name) didn't render")
        #expect(image.width > 100 && image.height > 20)
        let folder = Self.outputFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

// MARK: - A small library

/// One new movie and a two-season show half-way through season one.
@MainActor
private struct Fixture {
    let library = LibraryManager(inMemory: true)
    let session = PlaybackSession()
    let movie: Video
    let show: TVShow
    private var artworkKeys: [String] = []

    init() throws {
        let library = self.library
        let context = library.context
        let store = library.artworkStore
        var keys: [String] = []
        func art(_ width: Int, _ height: Int, _ palette: Int) -> String? {
            let key = Artwork.jpeg(width: width, height: height, palette: palette).flatMap { store.store($0) }
            if let key { keys.append(key) }
            return key
        }

        let movie = Video()
        movie.kind = .movie
        movie.title = "The Midnight Garden"
        movie.sortTitle = "midnight garden"
        movie.year = 2024
        movie.genres = ["Drama", "Mystery"]
        movie.overview = "A botanist inherits a walled garden that only blooms after dark, and the neighbours who have kept its secret for fifty years."
        movie.runtime = 7_440
        movie.dateAdded = Date.now.addingTimeInterval(-2 * 86_400)
        movie.backdropKey = art(1_280, 720, 0)
        movie.posterKey = art(600, 900, 0)
        movie.file = Self.file(name: "The Midnight Garden (2024).mkv", duration: 7_440, key: "movie-1", in: context)
        movie.file?.width = 3_840
        movie.file?.height = 1_608
        movie.file?.dynamicRangeRaw = "dolbyVision"
        movie.file?.hasAtmos = true
        context.insert(movie)

        let show = TVShow()
        show.title = "Quiet Harbour"
        show.sortTitle = "quiet harbour"
        show.key = "quiet harbour"
        show.year = 2023
        show.genres = ["Comedy", "Drama"]
        show.contentRating = "TV-14"
        show.network = "Coreplay+"
        show.overview = "When the harbour master of a sleepy fishing town retires, her estranged son comes home to run the port for one summer \u{2014} and finds the town has been quietly running a lot more than boats. Every regular has a secret, and every secret floats."
        show.cast = [CastMember(name: "Ada Lindqvist", role: "Mara"), CastMember(name: "Tomas Reyes", role: "Jonah"), CastMember(name: "Priya Shah", role: "Inez")]
        show.backdropKey = art(1_280, 720, 1)
        show.posterKey = art(600, 900, 1)
        show.dateAdded = Date.now.addingTimeInterval(-60 * 86_400)
        context.insert(show)

        let titles = ["Low Tide", "The Lighthouse Keeper", "Nets", "Fog Bank", "The Regatta", "Storm Season"]
        for seasonNumber in 1...2 {
            let season = Season()
            season.number = seasonNumber
            season.key = "quiet harbour#\(seasonNumber)"
            season.show = show
            context.insert(season)
            for (index, title) in titles.enumerated() {
                let episode = Video()
                episode.kind = .episode
                episode.title = seasonNumber == 1 ? title : "\(title) II"
                episode.sortTitle = episode.title.lowercased()
                episode.showTitle = show.title
                episode.seasonNumber = seasonNumber
                episode.episodeNumber = index + 1
                episode.overview = "Mara and Jonah can\u{2019}t agree about \u{201C}\(title)\u{201D}, and the whole town takes sides before the evening ferry."
                episode.runtime = 2_700
                episode.dateAdded = show.dateAdded
                episode.stillKey = art(780, 440, 2 + index)
                episode.file = Self.file(name: "Quiet Harbour S0\(seasonNumber)E0\(index + 1).mkv", duration: 2_700, key: "qh-\(seasonNumber)-\(index + 1)", in: context)
                episode.show = show
                episode.season = season
                context.insert(episode)
            }
        }
        try context.save()

        // Season 1: four watched, the fifth half-way.
        let seasonOne = show.orderedEpisodes.filter { $0.seasonNumber == 1 }
        library.markWatched(Array(seasonOne.prefix(4)))
        if let fifth = seasonOne.dropFirst(4).first, let file = fifth.file {
            library.recordProgress(libraryID: file.id, position: 1_350, duration: 2_700, outcome: .resume(at: 1_350))
        }

        self.movie = movie
        self.show = show
        self.artworkKeys = keys
    }

    private static func file(name: String, duration: Double, key: String, in context: ModelContext) -> MediaFile {
        let file = MediaFile()
        file.fileName = name
        file.fileExtension = "mkv"
        file.relativePath = name
        file.kindRaw = PlaybackItem.Kind.video.rawValue
        file.fileSize = 2_400_000_000
        file.contentKey = key
        file.duration = duration
        file.width = 1_920
        file.height = 1_080
        file.channels = 6
        file.hasSubtitles = true
        context.insert(file)
        return file
    }

    /// Decodes the artwork into the cache, so the pictures have it.
    func warmArtwork(sizes: [Int]) async throws {
        for key in artworkKeys {
            for size in sizes {
                let url = library.artworkStore.url(for: key, variant: .large)
                _ = await ArtworkDecoder.decode(contentsOf: url, maxPixelSize: size)
            }
        }
    }

    func environment(_ view: some View) -> some View {
        view
            .environment(library)
            .environment(session)
    }
}

/// Made-up artwork: a diagonal wash of two colours with soft light shapes.
private enum Artwork {
    static let palettes: [(CGColor, CGColor)] = [
        (CGColor(red: 0.10, green: 0.16, blue: 0.32, alpha: 1), CGColor(red: 0.62, green: 0.30, blue: 0.42, alpha: 1)),
        (CGColor(red: 0.05, green: 0.27, blue: 0.33, alpha: 1), CGColor(red: 0.85, green: 0.62, blue: 0.35, alpha: 1)),
        (CGColor(red: 0.18, green: 0.30, blue: 0.20, alpha: 1), CGColor(red: 0.70, green: 0.78, blue: 0.55, alpha: 1)),
        (CGColor(red: 0.30, green: 0.12, blue: 0.10, alpha: 1), CGColor(red: 0.92, green: 0.55, blue: 0.30, alpha: 1)),
        (CGColor(red: 0.12, green: 0.12, blue: 0.20, alpha: 1), CGColor(red: 0.45, green: 0.55, blue: 0.85, alpha: 1)),
        (CGColor(red: 0.22, green: 0.20, blue: 0.24, alpha: 1), CGColor(red: 0.80, green: 0.70, blue: 0.75, alpha: 1)),
        (CGColor(red: 0.08, green: 0.20, blue: 0.24, alpha: 1), CGColor(red: 0.40, green: 0.75, blue: 0.80, alpha: 1)),
        (CGColor(red: 0.26, green: 0.18, blue: 0.08, alpha: 1), CGColor(red: 0.95, green: 0.80, blue: 0.45, alpha: 1)),
    ]

    static func jpeg(width: Int, height: Int, palette: Int) -> Data? {
        let colors = palettes[palette % palettes.count]
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let gradient = CGGradient(colorsSpace: space, colors: [colors.0, colors.1] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        // Soft "lights", placed differently per palette.
        for index in 0..<7 {
            let seed = Double(index * 37 + palette * 11)
            let x = CGFloat((sin(seed) * 0.5 + 0.5)) * CGFloat(width)
            let y = CGFloat((cos(seed * 1.3) * 0.5 + 0.5)) * CGFloat(height)
            let radius = CGFloat(height) * CGFloat(0.08 + 0.05 * Double(index % 3))
            context.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.12 + 0.04 * CGFloat(index % 3)))
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
