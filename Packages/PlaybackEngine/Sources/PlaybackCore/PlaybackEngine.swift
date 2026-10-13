import Foundation

/// Events an engine emits while playing.
public enum PlaybackEvent: Hashable, Sendable {
    case stateChanged(PlaybackState)
    case timeChanged(TimeInterval)
    case durationChanged(TimeInterval?)
    /// Buffer fill in `0...1`.
    case bufferingChanged(Double)
    case rateChanged(Float)
    /// Audio, video or subtitle tracks were added, removed or (de)selected.
    case tracksChanged
    case chaptersChanged
    case videoDimensionsChanged(VideoDimensions?)
    case metadataChanged(MediaMetadata)
    /// The item played to its end. Always followed by `.stateChanged(.ended)`.
    case endOfMedia
}

/// A platform view an engine can render video into.
///
/// The PlaybackEngine module provides `PlatformVideoView` (a `UIView` /
/// `NSView`). Engines never create windows of their own.
@MainActor
public protocol VideoOutputHost: AnyObject {}

/// One playback engine. All calls happen on the main actor: VLCKit and AVKit
/// both expect their players and video views to be driven from one thread, and
/// both already dispatch heavy work to their own queues. Expensive work that we
/// own (probing, thumbnails, scanning) runs in separate actors.
///
/// Engines are reusable: `load(_:)` replaces whatever was loaded before.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var kind: EngineKind { get }
    var capabilities: EngineCapabilities { get }

    /// Single-consumer stream of events. The `PlaybackController` is the only consumer.
    var events: AsyncStream<PlaybackEvent> { get }

    var state: PlaybackState { get }
    /// Current position in seconds.
    var currentTime: TimeInterval { get }
    /// Length in seconds, `nil` while unknown or for live streams.
    var duration: TimeInterval? { get }
    var isSeekable: Bool { get }
    /// 1 is normal speed.
    var rate: Float { get set }
    /// 0…1. The VLC engine accepts up to 2 (volume boost).
    var volume: Float { get set }
    var isMuted: Bool { get set }

    /// Opens an item. Playback starts when `play()` is called.
    func load(_ item: PlaybackItem) async throws
    func play()
    func pause()
    /// Precise seek, in seconds.
    func seek(to time: TimeInterval) async

    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(id: MediaTrack.ID)
    /// `nil` turns subtitles off.
    func selectSubtitleTrack(id: MediaTrack.ID?)
    /// Adds and selects a subtitle file. Requires `.externalSubtitles`.
    func addExternalSubtitle(url: URL) async throws

    /// Seconds; positive delays audio. Requires `.audioDelay`.
    var audioDelay: TimeInterval { get set }
    /// Seconds; positive shows subtitles later. Requires `.subtitleDelay`.
    var subtitleDelay: TimeInterval { get set }

    var chapters: [Chapter] { get }
    func selectChapter(at index: Int)

    var videoDimensions: VideoDimensions? { get }
    /// Renders into `host`, or stops rendering when `nil`.
    func attachVideoOutput(to host: (any VideoOutputHost)?)

    /// Stops playback and releases every resource. The engine is unusable afterwards.
    func shutdown() async
}
