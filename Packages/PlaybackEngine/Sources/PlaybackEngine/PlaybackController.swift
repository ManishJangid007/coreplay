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
        case endOfMedia
    }

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

    public var isPlaying: Bool {
        state == .playing || state == .buffering
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
        if let item = currentItem, item.libraryID != nil {
            return item.title
        }
        return metadata.title ?? currentItem?.title ?? ""
    }

    public var displaySubtitle: String? {
        if let item = currentItem, item.libraryID != nil {
            return item.artist
        }
        return metadata.artist ?? currentItem?.artist
    }

    public var configuration: EngineConfiguration {
        didSet {
            factory.configuration = configuration
            router.alwaysUseVLC = configuration.alwaysUseVLC
        }
    }

    /// The single view all engines render into. See `VideoSurface`.
    public let videoView = PlatformVideoView(frame: .zero)

    // MARK: Internals

    @ObservationIgnored public var onChange: (@MainActor (Change) -> Void)?
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

    private struct TrackRestore {
        var audioLanguage: String?
        var subtitleLanguage: String?
        var subtitlesOff: Bool

        var isFinished: Bool {
            audioLanguage == nil && subtitleLanguage == nil && !subtitlesOff
        }
    }

    public init(configuration: EngineConfiguration = EngineConfiguration()) {
        self.configuration = configuration
        self.router = EngineRouter(alwaysUseVLC: configuration.alwaysUseVLC)
        self.factory = EngineFactory(configuration: configuration)
    }

    // MARK: - Loading

    /// Opens `item` with the engine the router picks, and starts playing unless `autoplay` is false.
    public func load(_ item: PlaybackItem, autoplay: Bool = true) async {
        generation += 1
        let loadGeneration = generation

        // Keep the previous item's file access until its engine has stopped
        // reading it (that happens before this method returns).
        let previousScopedURLs = securityScopedURLs
        securityScopedURLs = []
        defer { Self.endAccess(to: previousScopedURLs) }
        beginSecurityScopedAccess(to: item.url, if: item.requiresSecurityScope)
        for subtitleURL in item.externalSubtitleURLs {
            beginSecurityScopedAccess(to: subtitleURL, if: item.requiresSecurityScope)
        }

        currentItem = item
        resetMediaState()
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

        let decision: EngineRouter.Decision
        if let quick = router.quickDecision(for: item) {
            decision = quick
        } else {
            let probe = await prober.probe(item.url)
            guard loadGeneration == generation else { return }
            decision = router.decision(for: item, probe: probe)
        }
        routingReason = decision.reason
        await start(item, on: decision.engine, autoplay: autoplay, generation: loadGeneration)
    }

    private func start(_ item: PlaybackItem, on kind: EngineKind, autoplay: Bool, generation loadGeneration: Int) async {
        guard let engine = await prepareEngine(kind, generation: loadGeneration),
              loadGeneration == generation else { return }
        do {
            try await engine.load(item)
            guard loadGeneration == generation else { return }
            engine.rate = rate
            engine.volume = volume
            engine.isMuted = isMuted
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
        seekHold = (target, .now + .seconds(2))
        await engine.seek(to: target)
        notify(.seek)
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
        let limit: Float = capabilities.contains(.volumeBoost) ? 2 : 1
        volume = min(max(newVolume, 0), limit)
        engine?.volume = volume
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        engine?.isMuted = muted
    }

    // MARK: - Tracks

    public func selectAudioTrack(_ track: MediaTrack) {
        pendingTrackRestore = nil // the user's choice wins over a pending restore
        engine?.selectAudioTrack(id: track.id)
        refreshTracks()
    }

    /// Pass `nil` to turn subtitles off.
    public func selectSubtitleTrack(_ track: MediaTrack?) {
        pendingTrackRestore = nil
        engine?.selectSubtitleTrack(id: track?.id)
        refreshTracks()
    }

    /// Loads a subtitle file (SRT, ASS/SSA, WebVTT…) and shows it. Switches to
    /// VLC first when the current engine can't load external subtitles.
    public func addExternalSubtitle(url: URL) async throws {
        if !capabilities.contains(.externalSubtitles) {
            await handOff(to: .vlc)
        }
        guard let engine else { return }
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
    }

    /// Positive values show subtitles later. Needs VLC; switches engines if necessary.
    public func setSubtitleDelay(_ seconds: TimeInterval) async {
        if !capabilities.contains(.subtitleDelay) {
            await handOff(to: .vlc)
        }
        subtitleDelay = seconds
        engine?.subtitleDelay = seconds
    }

    public func selectChapter(_ chapter: Chapter) {
        engine?.selectChapter(at: chapter.id)
        notify(.seek)
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

    private func handOff(to kind: EngineKind) async {
        guard var item = currentItem, let oldEngine = engine, oldEngine.kind != kind else { return }
        generation += 1
        let handOffGeneration = generation

        let resumeAt = currentTime
        let shouldPlay = isPlaying || state == .opening
        let selectedAudio = audioTracks.first(where: \.isSelected)
        let selectedSubtitle = subtitleTracks.first(where: \.isSelected)
        let restore = TrackRestore(
            audioLanguage: selectedAudio?.languageCode,
            subtitleLanguage: selectedSubtitle?.languageCode,
            subtitlesOff: !subtitleTracks.isEmpty && selectedSubtitle == nil
        )

        oldEngine.pause()
        await retireCurrentEngine(for: handOffGeneration)
        guard handOffGeneration == generation, engine == nil else { return }

        let newEngine = factory.makeEngine(kind)
        install(newEngine)
        routingReason = .handoff
        pendingTrackRestore = restore.isFinished ? nil : restore
        item.startPosition = resumeAt > 0.5 ? resumeAt : nil
        item.externalSubtitleURLs += addedSubtitleURLs
        do {
            try await newEngine.load(item)
            guard handOffGeneration == generation else { return }
            newEngine.rate = rate
            newEngine.volume = min(volume, capabilities.contains(.volumeBoost) ? 2 : 1)
            newEngine.isMuted = isMuted
            if audioDelay != 0, capabilities.contains(.audioDelay) {
                newEngine.audioDelay = audioDelay
            }
            if subtitleDelay != 0, capabilities.contains(.subtitleDelay) {
                newEngine.subtitleDelay = subtitleDelay
            }
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
        case .timeChanged(let time):
            guard !isScrubbing else { return }
            if let hold = seekHold {
                if abs(time - hold.target) < 1.5 || ContinuousClock.now > hold.deadline {
                    seekHold = nil
                } else {
                    return
                }
            }
            currentTime = time
        case .durationChanged(let newDuration):
            duration = newDuration
            notify(.duration)
        case .bufferingChanged(let progress):
            bufferingProgress = progress
        case .rateChanged:
            notify(.rate)
        case .tracksChanged:
            refreshTracks()
        case .chaptersChanged:
            chapters = engine?.chapters ?? []
        case .videoDimensionsChanged(let dimensions):
            videoDimensions = dimensions
        case .metadataChanged(let newMetadata):
            var merged = newMetadata
            if let item = currentItem, item.libraryID != nil {
                merged.title = item.title
                merged.artist = item.artist
                merged.albumTitle = item.albumTitle ?? merged.albumTitle
            }
            if let itemArtwork {
                merged.artworkData = itemArtwork
            } else if merged.artworkData == nil {
                merged.artworkData = metadata.artworkData
            }
            metadata = merged
            notify(.metadata)
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
        }
        notify(.tracks)
    }

    private func setState(_ newState: PlaybackState) {
        isSeekable = engine?.isSeekable ?? false
        guard newState != state else { return }
        state = newState
        notify(.state)
    }

    private func resetMediaState() {
        currentTime = currentItem?.startPosition ?? 0
        duration = nil
        bufferingProgress = 1
        audioTracks = []
        subtitleTracks = []
        chapters = []
        videoDimensions = nil
        metadata = MediaMetadata()
        audioDelay = 0
        subtitleDelay = 0
        isSeekable = false
        isScrubbing = false
        seekHold = nil
        pendingTrackRestore = nil
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
