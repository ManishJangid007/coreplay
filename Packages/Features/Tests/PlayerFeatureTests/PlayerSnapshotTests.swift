#if os(macOS)
import AppKit
import DesignSystem
import Foundation
import ImageIO
import NowPlaying
import PlaybackCore
import PlaybackEngine
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import PlayerFeature

/// Renders the player screens to PNG files in `build/snapshots`, so their
/// layout can be checked by eye without running the app. (ImageRenderer
/// draws SwiftUI only: the video, AirPlay buttons and Liquid Glass are
/// missing or flat in these pictures.)
@MainActor
@Suite("Player snapshots", .serialized)
struct PlayerSnapshotTests {
    private static var outputFolder: URL {
        // Tests/PlayerFeatureTests/PlayerSnapshotTests.swift → repository root.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "build/snapshots", directoryHint: .isDirectory)
    }

    private func movieSession() -> PlaybackSession {
        let session = PlaybackSession()
        let item = PlaybackItem(url: URL(fileURLWithPath: "/Movies/Heat (1995).mkv"), kind: .video, title: "Heat", artist: "1995 \u{00B7} Crime")
        session.controller.showPreview(
            item: item,
            duration: 10_200,
            time: 3_725,
            isPlaying: true,
            dimensions: VideoDimensions(width: 3_840, height: 1_608),
            chapters: [
                Chapter(index: 0, title: "Opening", start: 0, duration: 900),
                Chapter(index: 1, title: "The Bank", start: 900, duration: 3_000),
                Chapter(index: 2, title: "Airport", start: 3_900, duration: 6_300),
            ],
            audioTracks: [
                MediaTrack(id: "1", kind: .audio, name: "English", languageCode: "en", codec: "E-AC-3", isSelected: true, channelCount: 6),
                MediaTrack(id: "2", kind: .audio, name: "Commentary", languageCode: "en", codec: "AAC", channelCount: 2),
            ],
            subtitleTracks: [
                MediaTrack(id: "3", kind: .subtitle, name: "English", languageCode: "en", isSelected: true),
                MediaTrack(id: "4", kind: .subtitle, name: "English SDH", languageCode: "en"),
            ]
        )
        return session
    }

    /// A DVD showing its menu: the remote replaces the transport.
    private func discSession(titleIndex: Int = 0) -> PlaybackSession {
        let session = PlaybackSession()
        var item = PlaybackItem(url: URL(fileURLWithPath: "/Movies/Heat (1995)/VIDEO_TS", isDirectory: true), kind: .video, title: "Heat", artist: "1995 \u{00B7} Crime")
        item.disc = .dvd
        session.controller.showPreview(
            item: item,
            duration: titleIndex == 0 ? 0 : 6_724,
            time: titleIndex == 0 ? 0 : 1_250,
            isPlaying: true,
            dimensions: VideoDimensions(width: 720, height: 480),
            titles: [
                MediaTitle(id: 0, name: "DVD Menu", isMenu: true, isInteractive: true),
                MediaTitle(id: 1, duration: 6_724, chapterCount: 24),
                MediaTitle(id: 2, duration: 754, chapterCount: 3),
                MediaTitle(id: 3, name: "Trailer", duration: 132),
            ],
            currentTitleIndex: titleIndex
        )
        return session
    }

    @Test func discMenu() throws {
        let view = VideoPlayerView(onClose: {})
            .environment(discSession())
            .frame(width: 1_280, height: 720)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.19, blue: 0.38), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
        try render(view, name: "video-disc-menu")
        // An iPhone held upright: the remote must fit above the buttons.
        let compact = VideoPlayerView(onClose: {})
            .environment(discSession())
            .frame(width: 393, height: 852)
            .background(Color(red: 0.12, green: 0.19, blue: 0.38))
        try render(compact, name: "video-disc-menu-compact")
        try render(optionsPages([nil, .titles], isVideo: true, session: discSession(titleIndex: 1)), name: "options-disc")
    }

    private func songSession() -> PlaybackSession {
        let session = PlaybackSession()
        let item = PlaybackItem(url: URL(fileURLWithPath: "/Music/Angel.flac"), kind: .audio, title: "Angel", artist: "Massive Attack", albumTitle: "Mezzanine")
        session.controller.showPreview(item: item, duration: 379, time: 95, isPlaying: true)
        return session
    }

    @Test func videoPlayer() throws {
        let view = VideoPlayerView(onClose: {})
            .environment(movieSession())
            .frame(width: 1_280, height: 720)
            .background(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
        try render(view, name: "video-player")
    }

    @Test func videoTopControls() throws {
        let session = movieSession()
        let view = HStack(spacing: 10) {
            GlassIconButton("Back to Library", systemImage: "chevron.backward", action: {})
            GlassIconButton("Picture in Picture", systemImage: "pip.enter", action: {})
            Spacer(minLength: 12)
            GlassControlGroup {
                // Stands in for the AirPlay route picker, which ImageRenderer can't draw.
                PlayerIconButton("AirPlay", systemImage: "airplay.video", action: {})
                VolumeControl(controller: session.controller)
                PlayerIconButton("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", action: {})
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 720)
        .background(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
        try render(view, name: "video-top-controls")
    }

    @Test func videoOptionsPages() async throws {
        let session = movieSession()
        let presets = EqualizerPresets.all
        if let preset = presets.first(where: { $0.name == "Rock" }) ?? presets.first {
            // The controller, not the session, so the test's defaults aren't touched.
            await session.controller.setEqualizer(preset.settings)
        }
        session.controller.advanceABLoop()
        try render(optionsPages([nil, .audio, .subtitles, .speed], isVideo: true, session: session), name: "options-video-1")
        try render(optionsPages([.picture, .colours, .sound], isVideo: true, session: session), name: "options-video-2")
        try render(optionsPages([.chapters, .tools, .info], isVideo: true, session: session), name: "options-video-3")
        // The controller, not the session, so the test's defaults aren't touched.
        await session.controller.setSubtitleStyle(SubtitleStyle(font: .rounded, textColor: .yellow, isBold: true, background: .translucent, position: .raised))
        await session.controller.setSubtitleEncoding("Windows-1251")
        try render(optionsPages([.subtitles, .subtitleStyle, .encoding], isVideo: true, session: session), name: "options-video-4")
    }

    @Test func musicOptionsPages() throws {
        try render(optionsPages([nil, .speed, .sound], isVideo: false, session: songSession()), name: "options-music")
    }

    private func optionsPages(_ pages: [PlaybackOptionsView.Page?], isVideo: Bool, session: PlaybackSession) -> some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(pages, id: \.self) { page in
                PlaybackOptionsView(snapshotOf: page, isVideo: isVideo)
                    .frame(width: 360)
            }
        }
        .environment(session)
        .padding(24)
        .background(Color(white: 0.32))
    }

    @Test func nowPlaying() throws {
        let view = NowPlayingView(onClose: {})
            .environment(songSession())
            .frame(width: 1_100, height: 700)
        try render(view, name: "now-playing")
    }

    @Test func narrowNowPlaying() throws {
        let view = NowPlayingView(onClose: {})
            .environment(songSession())
            .frame(width: 560, height: 820)
        try render(view, name: "now-playing-narrow")
    }

    @Test func playbackBar() throws {
        let view = PlaybackBar()
            .environment(songSession())
            .frame(width: 1_100)
        try render(view, name: "playback-bar")
    }

    @Test func upNextCard() throws {
        let item = PlaybackItem(url: URL(fileURLWithPath: "/TV/Quiet Harbour S01E06.mkv"), kind: .video, title: "Storm Season", artist: "Quiet Harbour \u{00B7} S1, E6")
        let view = VStack(alignment: .trailing, spacing: 20) {
            UpNextCard(item: item, countdown: UpNextPolicy.Countdown(remaining: 6.2, total: 10), onPlay: {}, onDismiss: {})
            UpNextCard(item: item, countdown: nil, onPlay: {}, onDismiss: {})
        }
        .padding(30)
        .frame(width: 560)
        .background(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
        try render(view, name: "up-next-card")
    }

    @Test func scrubberWithChapters() throws {
        let view = PlaybackScrubber(
            position: 1_800,
            duration: 5_400,
            elapsedText: "0:30:00",
            remainingText: "-1:00:00",
            accessibilityValue: "",
            markers: [600, 2_400, 4_000],
            onScrubEnd: { _ in }
        )
        .frame(width: 600)
        .padding(30)
        .background(Color.black)
        try render(view, name: "scrubber")
    }

    private func render(_ view: some View, name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
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
#endif
