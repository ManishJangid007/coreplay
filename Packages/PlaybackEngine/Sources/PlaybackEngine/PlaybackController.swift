import Foundation
import Observation
import PlaybackCore

/// The one object the UI talks to for playback.
///
/// It routes each item to the right engine, mirrors the engine's state into
/// observable properties, and hands playback over to VLC at the same
/// position when the user asks for something AVFoundation can't do (subtitle
/// timing, external subtitles, speeds above 2×…) or when AVFoundation fails.
/// Views never see an engine directly.
///
/// Every operation that replaces the engine is serialized: an engine is only
/// installed once the previous one has fully stopped, and a `generation`
/// counter makes superseded loads, stops and hand-offs give up quietly.
@MainActor
@Observable
public final class PlaybackController {
    /// Coarse notifications for non-UI observers such as Now Playing.
    public enum Change: Hashable, Sendable {
        case item
        case state
        case seek
        case rate
        case duration
        case metadata
        case tracks
        /// Another title started (a disc's menu included), or the list changed.
        case titles
        case endOfMedia
    }

    /// What a controller is for. The app's player is `.main`; the hero
    /// carousel's clips play in a `.preview` controller, which never offers
    /// Picture in Picture or AirPlay and makes no scrubber previews.
    public enum Purpose: Sendable {
        case main
        case preview
    }

    public let purpose: Purpose

    // MARK: Observable state

    public private(set) var currentItem: PlaybackItem?
    public private(set) var state: PlaybackState = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval?
    public private(set) var bufferingProgress: Double = 1
    public private(set) var rate: Float = 1
    public private(set) var volume: Float = 1
    public private(set) var isMuted = false
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var subtitleTracks: [MediaTrack] = []
    public private(set) var chapters: [Chapter] = []
    /// A disc's titles, its menus included, or a file's editions.
    public private(set) var titles: [MediaTitle] = []
    /// The playing title's `id`.
    public private(set) var currentTitleIndex: Int?
    public private(set) var videoDimensions: VideoDimensions?
    public private(set) var metadata = MediaMetadata()
    public private(set) var audioDelay: TimeInterval = 0
    public private(set) var subtitleDelay: TimeInterval = 0
    public private(set) var activeEngine: EngineKind?
    public private(set) var routingReason: EngineRouter.Reason?
    public private(set) var capabilities: EngineCapabilities = []
    public private(set) var isSeekable = false
    /// `true` while the user drags a scrubber; engine time updates are ignored.
    public private(set) var isScrubbing = false
    /// The video is playing on an AirPlay device (AVFoundation only).
    public private(set) var isExternalPlaybackActive = false

    // Level 2 options. Picture options and timing belong to the current item;
    // the fill mode, sound and subtitle size carry on to the next one.
    public private(set) var fillMode: VideoFillMode = .fit
    public private(set) var aspectRatio: VideoRatio?
    public private(set) var cropRatio: VideoRatio?
    public private(set) var videoAdjustments: VideoAdjustments = .neutral
    public private(set) var deinterlace: DeinterlaceMode = .automatic
    /// Which filter deinterlaces; carries on to the next item.
    public private(set) var deinterlaceFilter: DeinterlaceFilter = .standard
    /// Turned and mirrored (the video view does it, so both engines can).
    public private(set) var transform: VideoTransform = .identity
    /// Magnified past fitting, and which part is in view (the video view does it).
    public private(set) var zoom: VideoZoom = .none
    /// The playing video is 360° (or flat).
    public private(set) var projection: VideoProjection = .flat
    /// Where a 360° video looks.
    public private(set) var viewpoint: Viewpoint = .straightAhead
    public private(set) var stereoMode: StereoMode = .automatic
    public private(set) var equalizer: EqualizerSettings = .flat
    public private(set) var subtitleSize: SubtitleSize = .standard
    public private(set) var subtitleStyle: SubtitleStyle = .standard
    /// The character set for subtitle files that aren't Unicode; `nil` is automatic.
    public private(set) var subtitleEncoding: String?
    public private(set) var abLoop = ABLoop()
    /// Which tracks a video starts with when you haven't chosen for it before.
    public var trackPreferences: TrackPreferences = .automatic
    /// Levels music to the same loudness with its ReplayGain values.
    public private(set) var replayGain: ReplayGainSettings = .off
    /// What ReplayGain multiplies the current item's volume by (1: as recorded).
    public private(set) var replayGainScale: Double = 1

    public var isPlaying: Bool {
        state == .playing || state == .buffering
    }

    /// A 360° video: you look around it rather than turning or magnifying it.
    public var isSpherical: Bool {
        projection.isSpherical
    }

    // MARK: Discs

    /// The title playing, if the media has titles.
    public var currentTitle: MediaTitle? {
        guard let currentTitleIndex else { return nil }
        return titles.first { $0.id == currentTitleIndex }
    }

    /// A DVD or Blu-ray is playing (from a folder or an image).
    public var isDisc: Bool {
        currentItem?.disc != nil
    }

    /// The disc's menu is on screen: the arrows and Select work it.
    public var isShowingDiscMenu: Bool {
        currentTitle?.isMenu == true
    }

    /// The disc has a menu to go back to.
    public var hasDiscMenu: Bool {
        titles.contains(where: \.isMenu)
    }

    /// The disc's film: its longest title.
    public var mainTitle: MediaTitle? {
        MediaTitle.mainFeature(in: titles)
    }

    /// The film is playing, rather than a menu or an extra. Always `true`
    /// for files, so progress is saved only for a disc's film.
    public var isPlayingMainTitle: Bool {
        guard isDisc else { return true }
        guard let main = mainTitle else { return false }
        return main.id == currentTitleIndex
    }

    /// Whether the player should show video UI. The engine's report wins over
    /// the item's guessed kind.
    public var hasVideo: Bool {
        if videoDimensions != nil { return true }
        return currentItem?.kind == .video
    }

    /// Library items show the library's title and artist (which the user may
    /// have edited); anything else prefers what the engine read from the file.
    public var displayTitle: String {
        if let item = currentItem, item.namesItself {
            return item.title
        }
        return metadata.title ?? currentItem?.title ?? ""
    }

    public var displaySubtitle: String? {
        if let item = currentItem, item.namesItself {
            // The library's artist, even when it has none; a cue track falls back on the file's.
            return item.libraryID != nil ? item.artist : item.artist ?? metadata.artist
        }
        return metadata.artist ?? currentItem?.artist
    }

    /// The app's settings. The subtitle style and encoding chosen in the
    /// player are merged in for the engines (see `updateFactoryConfiguration`).
    public var configuration: EngineConfiguration {
        didSet {
            updateFactoryConfiguration()
        }
    }

    /// The single view all engines render into. See `VideoSurface`.
    public let videoView: PlatformVideoView
    /// Picture in Picture for whichever engine is playing.
    public let pictureInPicture = PictureInPicture()
    /// Frame previews for the scrubber.
    public let scrubPreviews = ScrubPreviews()

    // MARK: Internals

    @ObservationIgnored public var onChange: (@MainActor (Change) -> Void)?
    /// What you chose for a file last time (the session keeps them), or `nil`.
    @ObservationIgnored public var rememberedOptions: (@MainActor (PlaybackItem) -> FileOptions?)?
    /// The saved login for a share's file (the app reads the Keychain), or `nil`.
    @ObservationIgnored public var networkCredentials: (@MainActor (URL) -> NetworkCredential?)?
    /// Called when you change a video's tracks, timing or picture, to remember them.
    @ObservationIgnored public var onOptionsChosen: (@MainActor (PlaybackItem, FileOptions) -> Void)?
    /// The language the app runs in, for subtitle preferences.
    @ObservationIgnored public var appLanguage = MediaTrack.normalizedLanguageCode(Locale.preferredLanguages.first ?? "en")
    /// `trackPreferences` still to be applied as the item's tracks appear.
    @ObservationIgnored private var appliesTrackPreferences = false
    /// The tracks chosen for this item, by language: remembered from last
    /// time, or picked now. `nil` while the file's own (or your preferred)
    /// tracks play. Kept here rather than read back from the engine, which
    /// reports a new selection a moment later.
    @ObservationIgnored private var chosenTracks: ChosenTracks?

    private struct ChosenTracks {
        var audioLanguage: String?
        var subtitleLanguage: String?
        var subtitlesOff: Bool
    }
    /// The item's segment has played to its end (reported once).
    @ObservationIgnored private var reachedSegmentEnd = false
    /// The whole file's length, as the engine reports it (an item's
    /// `duration` is its segment's).
    @ObservationIgnored private var fileDuration: TimeInterval?
    /// Where a disc picks up once its titles are known: a title (the film
    /// when `nil`) and a time in it. Discs open at their menu, so a resume
    /// position can't be handed to the engine as a start time.
    @ObservationIgnored private var pendingDiscStart: (title: Int?, time: TimeInterval)?
    /// The title for `pendingDiscStart` has been asked for.
    @ObservationIgnored private var requestedDiscTitle = false
    @ObservationIgnored private var engine: (any PlaybackEngine)?
    @ObservationIgnored private var engineOptionsFingerprint: [String] = []
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    /// The shutdown of the previous engine, which every engine switch waits for.
    @ObservationIgnored private var retirement: Task<Void, Never>?
    @ObservationIgnored private var router: EngineRouter
    @ObservationIgnored private let factory: EngineFactory
    @ObservationIgnored private let prober = MediaProber()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var hasPlayedCurrentItem = false
    @ObservationIgnored private var didFallBackToVLC = false
    @ObservationIgnored private var seekHold: (target: TimeInterval, deadline: ContinuousClock.Instant)?
    @ObservationIgnored private var pendingTrackRestore: TrackRestore?
    @ObservationIgnored private var addedSubtitleURLs: [URL] = []
    @ObservationIgnored private var securityScopedURLs: [URL] = []
    /// Artwork the library supplied with the item (`PlaybackItem.artworkURL`),
    /// which wins over artwork the engine finds in the file.
    @ObservationIgnored private var itemArtwork: Data?
    /// Containers currently showing a `VideoSurface`, newest last (see VideoSurface.swift).
    @ObservationIgnored var videoContainers: [WeakVideoContainer] = []
    /// `videoView`, with VLC's Picture in Picture hooks.
    @ObservationIgnored private let videoHost: VideoHostView
    @ObservationIgnored private var lastPictureInPictureSnapshot = PictureInPictureMediaBridge.Snapshot()

    private struct TrackRestore {
        var audioLanguage: String?
        var subtitleLanguage: String?
        var subtitlesOff: Bool
        // After a restart in the same kind of engine, the tracks keep their
        // identifiers, so they're restored exactly (both subtitle tracks too).
        var audioID: String?
        var subtitleID: String?
        var secondarySubtitleID: String?

        var isFinished: Bool {
            audioLanguage == nil && subtitleLanguage == nil && !subtitlesOff
                && audioID == nil && subtitleID == nil && secondarySubtitleID == nil
        }
    }

    public init(configuration: EngineConfiguration = EngineConfiguration(), purpose: Purpose = .main) {
        self.purpose = purpose
        self.configuration = configuration
        self.router = EngineRouter(alwaysUseVLC: configuration.alwaysUseVLC)
        self.factory = EngineFactory(configuration: configuration)
        let host = VideoHostView(frame: .zero)
        self.videoHost = host
        self.videoView = host
        if purpose == .main {
            connectPictureInPicture()
            CastingCenter.shared.onTargetChange = { [weak self] _ in
                guard let self else { return }
                Task { await self.castTargetChanged() }
            }
        }
        Self.everyController.add(self)
    }

    // MARK: - One VLC picture at a time

    /// Every controller there is, weakly held. Two libVLC video outputs at
    /// once trip libVLC's OpenGL checks (which end the app in VLCKit's
    /// development builds), so the player and the previews keep out of each
    /// other's way: the player stops every preview before it opens anything,
    /// and a preview never uses VLC while the player has a video.
    private static let everyController = NSHashTable<PlaybackController>.weakObjects()

    /// The player has a video, open or opening (in whichever engine).
    static var playerHasVideo: Bool {
        everyController.allObjects.contains { $0.purpose == .main && $0.currentItem?.kind == .video }
    }

    /// Stops every preview, waiting until each one's video output is gone.
    private static func stopPreviews() async {
        for controller in everyController.allObjects
        where controller.purpose == .preview && (controller.currentItem != nil || controller.engine != nil) {
            await controller.stop()
        }
    }

    // MARK: - Loading

    /// Opens `item` with the engine the router picks, and starts playing unless `autoplay` is false.
    public func load(_ item: PlaybackItem, autoplay: Bool = true) async {
        generation += 1
        let loadGeneration = generation
        var item = item
        if purpose == .preview {
            item.isPreview = true
        }

        // Keep the previous item's file access until its engine has stopped
        // reading it (that happens before this method returns).
        let previousScopedURLs = securityScopedURLs
        securityScopedURLs = []
        defer { Self.endAccess(to: previousScopedURLs) }
        beginSecurityScopedAccess(to: item.url, if: item.requiresSecurityScope)
        for subtitleURL in item.externalSubtitleURLs {
            beginSecurityScopedAccess(to: subtitleURL, if: item.requiresSecurityScope)
        }

        // A DVD or Blu-ray (its folder, its VIDEO_TS, an IFO file in it, or
        // an image) opens as the disc, menus and all.
        if item.disc == nil, item.segment == nil, !item.isPreview, DiscLayout.mightBeDisc(item.url) {
            let url = item.url
            let disc = await Task.detached(priority: .userInitiated) { DiscLayout.disc(at: url) }.value
            guard loadGeneration == generation else { return }
            if let disc {
                item = item.playing(disc)
            }
        }
        if item.disc != nil, !DiscLayout.canPlayDiscs {
            await stop()
            guard loadGeneration + 1 == generation else { return }
            currentItem = item
            setState(.failed(PlaybackError(.unsupportedFormat, "Coreplay can\u{2019}t play DVDs and Blu-rays yet: the VLC engine it uses was built without disc support. The VOB or M2TS files inside the disc play on their own.")))
            notify(.item)
            return
        }
        pendingDiscStart = nil
        requestedDiscTitle = false
        if item.disc != nil, let start = item.startPosition, start > 0 {
            // Discs open at their menu, so the engine gets no start time:
            // the film is chosen, then the time, once VLC lists the titles.
            pendingDiscStart = (nil, start)
            item.startPosition = nil
        }

        currentItem = item
        resetMediaState()
        updateReplayGainScale()
        let remembered = item.kind == .audio || item.isPreview ? nil : rememberedOptions?(item)
        chosenTracks = remembered.flatMap { options in
            options.choosesTracks
                ? ChosenTracks(audioLanguage: options.audioLanguage, subtitleLanguage: options.subtitleLanguage, subtitlesOff: options.subtitlesOff)
                : nil
        }
        if let remembered {
            restore(remembered)
        }
        appliesTrackPreferences = item.kind != .audio && !item.isPreview && remembered?.choosesTracks != true
        scrubPreviews.reset()
        hasPlayedCurrentItem = false
        didFallBackToVLC = false
        addedSubtitleURLs = []
        itemArtwork = nil
        if item.libraryID != nil {
            metadata = MediaMetadata(title: item.title, artist: item.artist, albumTitle: item.albumTitle)
        }
        setState(.opening)
        notify(.item)
        loadItemArtwork(for: item)

        if purpose == .main {
            // A clip playing behind a title gives way first (see `everyController`).
            await Self.stopPreviews()
            guard loadGeneration == generation else { return }
        }

        var decision: EngineRouter.Decision
        if let quick = router.quickDecision(for: item) {
            decision = quick
        } else {
            let probe = await prober.probe(item.url)
            guard loadGeneration == generation else { return }
            decision = router.decision(for: item, probe: probe)
        }
        // Only VLC has an equalizer; protected files can only play in AVFoundation.
        if equalizer.isEnabled, decision.engine == .avFoundation,
           decision.reason != .protectedContent, decision.reason != .itemOverride {
            decision = EngineRouter.Decision(engine: .vlc, reason: .equalizer)
        }
        if let remembered, remembered.needsVLC, decision.engine == .avFoundation,
           decision.reason != .protectedContent, decision.reason != .itemOverride {
            decision = EngineRouter.Decision(engine: .vlc, reason: .rememberedOptions)
        }
        // Only VLC can send to a Chromecast.
        if purpose == .main, CastingCenter.shared.isCasting, decision.engine == .avFoundation,
           decision.reason != .protectedContent {
            decision = EngineRouter.Decision(engine: .vlc, reason: .casting)
        }
        if purpose == .preview, decision.engine == .vlc, Self.playerHasVideo {
            setState(.failed(PlaybackError(.engineFailure, "The player is showing a video.")))
            return
        }
        routingReason = decision.reason
        await start(item, on: decision.engine, autoplay: autoplay, generation: loadGeneration)
    }

    private func start(_ item: PlaybackItem, on kind: EngineKind, autoplay: Bool, generation loadGeneration: Int) async {
        guard let engine = await prepareEngine(kind, generation: loadGeneration),
              loadGeneration == generation else { return }
        do {
            try await engine.load(engineItem(item))
            guard loadGeneration == generation else { return }
            engine.rate = rate
            engine.volume = engineVolume
            engine.isMuted = isMuted
            applyOptions(to: engine)
            // Timing remembered for this file.
            if audioDelay != 0, engine.capabilities.contains(.audioDelay) {
                engine.audioDelay = audioDelay
            }
            if subtitleDelay != 0, engine.capabilities.contains(.subtitleDelay) {
                engine.subtitleDelay = subtitleDelay
            }
            if autoplay {
                engine.play()
            } else if engine.state == .opening {
                // VLC doesn't open media until play(); report "ready".
                setState(.paused)
            }
        } catch {
            guard loadGeneration == generation else { return }
            if kind == .avFoundation {
                await fallBackToVLC()
            } else {
                setState(.failed(error as? PlaybackError ?? PlaybackError(.engineFailure, error.localizedDescription)))
            }
        }
    }

    /// Reuses the current engine when it's the right kind and still matches
    /// the configuration; otherwise retires it and installs a new one.
    /// Returns `nil` when a newer operation took over while waiting.
    private func prepareEngine(_ kind: EngineKind, generation loadGeneration: Int) async -> (any PlaybackEngine)? {
        if let engine, engine.kind == kind,
           kind != .vlc || engineOptionsFingerprint == factory.vlcOptionsFingerprint {
            return engine
        }
        await retireCurrentEngine(for: loadGeneration)
        guard loadGeneration == generation, engine == nil else { return nil }
        let newEngine = factory.makeEngine(kind)
        install(newEngine)
        return newEngine
    }

    private func install(_ newEngine: any PlaybackEngine) {
        engine = newEngine
        engineOptionsFingerprint = newEngine.kind == .vlc ? factory.vlcOptionsFingerprint : []
        activeEngine = newEngine.kind
        capabilities = newEngine.capabilities
        newEngine.attachVideoOutput(to: videoView)
        if purpose == .main, let avEngine = newEngine as? AVPlayerEngine, let layer = avEngine.playerLayer {
            pictureInPicture.use(playerLayer: layer)
        } else {
            // VLC offers Picture in Picture once its video output is ready.
            pictureInPicture.reset()
        }

        let engineID = ObjectIdentifier(newEngine)
        let events = newEngine.events
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                guard let current = self.engine, ObjectIdentifier(current) == engineID else { continue }
                self.handle(event)
            }
        }
    }

    /// Shuts the current engine down. Concurrent callers wait for the same
    /// shutdown, so nothing is installed (and then stripped by
    /// `removeEngineContent()`) while an old engine is still stopping.
    /// - Parameter operation: The caller's `generation`. After waiting, an
    ///   outdated caller must not retire the engine a newer operation installed
    ///   (waiters resume newest-first).
    private func retireCurrentEngine(for operation: Int) async {
        if let retirement {
            await retirement.value
            guard operation == generation else { return }
        }
        guard let oldEngine = engine else { return }
        engine = nil
        eventTask?.cancel()
        eventTask = nil
        pictureInPicture.reset()
        isExternalPlaybackActive = false
        oldEngine.attachVideoOutput(to: nil)
        let videoView = self.videoView
        let task = Task { @MainActor in
            await oldEngine.shutdown()
            videoView.removeEngineContent()
        }
        retirement = task
        await task.value
        if retirement == task {
            retirement = nil
        }
    }

    // MARK: - Transport

    public func play() {
        guard let engine else { return }
        if state == .ended, let item = currentItem, !engine.isSeekable {
            Task { await load(item) }
            return
        }
        engine.play()
    }

    public func pause() {
        engine?.pause()
    }

    public func togglePlayPause() {
        if isPlaying || state == .opening {
            pause()
        } else {
            play()
        }
    }

    /// Stops playback and unloads the item.
    public func stop() async {
        generation += 1
        let stopGeneration = generation
        await retireCurrentEngine(for: stopGeneration)
        guard stopGeneration == generation else { return } // a newer load owns the state now
        endSecurityScopedAccess()
        currentItem = nil
        resetMediaState()
        scrubPreviews.reset()
        activeEngine = nil
        routingReason = nil
        capabilities = []
        setState(.idle)
        notify(.item)
    }

    public func seek(to time: TimeInterval) async {
        guard let engine else { return }
        var target = max(0, time)
        if let duration {
            target = min(target, max(0, duration - 0.25))
        }
        currentTime = target
        // The engine counts from the start of the file, the item from its segment.
        let fileTarget = target + segmentOffset
        seekHold = (fileTarget, .now + .seconds(2))
        reachedSegmentEnd = false
        await engine.seek(to: fileTarget)
        notify(.seek)
        updatePictureInPicture(invalidate: true)
    }

    // MARK: - Segments

    /// Where the item's segment starts in its file (0 for a whole file).
    private var segmentOffset: TimeInterval {
        currentItem?.segment?.start ?? 0
    }

    /// The item as the engine opens it: a segment starts at its own start.
    private func engineItem(_ item: PlaybackItem) -> PlaybackItem {
        var opened = item
        if NetworkAddress.isShare(item.url) {
            // A login VLC asks for is filed under this share if remembered.
            NetworkLoginPrompt.shared.currentAddress = item.url
            if opened.credential == nil {
                opened.credential = networkCredentials?(item.url)
            }
        }
        guard let segment = item.segment else { return opened }
        opened.startPosition = segment.start + (item.startPosition ?? 0)
        return opened
    }

    /// Moves playback to the device chosen in the cast menu (through VLC),
    /// or back to this one, at the same place.
    private func castTargetChanged() async {
        guard let item = currentItem, !item.isPreview else { return }
        if CastingCenter.shared.isCasting, activeEngine == .avFoundation {
            if routingReason == .protectedContent { return }
            await handOff(to: .vlc)
            routingReason = .casting
        } else if activeEngine == .vlc {
            await restartEngine()
        }
    }

    /// Carries on into the next stretch of the same file (a cue sheet's next
    /// track) without opening it again, so there's no gap.
    public func continueInto(_ item: PlaybackItem) {
        guard let current = currentItem, current.url == item.url else { return }
        currentItem = item
        reachedSegmentEnd = false
        if let fileDuration {
            duration = item.segment?.duration(fileDuration: fileDuration) ?? fileDuration
        }
        metadata.title = item.title
        if let artist = item.artist {
            metadata.artist = artist
        }
        notify(.item)
        notify(.duration)
        updatePictureInPicture(invalidate: true)
    }

    public func skip(by seconds: TimeInterval) async {
        await seek(to: currentTime + seconds)
    }

    /// Call when a scrubber drag begins: time updates stop moving the thumb.
    public func beginScrubbing() {
        isScrubbing = true
    }

    /// Updates the displayed position during a drag without seeking.
    public func scrub(to time: TimeInterval) {
        guard isScrubbing else { return }
        currentTime = max(0, min(time, duration ?? time))
    }

    /// Ends a drag and seeks to where the user let go.
    public func endScrubbing(at time: TimeInterval) async {
        isScrubbing = false
        await seek(to: time)
    }

    public func setRate(_ newRate: Float) async {
        let clamped = min(max(newRate, 0.25), 4)
        if clamped > 2, !capabilities.contains(.highRates) {
            await handOff(to: .vlc)
        }
        rate = clamped
        engine?.rate = clamped
        notify(.rate)
    }

    /// 0…1, or up to 2 with the VLC engine (volume boost).
    public func setVolume(_ newVolume: Float) {
        volume = min(max(newVolume, 0), volumeLimit)
        engine?.volume = engineVolume
    }

    /// Up to 2 (200%): above 1, the item moves to VLC, which can boost.
    public func setBoostedVolume(_ newVolume: Float) async {
        if newVolume > VolumeLimits.normal, !capabilities.contains(.volumeBoost), currentItem != nil {
            await handOff(to: .vlc)
        }
        setVolume(newVolume)
    }

    /// Turns ReplayGain levelling on or off, or changes it, for this item and the next.
    public func setReplayGain(_ settings: ReplayGainSettings) {
        replayGain = settings
        updateReplayGainScale()
    }

    /// ReplayGain values read after the item started (levelling was just turned on).
    public func updateReplayGainValues(_ values: ReplayGainValues?) {
        guard currentItem != nil else { return }
        currentItem?.replayGain = values
        updateReplayGainScale()
    }

    /// Music is levelled; films keep their own sound.
    private func updateReplayGainScale() {
        if let item = currentItem, item.kind == .audio {
            replayGainScale = replayGain.scale(for: item.replayGain)
        } else {
            replayGainScale = 1
        }
        engine?.volume = engineVolume
    }

    private var volumeLimit: Float {
        capabilities.contains(.volumeBoost) ? VolumeLimits.boosted : VolumeLimits.normal
    }

    /// What the engine plays at: your volume, levelled by ReplayGain.
    private var engineVolume: Float {
        VolumeLimits.engineVolume(chosen: volume, replayGainScale: replayGainScale, limit: volumeLimit)
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        engine?.isMuted = muted
    }

    // MARK: - Tracks

    public func selectAudioTrack(_ track: MediaTrack) {
        pendingTrackRestore = nil // the user's choice wins over a pending restore
        appliesTrackPreferences = false
        var chosen = chosenTracks ?? currentTrackChoice()
        chosen.audioLanguage = audioTracks.count > 1 ? track.languageCode : nil
        chosenTracks = chosen
        engine?.selectAudioTrack(id: track.id)
        refreshTracks()
        rememberOptions()
    }

    /// Pass `nil` to turn subtitles off.
    public func selectSubtitleTrack(_ track: MediaTrack?) {
        pendingTrackRestore = nil
        appliesTrackPreferences = false
        var chosen = chosenTracks ?? currentTrackChoice()
        chosen.subtitleLanguage = track?.languageCode
        chosen.subtitlesOff = track == nil && !subtitleTracks.isEmpty
        chosenTracks = chosen
        engine?.selectSubtitleTrack(id: track?.id)
        refreshTracks()
        rememberOptions()
    }

    /// What's playing now, as a choice to remember.
    private func currentTrackChoice() -> ChosenTracks {
        let audio = audioTracks.first(where: \.isSelected)
        let subtitle = subtitleTracks.first(where: \.isSelected)
        return ChosenTracks(
            audioLanguage: audioTracks.count > 1 ? audio?.languageCode : nil,
            subtitleLanguage: subtitle?.languageCode,
            subtitlesOff: subtitle == nil && !subtitleTracks.isEmpty
        )
    }

    /// Shows a second subtitle track with the first (two languages at
    /// once), or hides it with `nil`. Needs VLC.
    public func selectSecondarySubtitleTrack(_ track: MediaTrack?) {
        guard capabilities.contains(.dualSubtitles) else { return }
        pendingTrackRestore = nil
        engine?.selectSecondarySubtitleTrack(id: track?.id)
        refreshTracks()
    }

    /// Loads a subtitle file (SRT, ASS/SSA, WebVTT…) and shows it. Switches to
    /// VLC first when the current engine can't load external subtitles.
    public func addExternalSubtitle(url: URL) async throws {
        if !capabilities.contains(.externalSubtitles) {
            await handOff(to: .vlc)
        }
        guard let engine else { return }
        appliesTrackPreferences = false
        beginSecurityScopedAccess(to: url, if: true)
        try await engine.addExternalSubtitle(url: url)
        addedSubtitleURLs.append(url)
    }

    /// Positive values delay the audio. Needs VLC; switches engines if necessary.
    public func setAudioDelay(_ seconds: TimeInterval) async {
        if !capabilities.contains(.audioDelay) {
            await handOff(to: .vlc)
        }
        audioDelay = seconds
        engine?.audioDelay = seconds
        rememberOptions()
    }

    /// Positive values show subtitles later. Needs VLC; switches engines if necessary.
    public func setSubtitleDelay(_ seconds: TimeInterval) async {
        if !capabilities.contains(.subtitleDelay) {
            await handOff(to: .vlc)
        }
        subtitleDelay = seconds
        engine?.subtitleDelay = seconds
        rememberOptions()
    }

    public func selectChapter(_ chapter: Chapter) {
        engine?.selectChapter(at: chapter.id)
        notify(.seek)
    }

    // MARK: - Titles and disc menus

    /// Plays a title (a disc's film, an episode, an extra, its menu) from its start.
    public func selectTitle(_ title: MediaTitle) {
        guard capabilities.contains(.discMenus) else { return }
        pendingDiscStart = nil
        engine?.selectTitle(at: title.id)
        notify(.seek)
    }

    /// The disc's remote: the arrows, Select and its menus.
    public func navigateDisc(_ action: DiscNavigation) {
        guard capabilities.contains(.discMenus) else { return }
        pendingDiscStart = nil
        engine?.navigate(action)
    }

    /// Picks a disc up where it was left: once VLC lists the titles, plays
    /// the title (the film when none was noted), then goes to the time.
    private func continueDiscStart() {
        guard let pending = pendingDiscStart, !titles.isEmpty else { return }
        guard let target = pending.title ?? mainTitle?.id else {
            pendingDiscStart = nil
            return
        }
        if currentTitleIndex == target {
            pendingDiscStart = nil
            let itemID = currentItem?.id
            let titleLength = titles.first { $0.id == target }?.duration ?? 0
            Task { [weak self] in
                // libVLC reports the title's length a moment after it starts;
                // seeking before that would be clamped to the menu's length.
                for _ in 0..<30 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, self.currentItem?.id == itemID else { return }
                    if titleLength < 1 || self.duration.map({ abs($0 - titleLength) < 1.5 }) == true {
                        break
                    }
                }
                guard let self, self.currentItem?.id == itemID, self.currentTitleIndex == target else { return }
                await self.seek(to: pending.time)
            }
        } else if !requestedDiscTitle {
            requestedDiscTitle = true
            engine?.selectTitle(at: target)
        }
    }

    // MARK: - Level 2 options

    /// Fit or fill the player. Both engines can.
    public func setFillMode(_ mode: VideoFillMode) {
        fillMode = mode
        engine?.fillMode = mode
    }

    /// Forces the picture's shape, or `nil` for the file's own. Needs VLC.
    public func setAspectRatio(_ ratio: VideoRatio?) async {
        if ratio != nil, !capabilities.contains(.aspectRatioOverride) {
            await handOff(to: .vlc)
        }
        aspectRatio = ratio
        if capabilities.contains(.aspectRatioOverride) {
            engine?.aspectRatio = ratio
        }
        rememberOptions()
    }

    /// Trims the picture to a shape, or `nil` for the whole picture. Needs VLC.
    public func setCropRatio(_ ratio: VideoRatio?) async {
        if ratio != nil, !capabilities.contains(.crop) {
            await handOff(to: .vlc)
        }
        cropRatio = ratio
        if capabilities.contains(.crop) {
            engine?.cropRatio = ratio
        }
        rememberOptions()
    }

    /// Brightness, contrast, saturation, hue and gamma. Needs VLC.
    public func setVideoAdjustments(_ adjustments: VideoAdjustments) async {
        let values = adjustments.clamped
        if !values.isNeutral, !capabilities.contains(.videoAdjustments) {
            await handOff(to: .vlc)
        }
        videoAdjustments = values
        if capabilities.contains(.videoAdjustments) {
            engine?.videoAdjustments = values
        }
    }

    /// Needs VLC.
    public func setDeinterlace(_ mode: DeinterlaceMode) async {
        if mode != .automatic, !capabilities.contains(.deinterlacing) {
            await handOff(to: .vlc)
        }
        deinterlace = mode
        if capabilities.contains(.deinterlacing) {
            engine?.deinterlace = mode
        }
        rememberOptions()
    }

    /// Which filter deinterlaces (Yadif, Bob, Film NTSC…). Needs VLC.
    public func setDeinterlaceFilter(_ filter: DeinterlaceFilter) async {
        if filter != .standard, deinterlace != .off, !capabilities.contains(.deinterlacing), currentItem != nil {
            await handOff(to: .vlc)
        }
        deinterlaceFilter = filter
        if capabilities.contains(.deinterlacing) {
            engine?.deinterlaceFilter = filter
        }
    }

    // MARK: Turning, mirroring and magnifying

    /// Turns and mirrors the picture. Both engines can: the video view does it.
    public func setTransform(_ newTransform: VideoTransform) {
        guard newTransform != transform else { return }
        transform = newTransform
        layoutVideoGeometry()
        rememberOptions()
    }

    /// A quarter turn, as seen on screen.
    public func rotate(clockwise: Bool = true) {
        setTransform(transform.rotated(clockwise: clockwise))
    }

    public func flipHorizontally() {
        setTransform(transform.flippedHorizontally())
    }

    public func flipVertically() {
        setTransform(transform.flippedVertically())
    }

    /// Magnifies the picture (1 shows all of it). Both engines can.
    public func setZoom(_ newZoom: VideoZoom) {
        guard newZoom != zoom else { return }
        zoom = newZoom
        layoutVideoGeometry()
    }

    // MARK: 360° video

    /// Where a 360° video looks. Needs VLC, which plays every 360° video.
    public func setViewpoint(_ newViewpoint: Viewpoint) {
        guard newViewpoint != viewpoint else { return }
        viewpoint = newViewpoint
        if capabilities.contains(.viewpoint360) {
            engine?.viewpoint = newViewpoint
        }
    }

    /// Mono, left or right only, swapped… Needs VLC.
    public func setStereoMode(_ mode: StereoMode) async {
        if mode != .automatic, !capabilities.contains(.stereoModes) {
            await handOff(to: .vlc)
        }
        stereoMode = mode
        if capabilities.contains(.stereoModes) {
            engine?.stereoMode = mode
        }
    }

    /// The equalizer is VLC's; while it's on, everything plays with VLC.
    public func setEqualizer(_ settings: EqualizerSettings) async {
        if settings.isEnabled, !capabilities.contains(.equalizer), currentItem != nil {
            await handOff(to: .vlc)
            routingReason = .equalizer
        }
        equalizer = settings
        if capabilities.contains(.equalizer) {
            engine?.equalizer = settings
        }
    }

    /// Subtitle text size. Needs VLC for anything but the default.
    public func setSubtitleSize(_ size: SubtitleSize) async {
        if size != .standard, !capabilities.contains(.subtitleStyling), !subtitleTracks.isEmpty {
            await handOff(to: .vlc)
        }
        subtitleSize = size
        if capabilities.contains(.subtitleStyling) {
            engine?.subtitleScale = size.scale
        }
    }

    /// Font, colour, outline, background and height of plain-text
    /// subtitles. AVFoundation restyles at once; VLC reads the style when it
    /// starts, so a VLC item with subtitles restarts at the same position.
    public func setSubtitleStyle(_ style: SubtitleStyle) async {
        guard style != subtitleStyle else { return }
        subtitleStyle = style
        updateFactoryConfiguration()
        if capabilities.contains(.subtitleStyling) {
            engine?.subtitleStyle = style
        }
        if activeEngine == .vlc, currentItem != nil, !subtitleTracks.isEmpty {
            await restartEngine()
        }
    }

    /// The character set of subtitle files that aren't Unicode (`nil`:
    /// automatic). A VLC item with subtitles restarts at the same position.
    public func setSubtitleEncoding(_ encoding: String?) async {
        guard encoding != subtitleEncoding else { return }
        subtitleEncoding = encoding
        updateFactoryConfiguration()
        if activeEngine == .vlc, currentItem != nil, !subtitleTracks.isEmpty {
            await restartEngine()
        }
    }

    private func updateFactoryConfiguration() {
        var effective = configuration
        // No style chosen here: VLC follows Subtitles & Captioning, as AVFoundation does.
        effective.subtitleStyle = subtitleStyle.isStandard ? SystemCaptionStyle.current() : subtitleStyle
        effective.subtitleEncoding = subtitleEncoding
        factory.configuration = effective
        router.alwaysUseVLC = configuration.alwaysUseVLC
    }

    /// Shows the next or previous frame (pausing first).
    public func stepFrame(forward: Bool) {
        guard let engine, capabilities.contains(.frameStepping) else { return }
        engine.stepFrame(forward: forward)
    }

    /// Saves the frame on screen to `url` as a PNG.
    public func saveSnapshot(to url: URL) async throws {
        guard let engine else {
            throw PlaybackError(.engineFailure, "Nothing is playing.")
        }
        try await engine.saveSnapshot(to: url)
    }

    /// Sets the loop's start, then its end, then clears it.
    public func advanceABLoop() {
        abLoop.advance(at: currentTime)
    }

    public func clearABLoop() {
        abLoop.clear()
    }

    /// The options this engine can take, after a load or a hand-off.
    private func applyOptions(to engine: any PlaybackEngine) {
        engine.fillMode = fillMode
        let available = engine.capabilities
        if available.contains(.aspectRatioOverride) { engine.aspectRatio = aspectRatio }
        if available.contains(.crop) { engine.cropRatio = cropRatio }
        if available.contains(.videoAdjustments) { engine.videoAdjustments = videoAdjustments }
        if available.contains(.deinterlacing) {
            engine.deinterlace = deinterlace
            engine.deinterlaceFilter = deinterlaceFilter
        }
        if available.contains(.viewpoint360) { engine.viewpoint = viewpoint }
        if available.contains(.stereoModes) { engine.stereoMode = stereoMode }
        if available.contains(.equalizer) { engine.equalizer = equalizer }
        if available.contains(.subtitleStyling) {
            engine.subtitleScale = subtitleSize.scale
            engine.subtitleStyle = subtitleStyle
        }
    }

    // MARK: - Remembered options and starting tracks

    /// Puts back what you chose for this file last time. Tracks are picked
    /// by language once the engine lists them.
    private func restore(_ options: FileOptions) {
        audioDelay = options.audioDelay
        subtitleDelay = options.subtitleDelay
        aspectRatio = options.aspectRatio
        cropRatio = options.cropRatio
        deinterlace = options.deinterlace
        if options.transform != transform {
            transform = options.transform
            layoutVideoGeometry()
        }
        if options.choosesTracks {
            pendingTrackRestore = TrackRestore(
                audioLanguage: options.audioLanguage,
                subtitleLanguage: options.subtitleLanguage,
                subtitlesOff: options.subtitlesOff
            )
        }
    }

    /// Hands the current choices to whoever remembers them (the session).
    private func rememberOptions() {
        guard let item = currentItem, item.kind != .audio, !item.isPreview, let onOptionsChosen else { return }
        let options = FileOptions(
            audioLanguage: chosenTracks?.audioLanguage,
            subtitleLanguage: chosenTracks?.subtitleLanguage,
            subtitlesOff: chosenTracks?.subtitlesOff ?? false,
            audioDelay: audioDelay,
            subtitleDelay: subtitleDelay,
            aspectRatio: aspectRatio,
            cropRatio: cropRatio,
            transform: transform,
            deinterlace: deinterlace
        )
        onOptionsChosen(item, options)
    }

    /// Picks the starting audio and subtitles from `trackPreferences`. VLC
    /// lists tracks a few at a time, so this runs again as they arrive, until
    /// the item has played a few seconds or you pick a track yourself.
    private func applyTrackPreferences(with engine: any PlaybackEngine) {
        if case .track(let id) = trackPreferences.audioChoice(from: engine.audioTracks) {
            engine.selectAudioTrack(id: id)
        }
        let audio = engine.audioTracks.first(where: \.isSelected)
        switch trackPreferences.subtitleChoice(from: engine.subtitleTracks, audio: audio, appLanguage: appLanguage) {
        case .keep:
            break
        case .off:
            engine.selectSubtitleTrack(id: nil)
        case .track(let id):
            engine.selectSubtitleTrack(id: id)
        }
    }

    // MARK: - Media info

    /// What's inside the current item, stream by stream.
    public func mediaInfo() async -> MediaInfo? {
        guard let engine else { return nil }
        return await engine.mediaInfo()
    }

    /// Live figures from the engine (bitrate, dropped pictures). Not
    /// observable: read it on a timer.
    public var statistics: PlaybackStatistics? {
        engine?.statistics
    }

    // MARK: - Picture in Picture and previews

    /// VLC's Picture in Picture reports in through the video view; its
    /// buttons drive this controller.
    private func connectPictureInPicture() {
        videoHost.windowRelay.setHandler { [weak self] window in
            guard let self, self.activeEngine == .vlc else { return }
            self.pictureInPicture.use(vlcWindow: window)
        }
        videoHost.mediaBridge.setActions(PictureInPictureMediaBridge.Actions(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            skip: { [weak self] seconds in await self?.skip(by: seconds) }
        ))
    }

    /// Keeps VLC's Picture in Picture window in step with playback.
    private func updatePictureInPicture(invalidate: Bool) {
        let snapshot = PictureInPictureMediaBridge.Snapshot(
            timeMilliseconds: Int64((currentTime * 1_000).rounded()),
            lengthMilliseconds: Int64(((duration ?? 0) * 1_000).rounded()),
            isPlaying: isPlaying,
            isSeekable: isSeekable
        )
        guard snapshot != lastPictureInPictureSnapshot else { return }
        lastPictureInPictureSnapshot = snapshot
        videoHost.mediaBridge.update(snapshot)
        if invalidate {
            pictureInPicture.playbackChanged()
        }
    }

    private func prepareScrubPreviews() {
        // Discs have no single timeline to make frames from.
        guard purpose == .main, state == .playing, let item = currentItem, item.disc == nil else { return }
        scrubPreviews.prepare(for: item, duration: duration, hasVideo: hasVideo)
    }

    // MARK: - Engine switching

    /// Moves the current item to another engine at the same position.
    public func switchEngine(to kind: EngineKind) async {
        await handOff(to: kind)
    }

    /// Human-readable libVLC version (creates the shared libVLC instance if needed).
    public var vlcVersionDescription: String {
        factory.vlcVersionDescription
    }

    /// Starts the item again in a new engine of the same kind at the same
    /// position, for options a running libVLC instance can't take (subtitle
    /// style, encoding). Tracks come back exactly as they were.
    private func restartEngine() async {
        guard let kind = activeEngine else { return }
        await handOff(to: kind, isRestart: true)
    }

    private func handOff(to kind: EngineKind, isRestart: Bool = false) async {
        guard var item = currentItem, let oldEngine = engine, oldEngine.kind != kind || isRestart else { return }
        generation += 1
        let handOffGeneration = generation
        if kind == .vlc {
            // One VLC video output at a time (see `everyController`).
            if purpose == .preview, Self.playerHasVideo {
                await stop()
                setState(.failed(PlaybackError(.engineFailure, "The player is showing a video.")))
                return
            }
            if purpose == .main {
                await Self.stopPreviews()
                guard handOffGeneration == generation else { return }
            }
        }

        let resumeAt = currentTime
        let shouldPlay = isPlaying || state == .opening
        let selectedAudio = audioTracks.first(where: \.isSelected)
        let selectedSubtitle = subtitleTracks.first(where: \.isSelected)
        var restore = TrackRestore(
            audioLanguage: selectedAudio?.languageCode,
            subtitleLanguage: selectedSubtitle?.languageCode,
            subtitlesOff: !subtitleTracks.isEmpty && selectedSubtitle == nil
        )
        if isRestart {
            restore.audioID = audioTracks.count > 1 ? selectedAudio?.id : nil
            restore.subtitleID = selectedSubtitle?.id
            restore.secondarySubtitleID = subtitleTracks.first(where: \.isSecondary)?.id
        }
        let previousReason = routingReason
        // A disc starts again at its menu; go back to the title and time instead.
        let discStart: (title: Int?, time: TimeInterval)? = item.disc != nil && !isShowingDiscMenu && resumeAt > 0.5
            ? (currentTitleIndex, resumeAt)
            : nil

        oldEngine.pause()
        await retireCurrentEngine(for: handOffGeneration)
        guard handOffGeneration == generation, engine == nil else { return }

        let newEngine = factory.makeEngine(kind)
        install(newEngine)
        routingReason = isRestart ? previousReason : .handoff
        pendingTrackRestore = restore.isFinished ? nil : restore
        if item.disc != nil {
            pendingDiscStart = discStart
            requestedDiscTitle = false
            item.startPosition = nil
        } else {
            item.startPosition = resumeAt > 0.5 ? resumeAt : nil
        }
        item = engineItem(item)
        item.externalSubtitleURLs += addedSubtitleURLs
        do {
            try await newEngine.load(item)
            guard handOffGeneration == generation else { return }
            newEngine.rate = rate
            newEngine.volume = engineVolume
            newEngine.isMuted = isMuted
            if audioDelay != 0, capabilities.contains(.audioDelay) {
                newEngine.audioDelay = audioDelay
            }
            if subtitleDelay != 0, capabilities.contains(.subtitleDelay) {
                newEngine.subtitleDelay = subtitleDelay
            }
            applyOptions(to: newEngine)
            if shouldPlay {
                newEngine.play()
            }
        } catch {
            guard handOffGeneration == generation else { return }
            setState(.failed(error as? PlaybackError ?? PlaybackError(.engineFailure, error.localizedDescription)))
        }
    }

    /// AVFoundation said it could play the file but failed. VLC gets one try.
    private func fallBackToVLC() async {
        guard !didFallBackToVLC else { return }
        didFallBackToVLC = true
        await handOff(to: .vlc)
        routingReason = .probeFailed
    }

    // MARK: - Events

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case .stateChanged(let newState):
            if case .failed = newState, activeEngine == .avFoundation, !hasPlayedCurrentItem, !didFallBackToVLC {
                Task { await fallBackToVLC() }
                return
            }
            if newState == .playing {
                hasPlayedCurrentItem = true
            }
            setState(newState)
            if newState == .playing {
                prepareScrubPreviews()
            }
        case .timeChanged(let time):
            guard !isScrubbing else { return }
            if let hold = seekHold {
                if abs(time - hold.target) < 1.5 || ContinuousClock.now > hold.deadline {
                    seekHold = nil
                } else {
                    return
                }
            }
            currentTime = max(0, time - segmentOffset)
            if let end = currentItem?.segment?.end, time >= end, !reachedSegmentEnd {
                // The segment is over; the session moves on (gaplessly within the file).
                reachedSegmentEnd = true
                notify(.endOfMedia)
                return
            }
            if let target = abLoop.jumpTarget(at: currentTime) {
                Task { await seek(to: target) }
            }
            // A few seconds in, the tracks are settled: preferences stop
            // applying (a disc's menu doesn't count; its film starts them again).
            if appliesTrackPreferences, hasPlayedCurrentItem, !isShowingDiscMenu,
               currentTime > (currentItem?.startPosition ?? 0) + 3 {
                appliesTrackPreferences = false
            }
            updatePictureInPicture(invalidate: false)
        case .durationChanged(let newDuration):
            fileDuration = newDuration
            if let segment = currentItem?.segment {
                duration = segment.duration(fileDuration: newDuration)
            } else {
                duration = newDuration
            }
            notify(.duration)
            updatePictureInPicture(invalidate: true)
            prepareScrubPreviews()
        case .bufferingChanged(let progress):
            bufferingProgress = progress
        case .rateChanged:
            notify(.rate)
        case .tracksChanged:
            refreshTracks()
        case .chaptersChanged:
            chapters = engine?.chapters ?? []
        case .titlesChanged:
            let previousTitle = currentTitleIndex
            titles = engine?.titles ?? []
            currentTitleIndex = engine?.currentTitleIndex
            if isDisc, currentTitleIndex != previousTitle, currentTitle.map({ !$0.isMenu }) == true {
                // A disc's film (or an extra) starts with tracks of its own:
                // the ones chosen for this disc, or your languages.
                if let chosen = chosenTracks {
                    pendingTrackRestore = TrackRestore(
                        audioLanguage: chosen.audioLanguage,
                        subtitleLanguage: chosen.subtitleLanguage,
                        subtitlesOff: chosen.subtitlesOff
                    )
                } else if !(currentItem?.isPreview ?? true) {
                    appliesTrackPreferences = true
                }
            }
            notify(.titles)
            continueDiscStart()
        case .videoDimensionsChanged(let dimensions):
            videoDimensions = dimensions
            prepareScrubPreviews()
        case .projectionChanged(let newProjection):
            projection = newProjection
            // Turning and magnifying don't apply to a sphere.
            layoutVideoGeometry()
        case .metadataChanged(let newMetadata):
            var merged = newMetadata
            if let item = currentItem, item.namesItself {
                merged.title = item.title
                merged.artist = item.libraryID != nil ? item.artist : item.artist ?? merged.artist
                merged.albumTitle = item.albumTitle ?? merged.albumTitle
            }
            if let itemArtwork {
                merged.artworkData = itemArtwork
            } else if merged.artworkData == nil {
                merged.artworkData = metadata.artworkData
            }
            metadata = merged
            notify(.metadata)
        case .externalPlaybackChanged(let isActive):
            isExternalPlaybackActive = isActive
        case .endOfMedia:
            currentTime = duration ?? currentTime
            notify(.endOfMedia)
        }
    }

    private func refreshTracks() {
        guard let engine else { return }
        audioTracks = engine.audioTracks
        subtitleTracks = engine.subtitleTracks

        // After a hand-off, re-select the same languages. VLC announces
        // tracks one at a time, so keep trying until each one is satisfied.
        if var restore = pendingTrackRestore {
            // Exact tracks first (a restart in the same kind of engine).
            if let id = restore.audioID, let match = audioTracks.first(where: { $0.id == id }) {
                if !match.isSelected {
                    engine.selectAudioTrack(id: id)
                }
                restore.audioID = nil
                restore.audioLanguage = nil
            }
            if let id = restore.subtitleID, let match = subtitleTracks.first(where: { $0.id == id }) {
                if !match.isSelected {
                    engine.selectSubtitleTrack(id: id)
                }
                restore.subtitleID = nil
                restore.subtitleLanguage = nil
            }
            if restore.subtitleID == nil, let id = restore.secondarySubtitleID,
               subtitleTracks.contains(where: { $0.id == id }) {
                engine.selectSecondarySubtitleTrack(id: id)
                restore.secondarySubtitleID = nil
            }
            if let language = restore.audioLanguage,
               let match = audioTracks.first(where: { MediaTrack.languagesMatch($0.languageCode, language) }) {
                if !match.isSelected {
                    engine.selectAudioTrack(id: match.id)
                }
                restore.audioLanguage = nil
            }
            if let language = restore.subtitleLanguage,
               let match = subtitleTracks.first(where: { MediaTrack.languagesMatch($0.languageCode, language) }) {
                engine.selectSubtitleTrack(id: match.id)
                restore.subtitleLanguage = nil
            } else if restore.subtitlesOff, !subtitleTracks.isEmpty {
                engine.selectSubtitleTrack(id: nil)
                restore.subtitlesOff = false
            }
            pendingTrackRestore = restore.isFinished ? nil : restore
            audioTracks = engine.audioTracks
            subtitleTracks = engine.subtitleTracks
        } else if appliesTrackPreferences, !audioTracks.isEmpty {
            applyTrackPreferences(with: engine)
            audioTracks = engine.audioTracks
            subtitleTracks = engine.subtitleTracks
        }
        notify(.tracks)
    }

    private func setState(_ newState: PlaybackState) {
        isSeekable = engine?.isSeekable ?? false
        guard newState != state else { return }
        state = newState
        notify(.state)
        updatePictureInPicture(invalidate: true)
    }

    private func resetMediaState() {
        currentTime = currentItem?.startPosition ?? 0
        duration = nil
        bufferingProgress = 1
        audioTracks = []
        subtitleTracks = []
        chapters = []
        titles = []
        currentTitleIndex = nil
        videoDimensions = nil
        metadata = MediaMetadata()
        audioDelay = 0
        subtitleDelay = 0
        isSeekable = false
        isScrubbing = false
        seekHold = nil
        pendingTrackRestore = nil
        aspectRatio = nil
        cropRatio = nil
        videoAdjustments = .neutral
        deinterlace = .automatic
        abLoop.clear()
        projection = .flat
        viewpoint = .straightAhead
        reachedSegmentEnd = false
        fileDuration = nil
        if !transform.isIdentity || zoom.isZoomed {
            transform = .identity
            zoom = .none
            layoutVideoGeometry()
        }
    }

    private func notify(_ change: Change) {
        onChange?(change)
    }

    // MARK: - Item artwork

    /// Reads the artwork file the library pointed at, off the main actor.
    private func loadItemArtwork(for item: PlaybackItem) {
        guard let url = item.artworkURL, url.isFileURL else { return }
        Task { [weak self] in
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url, options: .mappedIfSafe)
            }.value
            // Hand-offs bump the generation but keep the item, so compare items.
            guard let self, let data, self.currentItem?.id == item.id else { return }
            self.itemArtwork = data
            self.metadata.artworkData = data
            self.notify(.metadata)
        }
    }

    // MARK: - Security-scoped access

    private func beginSecurityScopedAccess(to url: URL, if needed: Bool) {
        guard needed, url.isFileURL, !securityScopedURLs.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(url)
        }
    }

    private func endSecurityScopedAccess() {
        Self.endAccess(to: securityScopedURLs)
        securityScopedURLs.removeAll()
    }

    private static func endAccess(to urls: [URL]) {
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

#if DEBUG
extension PlaybackController {
    /// Makes the controller look as if something is playing, without any
    /// media: for SwiftUI previews and the player's snapshot tests.
    public func showPreview(
        item: PlaybackItem,
        duration: TimeInterval,
        time: TimeInterval,
        isPlaying: Bool,
        dimensions: VideoDimensions? = nil,
        chapters: [Chapter] = [],
        titles: [MediaTitle] = [],
        currentTitleIndex: Int? = nil,
        audioTracks: [MediaTrack] = [],
        subtitleTracks: [MediaTrack] = [],
        artwork: Data? = nil
    ) {
        currentItem = item
        self.duration = duration
        currentTime = time
        state = isPlaying ? .playing : .paused
        videoDimensions = dimensions
        self.chapters = chapters
        self.titles = titles
        self.currentTitleIndex = currentTitleIndex
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        metadata = MediaMetadata(title: item.title, artist: item.artist, albumTitle: item.albumTitle, artworkData: artwork)
        isSeekable = true
        activeEngine = .vlc
        capabilities = .vlc
        routingReason = .unsupportedContainer("mkv")
    }
}
#endif


private extension PlaybackItem {
    /// Library items and a cue sheet's tracks carry their own title, which
    /// wins over what the engine reads from the file.
    var namesItself: Bool {
        libraryID != nil || segment != nil
    }
}
