import Foundation
import Observation
import PlaybackCore
import PlaybackEngine

#if os(iOS)
import UIKit
#endif

/// Everything about "what's playing" in one observable object: the engine
/// controller, the Up Next queue, and the system integrations (Now Playing
/// info, remote commands, audio session). The app creates one and puts it in
/// the SwiftUI environment.
@MainActor
@Observable
public final class PlaybackSession {
    public let controller: PlaybackController
    public private(set) var queue = PlaybackQueue()
    /// A short message for the player to show ("Saved to Pictures"), for
    /// actions that happen outside it (menus, shortcuts).
    public private(set) var announcement: Announcement?

    public struct Announcement: Hashable, Sendable {
        public let id: UUID
        public let message: String
    }

    public func announce(_ message: String) {
        announcement = Announcement(id: UUID(), message: message)
    }

    /// Reads a music file's ReplayGain values (the app reads its tags).
    /// Called just before each song plays.
    @ObservationIgnored public var replayGainLookup: (@Sendable (URL) async -> ReplayGainValues?)?

    /// Finds subtitles online: OpenSubtitles with your key, when one is
    /// saved in Settings (`nil` otherwise, and the player offers no search).
    public var onlineSubtitles: (any OnlineSubtitleProvider)?
    /// Describes what's playing for a subtitle search: the app fills in the
    /// library's title, IMDb IDs and episode numbers.
    @ObservationIgnored public var subtitleSearchRequest: (@MainActor (PlaybackItem) -> SubtitleSearchRequest)?
    /// Finds a song's lyrics (the app reads tags, `.lrc` files and, if
    /// allowed, LRCLIB). `nil` shows "No Lyrics".
    @ObservationIgnored public var lyricsLookup: (@MainActor (PlaybackItem) async -> Lyrics?)?

    /// What you chose for each video (tracks, timing, picture), most recent kept.
    @ObservationIgnored private var fileOptions = FileOptionsStore()
    @ObservationIgnored private var fileOptionsSaveTask: Task<Void, Never>?

    @ObservationIgnored private let nowPlaying = NowPlayingInfoPublisher()
    @ObservationIgnored private let remoteCommands = RemoteCommandController()
    /// What the user asked for, independent of what the engine is doing right
    /// now (AVPlayer may already be paused by the system when an interruption begins).
    @ObservationIgnored private var wantsPlayback = false
    #if os(iOS)
    @ObservationIgnored private let audioSession = AudioSessionController()
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []
    #endif

    public init(configuration: EngineConfiguration = EngineConfiguration()) {
        controller = PlaybackController(configuration: configuration)
        controller.onChange = { [weak self] change in
            self?.controllerDidChange(change)
        }
        remoteCommands.install(for: self)
        updateRemoteCommands()
        restorePreferences()
        connectFileOptions()
        #if os(iOS)
        audioSession.onEvent = { [weak self] event in
            self?.handleAudioSessionEvent(event)
        }
        observeAppLifecycle()
        #endif
    }

    // MARK: - Reading

    public var currentItem: PlaybackItem? { controller.currentItem }

    /// `true` when something is loaded (playing or paused).
    public var hasItem: Bool { controller.currentItem != nil }

    public var upNext: [PlaybackItem] { queue.upNext }

    // MARK: - Starting playback

    /// Replaces the queue with `items` and plays from `index`.
    /// - Parameter shuffled: Turns shuffle on or off first (Apple Music's Play
    ///   and Shuffle buttons); `nil` keeps the current setting, as tapping a song does.
    public func play(_ items: [PlaybackItem], startingAt index: Int = 0, shuffled: Bool? = nil) async {
        guard !items.isEmpty else { return }
        if let shuffled {
            queue.setShuffle(shuffled)
        }
        queue.replace(with: items, startingAt: index)
        await loadCurrent()
    }

    /// Shuffle: starts with a random item and shuffles the rest.
    public func playShuffled(_ items: [PlaybackItem]) async {
        guard !items.isEmpty else { return }
        await play(items, startingAt: Int.random(in: items.indices), shuffled: true)
    }

    public func play(_ item: PlaybackItem) async {
        await play([item])
    }

    public func playNext(_ items: [PlaybackItem]) {
        let wasEmpty = queue.isEmpty
        queue.playNext(items)
        updateRemoteCommands()
        if wasEmpty {
            Task { await loadCurrent() }
        }
    }

    public func playLater(_ items: [PlaybackItem]) {
        let wasEmpty = queue.isEmpty
        queue.playLater(items)
        updateRemoteCommands()
        if wasEmpty {
            Task { await loadCurrent() }
        }
    }

    // MARK: - Transport

    public func play() {
        wantsPlayback = true
        activateAudioSession()
        controller.play()
    }

    public func pause() {
        wantsPlayback = false
        controller.pause()
    }

    public func togglePlayPause() {
        if controller.isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func stop() async {
        wantsPlayback = false
        queue.clear()
        await controller.stop()
        // A new item may have started while the old one was stopping.
        guard controller.currentItem == nil else { return }
        nowPlaying.clear()
        updateRemoteCommands()
        #if os(iOS)
        audioSession.deactivate()
        #endif
    }

    /// Next item in the queue (the Next button).
    public func next() async {
        guard let item = queue.advance(automatic: false) else { return }
        await load(item)
    }

    /// Restarts the current item, or goes to the previous one when pressed
    /// within the first three seconds, like Apple Music.
    public func previous() async {
        if controller.currentTime > 3 {
            await controller.seek(to: 0)
            return
        }
        if let item = queue.goBack() {
            await load(item)
        } else {
            await controller.seek(to: 0)
        }
    }

    public func seek(to time: TimeInterval) async {
        await controller.seek(to: time)
    }

    public func skip(by seconds: TimeInterval) async {
        await controller.skip(by: seconds)
    }

    public func setRate(_ rate: Float) async {
        await controller.setRate(rate)
    }

    // MARK: - Queue

    public var repeatMode: PlaybackQueue.RepeatMode {
        get { queue.repeatMode }
        set {
            queue.repeatMode = newValue
            updateRemoteCommands()
        }
    }

    public var isShuffled: Bool { queue.isShuffled }

    public func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        updateRemoteCommands()
    }

    public func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    /// Plays an item from Up Next.
    public func jump(to item: PlaybackItem) async {
        guard let target = queue.jump(to: item.id) else { return }
        await load(target)
    }

    public func removeFromQueue(_ item: PlaybackItem) {
        queue.remove(id: item.id)
        updateRemoteCommands()
    }

    public func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpNext(fromOffsets: source, toOffset: destination)
    }

    public func clearUpNext() {
        queue.clearUpNext()
        updateRemoteCommands()
    }

    // MARK: - Sleep timer

    public enum SleepTimer: Hashable, Sendable {
        case minutes(Int)
        /// Stops when the song or video playing now ends.
        case endOfItem
    }

    /// The sleep timer that's set, if any.
    public private(set) var sleepTimer: SleepTimer?
    /// When a minutes timer stops playback.
    public private(set) var sleepDeadline: Date?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

    /// Sets (or with `nil` cancels) the sleep timer. A minutes timer fades
    /// the sound out over its last ten seconds, then pauses.
    public func setSleepTimer(_ timer: SleepTimer?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = timer
        sleepDeadline = nil
        guard case .minutes(let minutes) = timer else { return }
        let deadline = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        sleepDeadline = deadline
        sleepTask = Task { [weak self] in
            let fade: TimeInterval = 10
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow - fade)))
            guard !Task.isCancelled else { return }
            await self?.fadeOutAndSleep(over: fade)
        }
    }

    private func fadeOutAndSleep(over seconds: TimeInterval) async {
        let volume = controller.volume
        let steps = 20
        for step in 1...steps {
            guard !Task.isCancelled else {
                controller.setVolume(volume)
                return
            }
            controller.setVolume(volume * Float(steps - step) / Float(steps))
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
        }
        pause()
        controller.setVolume(volume)
        sleepTimer = nil
        sleepDeadline = nil
        sleepTask = nil
    }

    // MARK: - Remembered preferences

    /// Turns the equalizer on or off or changes it; remembered between launches.
    public func setEqualizer(_ settings: EqualizerSettings) async {
        await controller.setEqualizer(settings)
        Self.save(settings, forKey: Self.equalizerKey)
    }

    /// Levels songs to the same loudness with their ReplayGain values (Sound
    /// Check); remembered between launches.
    public func setReplayGain(_ settings: ReplayGainSettings) async {
        // A song that started with levelling off hasn't had its values read.
        if settings.mode != .off, var item = controller.currentItem, item.kind == .audio, item.replayGain == nil,
           let lookup = replayGainLookup {
            item.replayGain = await lookup(item.url)
            if item.replayGain != nil, controller.currentItem?.id == item.id {
                controller.updateReplayGainValues(item.replayGain)
            }
        }
        controller.setReplayGain(settings)
        Self.save(settings, forKey: Self.replayGainKey)
    }

    // MARK: - Subtitles online

    /// Subtitles on offer for what's playing, best first.
    public func searchOnlineSubtitles(languages: [String]) async throws -> [OnlineSubtitle] {
        guard let provider = onlineSubtitles, let item = controller.currentItem else { return [] }
        var request = subtitleSearchRequest?(item) ?? SubtitleSearchRequest(fileURL: item.url, title: item.title)
        request.languages = languages
        return try await provider.search(request)
    }

    /// Downloads a subtitle file and shows it (VLC takes over if needed).
    public func addOnlineSubtitle(_ subtitle: OnlineSubtitle) async throws {
        guard let provider = onlineSubtitles else { return }
        let url = try await provider.download(subtitle)
        try await controller.addExternalSubtitle(url: url)
    }

    /// Subtitle text size; remembered between launches.
    public func setSubtitleSize(_ size: SubtitleSize) async {
        await controller.setSubtitleSize(size)
        UserDefaults.standard.set(size.rawValue, forKey: Self.subtitleSizeKey)
    }

    /// Subtitle font, colour, outline, background and height; remembered between launches.
    public func setSubtitleStyle(_ style: SubtitleStyle) async {
        await controller.setSubtitleStyle(style)
        Self.save(style, forKey: Self.subtitleStyleKey)
    }

    /// The character set for subtitle files that aren't Unicode (`nil`:
    /// automatic); remembered between launches.
    public func setSubtitleEncoding(_ encoding: String?) async {
        await controller.setSubtitleEncoding(encoding)
        if let encoding {
            UserDefaults.standard.set(encoding, forKey: Self.subtitleEncodingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.subtitleEncodingKey)
        }
    }

    private static let equalizerKey = "player.equalizer"
    private static let replayGainKey = "player.replayGain"
    private static let trackPreferencesKey = "player.trackPreferences"
    private static let fileOptionsKey = "player.fileOptions"

    /// Which audio and subtitles videos start with; remembered between launches.
    public func setTrackPreferences(_ preferences: TrackPreferences) {
        controller.trackPreferences = preferences
        Self.save(preferences, forKey: Self.trackPreferencesKey)
    }

    /// Forgets every file's remembered options.
    public func forgetFileOptions() {
        fileOptions = FileOptionsStore()
        UserDefaults.standard.removeObject(forKey: Self.fileOptionsKey)
    }

    /// The controller asks for, and reports, each video's options.
    private func connectFileOptions() {
        if let stored: FileOptionsStore = Self.load(forKey: Self.fileOptionsKey) {
            fileOptions = stored
        }
        controller.rememberedOptions = { [weak self] item in
            guard let self, PlaybackPreferences.remembersFileOptions else { return nil }
            return self.fileOptions.options(for: FileOptionsStore.key(for: item))
        }
        controller.onOptionsChosen = { [weak self] item, options in
            guard let self, PlaybackPreferences.remembersFileOptions else { return }
            self.fileOptions.set(options, for: FileOptionsStore.key(for: item))
            self.saveFileOptionsSoon()
        }
    }

    /// Timing sliders change many times a second: save once they settle.
    private func saveFileOptionsSoon() {
        fileOptionsSaveTask?.cancel()
        fileOptionsSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            Self.save(self.fileOptions, forKey: Self.fileOptionsKey)
        }
    }
    private static let subtitleSizeKey = "player.subtitleSize"
    private static let subtitleStyleKey = "player.subtitleStyle"
    private static let subtitleEncodingKey = "player.subtitleEncoding"

    private func restorePreferences() {
        if let replayGain: ReplayGainSettings = Self.load(forKey: Self.replayGainKey) {
            controller.setReplayGain(replayGain)
        }
        if let trackPreferences: TrackPreferences = Self.load(forKey: Self.trackPreferencesKey) {
            controller.trackPreferences = trackPreferences
        }
        let equalizer: EqualizerSettings? = Self.load(forKey: Self.equalizerKey)
        let subtitleSize = UserDefaults.standard.string(forKey: Self.subtitleSizeKey).flatMap(SubtitleSize.init(rawValue:))
        let subtitleStyle: SubtitleStyle? = Self.load(forKey: Self.subtitleStyleKey)
        let subtitleEncoding = UserDefaults.standard.string(forKey: Self.subtitleEncodingKey)
        guard equalizer != nil || subtitleSize != nil || subtitleStyle != nil || subtitleEncoding != nil else { return }
        Task {
            if let equalizer {
                await controller.setEqualizer(equalizer)
            }
            if let subtitleSize {
                await controller.setSubtitleSize(subtitleSize)
            }
            if let subtitleStyle {
                await controller.setSubtitleStyle(subtitleStyle)
            }
            if let subtitleEncoding {
                await controller.setSubtitleEncoding(subtitleEncoding)
            }
        }
    }

    private static func save<Value: Encodable>(_ value: Value, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<Value: Decodable>(forKey key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    // MARK: - Previews

    /// Call before a hero carousel clip starts. On iOS it keeps the clip from
    /// interrupting audio from other apps (see `AudioSessionController`).
    public func preparePreviewAudio() {
        #if os(iOS)
        audioSession.prepareForPreview()
        #endif
    }

    // MARK: - Engine configuration

    public func updateConfiguration(_ configuration: EngineConfiguration) {
        guard controller.configuration != configuration else { return }
        controller.configuration = configuration
    }

    // MARK: - Internals

    private func loadCurrent() async {
        guard let item = queue.currentItem else { return }
        await load(item)
    }

    private func load(_ item: PlaybackItem) async {
        wantsPlayback = true
        activateAudioSession(isVideo: item.kind == .video)
        var item = item
        if item.kind == .audio, item.replayGain == nil, controller.replayGain.mode != .off, let lookup = replayGainLookup {
            // A few milliseconds of tag reading, so the song starts at its level.
            item.replayGain = await lookup(item.url)
        }
        await controller.load(item)
        updateRemoteCommands()
    }

    private func activateAudioSession(isVideo: Bool? = nil) {
        #if os(iOS)
        audioSession.activate(forVideo: isVideo ?? controller.hasVideo)
        #endif
    }

    private func controllerDidChange(_ change: PlaybackController.Change) {
        switch change {
        case .item, .metadata, .duration, .titles:
            publishItem()
            publishPlayback()
        case .state, .seek, .rate:
            publishPlayback()
        case .tracks:
            break
        case .endOfMedia:
            Task { await advanceAfterEnd() }
        }
        updateRemoteCommands()
    }

    private func advanceAfterEnd() async {
        if sleepTimer == .endOfItem {
            // The sleep timer was set to the end of this item.
            setSleepTimer(nil)
            wantsPlayback = false
            publishPlayback()
            return
        }
        if controller.hasVideo, queue.hasNext, !PlaybackPreferences.autoplaysNextEpisode {
            // Autoplay is off: stay on the last frame, where the player
            // offers the next episode.
            wantsPlayback = false
            publishPlayback()
            return
        }
        let finished = controller.currentItem
        if let item = queue.advance(automatic: true) {
            if let finished, finished.url == item.url, let segment = finished.segment, let next = item.segment,
               segment.continues(into: next) {
                // The next track of a cue sheet: same file, so carry straight on.
                controller.continueInto(item)
                updateRemoteCommands()
            } else {
                await load(item)
            }
        } else {
            wantsPlayback = false // the queue finished: nothing to resume after an interruption
            if finished?.segment?.end != nil {
                // The track ended inside its file: stop there.
                controller.pause()
            }
            publishPlayback()
        }
    }

    private func publishItem() {
        guard let item = controller.currentItem else {
            nowPlaying.clear()
            return
        }
        nowPlaying.updateItem(
            title: controller.displayTitle,
            artist: controller.displaySubtitle,
            albumTitle: controller.metadata.albumTitle ?? item.albumTitle,
            artworkData: controller.metadata.artworkData,
            duration: controller.duration,
            isVideo: controller.hasVideo,
            assetURL: item.url
        )
    }

    private func publishPlayback() {
        guard controller.currentItem != nil else { return }
        nowPlaying.updatePlayback(
            elapsed: controller.currentTime,
            rate: controller.rate,
            isPlaying: controller.isPlaying
        )
    }

    private func updateRemoteCommands() {
        remoteCommands.update(
            isVideo: controller.hasVideo,
            hasNext: queue.hasNext,
            isSeekable: controller.isSeekable,
            hasItem: controller.currentItem != nil
        )
    }

    #if os(iOS)
    private func handleAudioSessionEvent(_ event: AudioSessionController.Event) {
        switch event {
        case .interruptionBegan:
            resumeAfterInterruption = wantsPlayback
            controller.pause()
        case .interruptionEnded(let shouldResume):
            if shouldResume, resumeAfterInterruption {
                play()
            }
            resumeAfterInterruption = false
        case .outputDeviceLost:
            // Headphones unplugged: pause rather than blast through the speaker.
            pause()
        }
    }

    /// Video keeps playing in Picture in Picture when the app goes to the
    /// background (AVFoundation starts it by itself); otherwise it pauses,
    /// since nothing would show it. Audio keeps playing.
    private func observeAppLifecycle() {
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.controller.hasVideo, self.controller.isPlaying else { return }
                let pip = self.controller.pictureInPicture
                let startsAutomatically = pip.isPossible && self.controller.activeEngine == .avFoundation
                if pip.isActive || startsAutomatically || self.controller.isExternalPlaybackActive {
                    return
                }
                self.pause()
            }
        }
        lifecycleObservers.append(token)
    }
    #endif
}
