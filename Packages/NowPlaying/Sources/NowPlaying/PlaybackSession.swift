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

    // MARK: - Remembered preferences

    /// Turns the equalizer on or off or changes it; remembered between launches.
    public func setEqualizer(_ settings: EqualizerSettings) async {
        await controller.setEqualizer(settings)
        Self.save(settings, forKey: Self.equalizerKey)
    }

    /// Subtitle text size; remembered between launches.
    public func setSubtitleSize(_ size: SubtitleSize) async {
        await controller.setSubtitleSize(size)
        UserDefaults.standard.set(size.rawValue, forKey: Self.subtitleSizeKey)
    }

    private static let equalizerKey = "player.equalizer"
    private static let subtitleSizeKey = "player.subtitleSize"

    private func restorePreferences() {
        let equalizer: EqualizerSettings? = Self.load(forKey: Self.equalizerKey)
        let subtitleSize = UserDefaults.standard.string(forKey: Self.subtitleSizeKey).flatMap(SubtitleSize.init(rawValue:))
        guard equalizer != nil || subtitleSize != nil else { return }
        Task {
            if let equalizer {
                await controller.setEqualizer(equalizer)
            }
            if let subtitleSize {
                await controller.setSubtitleSize(subtitleSize)
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
        case .item, .metadata, .duration:
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
        if let item = queue.advance(automatic: true) {
            await load(item)
        } else {
            wantsPlayback = false // the queue finished: nothing to resume after an interruption
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
