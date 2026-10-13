import AVFoundation
import Foundation
import PlaybackCore

/// Plays natively supported media with AVPlayer: better battery life, system
/// HDR handling and AirPlay video. Anything it can't do is handed to VLC by
/// the `PlaybackController`.
///
/// AVFoundation callbacks (KVO, notifications, time observers) are received in
/// `@Sendable` closures and hopped onto the main actor explicitly, so nothing
/// relies on which thread the framework happens to call back on.
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    let kind: EngineKind = .avFoundation
    let capabilities: EngineCapabilities = .avFoundation
    let events: AsyncStream<PlaybackEvent>

    private(set) var state: PlaybackState = .idle
    private(set) var duration: TimeInterval?
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var chapters: [Chapter] = []
    private(set) var videoDimensions: VideoDimensions?
    var audioDelay: TimeInterval = 0
    var subtitleDelay: TimeInterval = 0

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer?
    private var playerItem: AVPlayerItem?
    private var asset: AVURLAsset?
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var playerObservations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var itemNotificationTokens: [any NSObjectProtocol] = []
    private var timeObserver: Any?
    private var detailsTask: Task<Void, Never>?
    private var isReady = false
    private var wantsToPlay = false
    private var pendingStartPosition: TimeInterval?
    private var requestedRate: Float = 1

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
        self.events = stream
        self.continuation = continuation
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = true
        #if os(iOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        observePlayer()
    }

    // MARK: - Transport

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var isSeekable: Bool {
        guard let playerItem else { return false }
        return !playerItem.seekableTimeRanges.isEmpty
    }

    var rate: Float {
        get { requestedRate }
        set {
            requestedRate = newValue
            player.defaultRate = newValue
            if player.rate != 0 {
                player.rate = newValue
            }
        }
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = min(max(newValue, 0), 1) }
    }

    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    func load(_ item: PlaybackItem) async throws {
        tearDownItem()

        let asset = AVURLAsset(url: item.url)
        let playerItem = AVPlayerItem(asset: asset)
        // Keep voices natural at other speeds.
        playerItem.audioTimePitchAlgorithm = .spectral

        self.asset = asset
        self.playerItem = playerItem
        isReady = false
        wantsToPlay = false
        pendingStartPosition = (item.startPosition ?? 0) > 0 ? item.startPosition : nil
        duration = nil
        audioTracks = []
        subtitleTracks = []
        chapters = []
        videoDimensions = nil

        observe(playerItem)
        player.replaceCurrentItem(with: playerItem)
        setState(.opening)

        detailsTask = Task { [weak self] in
            await self?.loadDetails(of: asset)
        }
    }

    func play() {
        wantsToPlay = true
        guard isReady, pendingStartPosition == nil else { return } // starts once ready
        if state == .ended {
            player.seek(to: .zero)
        }
        player.defaultRate = requestedRate
        player.play()
    }

    func pause() {
        wantsToPlay = false
        player.pause()
    }

    func seek(to time: TimeInterval) async {
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        // No .timeChanged echo: the controller already shows the target.
        if state == .ended {
            setState(.paused)
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                done.resume()
            }
        }
    }

    // MARK: - Tracks

    func selectAudioTrack(id: MediaTrack.ID) {
        guard let group = audibleGroup, let playerItem,
              let option = Self.option(withID: id, in: group, kind: .audio) else { return }
        playerItem.select(option, in: group)
        refreshTracks()
    }

    func selectSubtitleTrack(id: MediaTrack.ID?) {
        guard let group = legibleGroup, let playerItem else { return }
        if let id, let option = Self.option(withID: id, in: group, kind: .subtitle) {
            playerItem.select(option, in: group)
        } else {
            playerItem.select(nil, in: group)
        }
        refreshTracks()
    }

    func addExternalSubtitle(url: URL) async throws {
        throw PlaybackError(.unsupportedFormat, "External subtitles need the VLC engine.")
    }

    // MARK: - Chapters

    func selectChapter(at index: Int) {
        guard let chapter = chapters.first(where: { $0.id == index }) else { return }
        Task { await seek(to: chapter.start) }
    }

    // MARK: - Video output

    func attachVideoOutput(to host: (any VideoOutputHost)?) {
        guard let view = host as? PlatformVideoView else {
            playerLayer?.removeFromSuperlayer()
            return
        }
        let layer = playerLayer ?? AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        playerLayer = layer
        view.managedLayer = layer
    }

    // MARK: - Shutdown

    func shutdown() async {
        detailsTask?.cancel()
        player.pause()
        tearDownItem()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        for observation in playerObservations {
            observation.invalidate()
        }
        playerObservations.removeAll()
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player.replaceCurrentItem(with: nil)
        continuation.finish()
    }

    // MARK: - Observation

    private func observePlayer() {
        playerObservations.append(
            player.observe(\.timeControlStatus, options: [.initial, .new]) { @Sendable [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor [weak self] in
                    self?.handleTimeControlStatus(status)
                }
            }
        )

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { @Sendable [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.continuation.yield(.timeChanged(max(0, seconds)))
            }
        }
    }

    /// Observes one player item. Every callback checks the item is still the
    /// current one: a hop queued just before `load()` replaced the item must
    /// not apply the old item's status to the new one.
    private func observe(_ item: AVPlayerItem) {
        let itemID = ObjectIdentifier(item)
        itemObservations = [
            item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
                let status = item.status
                let message = item.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(itemID) else { return }
                    self.handleItemStatus(status, errorMessage: message)
                }
            },
            item.observe(\.presentationSize, options: [.new]) { @Sendable [weak self] item, _ in
                let size = item.presentationSize
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(itemID) else { return }
                    self.handlePresentationSize(width: size.width, height: size.height)
                }
            },
        ]

        let center = NotificationCenter.default
        itemNotificationTokens = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { @Sendable [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isCurrent(itemID) else { return }
                    self.handlePlayedToEnd()
                }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { @Sendable [weak self] note in
                let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                MainActor.assumeIsolated {
                    guard let self, self.isCurrent(itemID) else { return }
                    self.fail(message)
                }
            },
            center.addObserver(forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: item, queue: .main) { @Sendable [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isCurrent(itemID) else { return }
                    self.refreshTracks()
                }
            },
        ]
    }

    private func isCurrent(_ itemID: ObjectIdentifier) -> Bool {
        playerItem.map { ObjectIdentifier($0) } == itemID
    }

    private func tearDownItem() {
        detailsTask?.cancel()
        detailsTask = nil
        for observation in itemObservations {
            observation.invalidate()
        }
        itemObservations.removeAll()
        for token in itemNotificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        itemNotificationTokens.removeAll()
        audibleGroup = nil
        legibleGroup = nil
        playerItem = nil
        asset = nil
    }

    // MARK: - Handlers

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard playerItem != nil, isReady else { return }
        switch status {
        case .playing:
            setState(.playing)
        case .waitingToPlayAtSpecifiedRate:
            setState(.buffering)
        case .paused:
            if state != .ended {
                setState(.paused)
            }
        @unknown default:
            break
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, errorMessage: String?) {
        switch status {
        case .readyToPlay:
            guard !isReady else { return }
            isReady = true
            if let start = pendingStartPosition {
                let itemID = playerItem.map { ObjectIdentifier($0) }
                Task { [weak self] in
                    await self?.seek(to: start)
                    guard let self, let itemID, self.isCurrent(itemID) else { return }
                    self.pendingStartPosition = nil
                    self.startIfWanted()
                }
            } else {
                startIfWanted()
            }
        case .failed:
            fail(errorMessage)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func startIfWanted() {
        if wantsToPlay {
            player.defaultRate = requestedRate
            player.play()
        } else {
            setState(.paused)
        }
    }

    private func handlePresentationSize(width: CGFloat, height: CGFloat) {
        let dimensions: VideoDimensions? = width > 0 && height > 0
            ? VideoDimensions(width: Int(width.rounded()), height: Int(height.rounded()))
            : nil
        guard dimensions != videoDimensions else { return }
        videoDimensions = dimensions
        continuation.yield(.videoDimensionsChanged(dimensions))
    }

    private func handlePlayedToEnd() {
        wantsToPlay = false
        continuation.yield(.endOfMedia)
        setState(.ended)
    }

    private func fail(_ message: String?) {
        let name = asset?.url.lastPathComponent ?? "this item"
        let detail = message.map { " (\($0))" } ?? ""
        setState(.failed(PlaybackError(.cannotOpen, "AVFoundation couldn\u{2019}t play \u{201C}\(name)\u{201D}\(detail).")))
    }

    private func setState(_ newState: PlaybackState) {
        guard newState != state else { return }
        state = newState
        continuation.yield(.stateChanged(newState))
    }

    // MARK: - Asset details

    private func loadDetails(of asset: AVURLAsset) async {
        let groups = await Self.loadSelectionGroups(asset)
        guard self.asset === asset, !Task.isCancelled else { return }
        audibleGroup = groups.audible
        legibleGroup = groups.legible
        refreshTracks()

        let details = await Self.loadAssetDetails(asset)
        guard self.asset === asset, !Task.isCancelled else { return }
        if details.duration != duration {
            duration = details.duration
            continuation.yield(.durationChanged(details.duration))
        }
        if details.chapters != chapters {
            chapters = details.chapters
            continuation.yield(.chaptersChanged)
        }
        if !details.metadata.isEmpty {
            continuation.yield(.metadataChanged(details.metadata))
        }
    }

    /// Media selection groups aren't Sendable; they're immutable once loaded,
    /// and only used on the main actor after this hand-over.
    private struct SelectionGroups: @unchecked Sendable {
        let audible: AVMediaSelectionGroup?
        let legible: AVMediaSelectionGroup?
    }

    private nonisolated static func loadSelectionGroups(_ asset: AVURLAsset) async -> SelectionGroups {
        let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
        let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
        return SelectionGroups(audible: audible ?? nil, legible: legible ?? nil)
    }

    private struct AssetDetails: Sendable {
        var duration: TimeInterval?
        var chapters: [Chapter] = []
        var metadata = MediaMetadata()
    }

    /// Loads duration, chapter markers and common metadata off the main actor.
    private nonisolated static func loadAssetDetails(_ asset: AVURLAsset) async -> AssetDetails {
        var details = AssetDetails()

        if let duration = try? await asset.load(.duration) {
            let seconds = duration.seconds
            details.duration = seconds.isFinite && seconds > 0 ? seconds : nil
        }

        if let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages) {
            for (index, group) in groups.enumerated() {
                var title: String?
                if let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first {
                    title = (try? await titleItem.load(.stringValue)) ?? nil
                }
                let start = group.timeRange.start.seconds
                let length = group.timeRange.duration.seconds
                details.chapters.append(Chapter(
                    index: index,
                    title: title,
                    start: start.isFinite ? start : 0,
                    duration: length.isFinite ? length : 0
                ))
            }
        }

        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let identifier = item.identifier else { continue }
                switch identifier {
                case .commonIdentifierTitle:
                    details.metadata.title = (try? await item.load(.stringValue)) ?? nil
                case .commonIdentifierArtist:
                    details.metadata.artist = (try? await item.load(.stringValue)) ?? nil
                case .commonIdentifierAlbumName:
                    details.metadata.albumTitle = (try? await item.load(.stringValue)) ?? nil
                case .commonIdentifierArtwork:
                    details.metadata.artworkData = (try? await item.load(.dataValue)) ?? nil
                default:
                    continue
                }
            }
        }
        return details
    }

    private func refreshTracks() {
        guard let playerItem else { return }
        let selection = playerItem.currentMediaSelection
        var audio: [MediaTrack] = []
        if let group = audibleGroup {
            let selected = selection.selectedMediaOption(in: group)
            audio = Self.tracks(in: group, kind: .audio, selected: selected)
        }
        var subtitles: [MediaTrack] = []
        if let group = legibleGroup {
            let selected = selection.selectedMediaOption(in: group)
            subtitles = Self.tracks(in: group, kind: .subtitle, selected: selected)
        }
        guard audio != audioTracks || subtitles != subtitleTracks else { return }
        audioTracks = audio
        subtitleTracks = subtitles
        continuation.yield(.tracksChanged)
    }

    private static func tracks(in group: AVMediaSelectionGroup, kind: MediaTrack.Kind, selected: AVMediaSelectionOption?) -> [MediaTrack] {
        group.options.enumerated().map { index, option in
            MediaTrack(
                id: "\(kind.rawValue)-\(index)",
                kind: kind,
                name: option.displayName,
                languageCode: option.extendedLanguageTag ?? option.locale?.identifier,
                isSelected: option == selected,
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
                isSDH: option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility)
                    || option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility)
            )
        }
    }

    private static func option(withID id: MediaTrack.ID, in group: AVMediaSelectionGroup, kind: MediaTrack.Kind) -> AVMediaSelectionOption? {
        let prefix = "\(kind.rawValue)-"
        guard id.hasPrefix(prefix), let index = Int(id.dropFirst(prefix.count)),
              group.options.indices.contains(index) else { return nil }
        return group.options[index]
    }
}
