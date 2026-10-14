internal import VLCKit
import Foundation
import PlaybackCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// API names in this file were checked against the VLCKit 4.0.0a25 public
// headers (Headers/Public in the official VLCKit repository, master branch
// whose Package.swift points at the 4.0.0a25 binary), including the Swift
// names of the optional delegate methods.

/// Plays anything libVLC can play.
///
/// VLCKit delivers events on libVLC's own threads (VLCEventsDefaultConfiguration).
/// `VLCEventBridge` turns those callbacks into values on an `AsyncStream`; this
/// class consumes them on the main actor, where it also drives the player.
///
/// libVLC 4 facts this relies on: there is no "ended" state (reaching the end
/// goes stopping → stopped), `stop()` is asynchronous, and a stop issued
/// before playback started produces no callback at all.
@MainActor
final class VLCKitEngine: PlaybackEngine {
    let kind: EngineKind = .vlc
    let capabilities: EngineCapabilities = .vlc
    let events: AsyncStream<PlaybackEvent>

    private(set) var state: PlaybackState = .idle
    private(set) var duration: TimeInterval?
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var chapters: [Chapter] = []
    private(set) var titles: [MediaTitle] = []
    private(set) var currentTitleIndex: Int?
    private(set) var videoDimensions: VideoDimensions?

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    let player: VLCMediaPlayer
    private let bridge = VLCEventBridge()
    private let mediaOptions: [String]
    private var bridgeTask: Task<Void, Never>?
    /// Callers waiting for libVLC to confirm a stop.
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    /// Bumped whenever a stop completes, so a stale timeout can't release a later stop.
    private var stopToken = 0
    /// `true` when the stop in progress was asked for (not the end of the media).
    private var stopRequested = false
    /// `play()` was issued since the last confirmed `.stopped`.
    private var playerStarted = false
    private var hasPlayedCurrentMedia = false
    private var isShutDown = false
    private var fallbackDrawable: PlatformView?
    private var lastArtworkIdentity: ObjectIdentifier?
    private var lastArtworkData: Data?
    /// Set once per item when the chosen options have been applied again to
    /// the running video output (libVLC keeps some of them per output).
    private var appliedPictureOptions = false
    /// Where option changes reach libVLC; see `onOutputQueue(_:)`.
    let outputQueue = DispatchQueue(label: "Coreplay.VLCKitEngine.output", qos: .userInitiated)

    // Level 2 options. Setters apply straight away (on `outputQueue`); options
    // that differ from libVLC's defaults are applied again once playback
    // starts and the video output exists.
    var fillMode: VideoFillMode = .fit {
        didSet { applyFillMode() }
    }
    var aspectRatio: VideoRatio? {
        didSet { applyAspectRatio() }
    }
    var cropRatio: VideoRatio? {
        didSet { applyCrop() }
    }
    var videoAdjustments: VideoAdjustments = .neutral {
        didSet { applyAdjustments() }
    }
    var deinterlace: DeinterlaceMode = .automatic {
        didSet { applyDeinterlace() }
    }
    var deinterlaceFilter: DeinterlaceFilter = .standard {
        didSet { applyDeinterlace() }
    }
    /// 360° videos are projected by libVLC; this is where you're looking.
    var viewpoint: Viewpoint = .straightAhead {
        didSet { applyViewpoint() }
    }
    private(set) var projection: VideoProjection = .flat
    var stereoMode: StereoMode = .automatic {
        didSet { applyStereoMode() }
    }
    var equalizer: EqualizerSettings = .flat {
        didSet { applyEqualizer() }
    }
    var subtitleScale: Float = 1 {
        didSet { applySubtitleScale() }
    }
    /// Applied through the libVLC instance's options when the engine is
    /// created (`EngineConfiguration.subtitleStyle`); kept for the protocol.
    var subtitleStyle: SubtitleStyle = .standard
    /// The second subtitle track shown with the first, if any.
    private var secondarySubtitleID: String?
    /// The subtitle tracks last asked for. VLC makes a selection on its
    /// input thread, so for a moment its track list still reports the old
    /// one; until it catches up (or two seconds pass) the request is shown.
    private var requestedSubtitles: (main: String?, secondary: String?, until: Date)?

    /// Engines whose player hadn't confirmed its stop when they were shut down.
    /// Releasing a running VLCMediaPlayer would block the main thread while
    /// libVLC tears the input down, so they stay alive until `.stopped` arrives.
    private static var awaitingStop: [ObjectIdentifier: VLCKitEngine] = [:]

    init(library: VLCLibrary, mediaOptions: [String]) {
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
        self.events = stream
        self.continuation = continuation
        self.mediaOptions = mediaOptions
        self.player = VLCMediaPlayer(library: library)
        player.delegate = bridge
        // VLCKit interpolates the clock between libVLC time points; a shorter
        // interval keeps scrubbers moving smoothly (default is 1 s).
        player.timeChangeUpdateInterval = 0.25

        let bridgeEvents = bridge.events
        bridgeTask = Task { [weak self] in
            for await event in bridgeEvents {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    /// libVLC's own Theora decoder makes VLCKit 4.0.0a25's macOS video
    /// output fail an OpenGL check, which aborts the app (development builds
    /// keep their assertions). FFmpeg's decoder plays the same files fine, so
    /// Ogg video uses it first.
    nonisolated static func prefersFFmpegDecoders(_ url: URL) -> Bool {
        ["ogv", "ogm", "ogx"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Transport

    var currentTime: TimeInterval {
        Self.seconds(from: player.time)
    }

    var isSeekable: Bool { player.isSeekable }

    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }

    var volume: Float {
        get { Float(player.audio?.volume ?? 100) / 100 }
        set { player.audio?.volume = Int32((min(max(newValue, 0), 2) * 100).rounded()) }
    }

    var isMuted: Bool {
        get { player.audio?.isMuted ?? false }
        set { player.audio?.isMuted = newValue }
    }

    func load(_ item: PlaybackItem) async throws {
        if player.media != nil {
            await stopAndWait()
        }
        guard let media = VLCMedia(url: item.url) else {
            throw PlaybackError.cannotOpen(item.url)
        }
        for option in mediaOptions {
            media.addOption(option)
        }
        // A saved login for a share, as options: never in the URL.
        for option in item.credential?.vlcOptions(for: item.url) ?? [] {
            media.addOption(option)
        }
        if item.kind == .audio {
            // Never open a video output for music (embedded cover art would
            // otherwise become a "video" track on some containers).
            media.addOption(":no-video")
        }
        if Self.prefersFFmpegDecoders(item.url) {
            media.addOption(":codec=avcodec,all")
        }
        if item.isPreview {
            // A clip behind a title: no subtitles, and no looking for subtitle files.
            media.addOption(":no-spu")
            media.addOption(":no-sub-autodetect-file")
        }
        if !item.playsAudio {
            // No audio output at all, so nothing else that's playing is interrupted.
            media.addOption(":no-audio")
        }
        if let start = item.startPosition, start > 0 {
            media.addOption(":start-time=\(start)")
        }
        for subtitleURL in item.externalSubtitleURLs {
            _ = media.addSlave(VLCMediaSlave(url: subtitleURL, type: .subtitle, priority: 4))
        }
        media.delegate = bridge

        duration = nil
        audioTracks = []
        subtitleTracks = []
        secondarySubtitleID = nil
        requestedSubtitles = nil
        chapters = []
        titles = []
        currentTitleIndex = nil
        videoDimensions = nil
        projection = .flat
        hasPlayedCurrentMedia = false
        stopRequested = false
        lastArtworkIdentity = nil
        lastArtworkData = nil
        appliedPictureOptions = false

        player.media = media
        // A Chromecast chosen in the cast menu (never for a preview clip).
        player.setRendererItem(item.isPreview ? nil : CastingCenter.shared.activeRendererItem)
        setState(.opening)
    }

    func play() {
        // load()/shutdown() is waiting for a stop; the controller plays after load().
        guard stopWaiters.isEmpty, !isShutDown else { return }
        ensureDrawable()
        playerStarted = true
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) async {
        let target = max(0, time)
        if state == .ended || state == .idle {
            // libVLC can't seek a stopped player; restart at the requested time.
            if let media = player.media, stopWaiters.isEmpty, !isShutDown {
                media.addOption(":start-time=\(target)")
                ensureDrawable()
                playerStarted = true
                player.play()
            }
        } else {
            player.time = VLCTime(number: NSNumber(value: target * 1_000))
        }
        // No .timeChanged echo here: the controller already shows the target,
        // and an echo would release its seek hold before libVLC catches up.
    }

    // MARK: - Tracks

    func selectAudioTrack(id: MediaTrack.ID) {
        guard let track = player.audioTracks.first(where: { $0.trackId == id }) else { return }
        track.isSelectedExclusively = true
        refreshTracks()
    }

    func selectSubtitleTrack(id: MediaTrack.ID?) {
        // Choosing the main track (or none) also drops the second one.
        secondarySubtitleID = nil
        if let id, let track = player.textTracks.first(where: { $0.trackId == id }) {
            track.isSelectedExclusively = true
            requestedSubtitles = (id, nil, Date.now.addingTimeInterval(2))
        } else {
            player.deselectAllTextTracks()
            requestedSubtitles = (nil, nil, Date.now.addingTimeInterval(2))
        }
        refreshTracks()
    }

    /// libVLC 4 shows two subtitle tracks at once: the second is selected
    /// alongside the first rather than instead of it.
    func selectSecondarySubtitleTrack(id: MediaTrack.ID?) {
        let tracks = player.textTracks
        // The main track as last asked for, or as shown.
        let main: String?
        if let request = requestedSubtitles, Date.now < request.until {
            main = request.main
        } else {
            main = subtitleTracks.first { $0.isSelected && !$0.isSecondary }?.id
        }
        var chosen = tracks.filter { $0.trackId == main }
        secondarySubtitleID = nil
        if let id, id != main, let track = tracks.first(where: { $0.trackId == id }) {
            chosen.append(track)
            secondarySubtitleID = id
        }
        // Both at once: VLCKit's per-track `isSelected` reads VLC's current
        // selection, which may not include a main track chosen a moment ago.
        if chosen.isEmpty {
            player.deselectAllTextTracks()
        } else {
            player.selectTextTracks(chosen)
        }
        requestedSubtitles = (main, secondarySubtitleID, Date.now.addingTimeInterval(2))
        refreshTracks()
    }

    func addExternalSubtitle(url: URL) async throws {
        let result = player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        guard result == 0 else {
            throw PlaybackError(.unsupportedFormat, "Couldn\u{2019}t load the subtitle file \u{201C}\(url.lastPathComponent)\u{201D}.")
        }
    }

    var audioDelay: TimeInterval {
        get { TimeInterval(player.currentAudioPlaybackDelay) / 1_000_000 }
        set { player.currentAudioPlaybackDelay = Int((newValue * 1_000_000).rounded()) }
    }

    var subtitleDelay: TimeInterval {
        get { TimeInterval(player.currentVideoSubTitleDelay) / 1_000_000 }
        set { player.currentVideoSubTitleDelay = Int((newValue * 1_000_000).rounded()) }
    }

    // MARK: - Chapters

    func selectChapter(at index: Int) {
        player.currentChapterIndex = Int32(index)
    }

    // MARK: - Titles and disc menus

    func selectTitle(at index: Int) {
        player.currentTitleIndex = Int32(index)
    }

    /// The arrows and Select reach libVLC's DVD and Blu-ray navigation. A
    /// DVD's menu is a title of its own ("DVD Menu"; selecting it calls the
    /// root menu), as is a Blu-ray's top menu; the pop-up menu is a command.
    func navigate(_ action: DiscNavigation) {
        switch action {
        case .up: player.perform(.up)
        case .down: player.perform(.down)
        case .left: player.perform(.left)
        case .right: player.perform(.right)
        case .activate: player.perform(.activate)
        case .menu:
            if let menu = titles.first(where: \.isMenu) {
                player.currentTitleIndex = Int32(menu.id)
            } else {
                player.currentTitleDescription?.navigatePopup()
            }
        case .popUpMenu:
            player.currentTitleDescription?.navigatePopup()
        }
    }

    // MARK: - Video output

    func attachVideoOutput(to host: (any VideoOutputHost)?) {
        if let view = host as? PlatformVideoView {
            player.drawable = view
        } else {
            player.drawable = makeFallbackDrawable()
        }
    }

    /// VLC must always have a drawable: on macOS it would otherwise open a
    /// window of its own, which the design forbids.
    private func ensureDrawable() {
        if player.drawable == nil {
            player.drawable = makeFallbackDrawable()
        }
    }

    private func makeFallbackDrawable() -> PlatformView {
        if let fallbackDrawable { return fallbackDrawable }
        let view = PlatformView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        // Kept in a window, so VLC's OpenGL output has a framebuffer (see `VideoParking`).
        VideoParking.park(view)
        fallbackDrawable = view
        return view
    }

    // MARK: - Shutdown

    func shutdown() async {
        isShutDown = true
        await stopAndWait()
        player.media?.delegate = nil
        player.drawable = nil
        continuation.finish()
        if playerStarted {
            // libVLC hasn't confirmed the stop yet: stay alive until it does.
            Self.awaitingStop[ObjectIdentifier(self)] = self
        } else {
            finishShutdown()
        }
    }

    private func finishShutdown() {
        // libVLC has stopped drawing: the parking window can go.
        if let fallbackDrawable {
            VideoParking.unpark(fallbackDrawable)
        }
        player.delegate = nil
        bridgeTask?.cancel()
        bridge.finish()
        Self.awaitingStop[ObjectIdentifier(self)] = nil
    }

    /// Stops playback and waits (up to two seconds) for libVLC to confirm, so
    /// the video output is gone before its view is reused or released.
    private func stopAndWait() async {
        guard playerStarted || (player.state != .stopped && player.state != .error) else { return }
        stopRequested = true
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            stopWaiters.append(waiter)
            guard stopWaiters.count == 1 else { return } // a stop is already in flight
            player.stop()
            let token = stopToken
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.stopToken == token else { return } // that stop already finished
                self.resumeStopWaiters()
            }
        }
    }

    private func resumeStopWaiters() {
        stopToken &+= 1
        let waiters = stopWaiters
        stopWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Events

    private func handle(_ event: VLCEventBridge.Event) {
        switch event {
        case .state(let rawValue):
            if let newState = VLCMediaPlayerState(rawValue: rawValue) {
                handleStateChange(newState)
            }
        case .buffering(let progress):
            continuation.yield(.bufferingChanged(Double(min(max(progress, 0), 1))))
        case .rate(let rate):
            continuation.yield(.rateChanged(rate))
        case .length(let milliseconds):
            updateDuration(milliseconds: milliseconds)
        case .time:
            continuation.yield(.timeChanged(currentTime))
        case .tracks:
            refreshTracks()
            refreshVideoDimensions()
        case .chapters:
            refreshChapters()
        case .titles:
            refreshTitles()
            refreshChapters()
        case .metadata:
            publishMetadata()
        }
    }

    private func handleStateChange(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .opening:
            setState(.opening)
        case .playing:
            hasPlayedCurrentMedia = true
            if !appliedPictureOptions {
                appliedPictureOptions = true
                applyChosenOptions()
            }
            setState(.playing)
            updateDuration(milliseconds: nil)
            refreshTracks()
            refreshTitles()
            refreshChapters()
            refreshVideoDimensions()
            publishMetadata()
        case .paused:
            setState(.paused)
        case .stopping:
            break
        case .stopped:
            playerStarted = false
            resumeStopWaiters()
            if isShutDown {
                finishShutdown()
                return
            }
            if case .failed = state { return }
            if stopRequested {
                stopRequested = false
                setState(.idle)
            } else if hasPlayedCurrentMedia {
                // libVLC 4 has no "ended" state: reaching the end stops the player.
                hasPlayedCurrentMedia = false
                continuation.yield(.endOfMedia)
                setState(.ended)
            } else {
                setState(.idle)
            }
        case .error:
            let name = player.media?.url?.lastPathComponent ?? "this item"
            setState(.failed(PlaybackError(.cannotOpen, "VLC couldn\u{2019}t play \u{201C}\(name)\u{201D}.")))
        case .nothingSpecial:
            break
        @unknown default:
            break
        }
    }

    private func setState(_ newState: PlaybackState) {
        guard newState != state else { return }
        state = newState
        continuation.yield(.stateChanged(newState))
    }

    private func updateDuration(milliseconds: Int64?) {
        let value: TimeInterval
        if let milliseconds, milliseconds > 0 {
            value = TimeInterval(milliseconds) / 1_000
        } else if duration == nil, let media = player.media {
            // VLCMedia caches the first length it reads; only use it to fill a gap.
            let seconds = Self.seconds(from: media.length)
            guard seconds > 0 else { return }
            value = seconds
        } else {
            return
        }
        guard value != duration else { return }
        duration = value
        continuation.yield(.durationChanged(value))
    }

    private func refreshTracks() {
        let audio = player.audioTracks.map { Self.makeTrack($0, kind: .audio) }
        var subtitles = player.textTracks.map { Self.makeTrack($0, kind: .subtitle) }
        if let request = requestedSubtitles {
            let reported = Set(subtitles.filter(\.isSelected).map(\.id))
            let wanted = Set([request.main, request.secondary].compactMap { $0 })
            if reported == wanted || Date.now > request.until {
                requestedSubtitles = nil
            } else {
                for index in subtitles.indices {
                    subtitles[index].isSelected = wanted.contains(subtitles[index].id)
                }
            }
        }
        if let secondary = secondarySubtitleID {
            if let index = subtitles.firstIndex(where: { $0.id == secondary && $0.isSelected }) {
                subtitles[index].isSelected = false
                subtitles[index].isSecondary = true
            } else {
                secondarySubtitleID = nil
            }
        }
        guard audio != audioTracks || subtitles != subtitleTracks else { return }
        audioTracks = audio
        subtitleTracks = subtitles
        continuation.yield(.tracksChanged)
    }

    private func refreshChapters() {
        let descriptions = player.chapterDescriptions(ofTitle: player.currentTitleIndex)
        let newChapters = descriptions.map { description in
            Chapter(
                index: Int(description.chapterIndex),
                title: description.name,
                start: Self.seconds(from: description.timeOffset),
                duration: Self.seconds(from: description.durationTime)
            )
        }
        guard newChapters != chapters else { return }
        chapters = newChapters
        continuation.yield(.chaptersChanged)
    }

    private func refreshTitles() {
        let newTitles = player.titleDescriptions.map { description in
            MediaTitle(
                id: Int(description.titleIndex),
                name: description.name,
                duration: Self.seconds(from: description.durationTime),
                isMenu: description.isMenu || description.titleType.contains(.menu),
                isInteractive: description.titleType.contains(.interactive),
                chapterCount: description.chapterDescriptions.count
            )
        }
        let index = Int(player.currentTitleIndex)
        let current: Int? = index >= 0 ? index : nil
        guard newTitles != titles || current != currentTitleIndex else { return }
        titles = newTitles
        currentTitleIndex = current
        continuation.yield(.titlesChanged)
    }

    /// 360° or flat, from the selected video track.
    private func refreshProjection() {
        let tracks = player.videoTracks
        let track = tracks.first(where: \.isSelected) ?? tracks.first
        let value: VideoProjection = switch track?.video?.projection {
        case .equiRectangular: .equirectangular
        case .cubemapLayoutStandard: .cubeMap
        default: .flat
        }
        guard value != projection else { return }
        projection = value
        continuation.yield(.projectionChanged(value))
    }

    private func refreshVideoDimensions() {
        refreshProjection()
        let size = player.videoSize
        let dimensions: VideoDimensions? = size.width > 0 && size.height > 0
            ? VideoDimensions(width: Int(size.width), height: Int(size.height))
            : nil
        guard dimensions != videoDimensions else { return }
        // Keep the last known size while the video output restarts.
        if dimensions == nil, !player.videoTracks.isEmpty, videoDimensions != nil { return }
        videoDimensions = dimensions
        continuation.yield(.videoDimensionsChanged(dimensions))
    }

    private func publishMetadata() {
        guard let media = player.media else { return }
        let tags = media.metaData
        var metadata = MediaMetadata(
            title: tags.title.nonEmpty,
            artist: tags.artist.nonEmpty,
            albumTitle: tags.album.nonEmpty,
            albumArtist: tags.albumArtist.nonEmpty,
            genre: tags.genre.nonEmpty,
            trackNumber: tags.trackNumber > 0 ? Int(tags.trackNumber) : nil,
            discNumber: tags.discNumber > 0 ? Int(tags.discNumber) : nil
        )
        if let artwork = tags.artwork {
            let identity = ObjectIdentifier(artwork)
            if identity != lastArtworkIdentity {
                lastArtworkIdentity = identity
                lastArtworkData = Self.jpegData(from: artwork)
            }
            metadata.artworkData = lastArtworkData
        }
        continuation.yield(.metadataChanged(metadata))
    }

    // MARK: - Helpers

    private static func seconds(from time: VLCTime) -> TimeInterval {
        guard let milliseconds = time.value?.doubleValue, milliseconds.isFinite else { return 0 }
        return max(0, milliseconds / 1_000)
    }

    private static func makeTrack(_ track: VLCMediaPlayer.Track, kind: MediaTrack.Kind) -> MediaTrack {
        let codec = track.codecName()
        let channels = track.audio.map { Int($0.channelsNumber) }
        return MediaTrack(
            id: track.trackId,
            kind: kind,
            name: track.trackName,
            languageCode: track.language.nonEmpty,
            codec: codec.isEmpty ? nil : codec,
            isSelected: track.isSelected,
            channelCount: channels.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    #if canImport(UIKit)
    private static func jpegData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.9)
    }
    #elseif canImport(AppKit)
    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
    #endif
}

/// Receives VLCKit's delegate callbacks on whichever thread libVLC uses and
/// forwards them as plain values. It never touches the player itself.
///
/// The Swift names below are exactly what the importer derives from the
/// VLCKit 4 headers (e.g. `mediaPlayerTrackAdded:withType:` becomes
/// `mediaPlayerTrackAdded(_:with:)`); a mismatch would make Swift skip the method.
final class VLCEventBridge: NSObject, VLCMediaPlayerDelegate, VLCMediaDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case state(Int)
        case buffering(Float)
        case rate(Float)
        case length(Int64)
        case time
        case tracks
        case chapters
        case titles
        case metadata
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    override init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.continuation = continuation
        super.init()
    }

    func finish() {
        continuation.finish()
    }

    // MARK: VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        continuation.yield(.state(newState.rawValue))
    }

    func mediaPlayerBufferingChanged(_ progress: Float) {
        continuation.yield(.buffering(progress))
    }

    func mediaPlayerRateChanged(_ rate: Float) {
        continuation.yield(.rate(rate))
    }

    func mediaPlayerLengthChanged(_ length: Int64) {
        continuation.yield(.length(length))
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        continuation.yield(.time)
    }

    func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        continuation.yield(.tracks)
    }

    func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        continuation.yield(.tracks)
    }

    func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        continuation.yield(.tracks)
    }

    func mediaPlayerTrackSelected(_ trackType: VLCMedia.TrackType, selectedId: String, unselectedId: String) {
        continuation.yield(.tracks)
    }

    func mediaPlayerChapterChanged(_ aNotification: Notification) {
        continuation.yield(.chapters)
    }

    func mediaPlayerTitleListChanged(_ aNotification: Notification) {
        continuation.yield(.titles)
    }

    func mediaPlayerTitleSelectionChanged(_ aNotification: Notification) {
        continuation.yield(.titles)
    }

    // MARK: VLCMediaDelegate

    func mediaMetaDataDidChange(_ aMedia: VLCMedia) {
        continuation.yield(.metadata)
    }

    func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        continuation.yield(.metadata)
    }

    func mediaDidChangeArtwork(_ aMedia: VLCMedia) {
        continuation.yield(.metadata)
    }
}

/// Owns the `VLCLibrary` (one libVLC instance) shared by every VLC engine.
/// A new library is created only when the global options change.
@MainActor
final class VLCLibraryProvider {
    private var library: VLCLibrary?
    private var options: [String] = []

    func library(options: [String]) -> VLCLibrary {
        if let library, options == self.options {
            return library
        }
        let library = VLCLibrary(options: options)
        library.setHumanReadableName("Coreplay", withHTTPUserAgent: "Coreplay/1.0")
        // Logins VLC asks for while playing from a share or a stream.
        NetworkLoginPrompt.shared.attach(to: library)
        self.library = library
        self.options = options
        return library
    }

    func versionDescription(options: [String]) -> String {
        let library = library(options: options)
        return "libVLC \(library.version)"
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
