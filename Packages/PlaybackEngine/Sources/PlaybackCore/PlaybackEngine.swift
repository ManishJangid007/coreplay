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
    /// The titles changed, or another one started (a disc's menu included).
    case titlesChanged
    case videoDimensionsChanged(VideoDimensions?)
    /// The video turned out to be 360° (or flat after all).
    case projectionChanged(VideoProjection)
    case metadataChanged(MediaMetadata)
    /// The video started or stopped playing on an AirPlay device.
    case externalPlaybackChanged(Bool)
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

    // MARK: Titles and disc menus

    /// A disc's titles, its menus included, or a Matroska file's editions.
    /// Empty (or one title) for most files.
    var titles: [MediaTitle] { get }
    /// The playing title's `id`.
    var currentTitleIndex: Int? { get }
    /// Plays a title from its start. Requires `.discMenus`.
    func selectTitle(at index: Int)
    /// Moves around a disc's menu, as a DVD player's remote does. Requires `.discMenus`.
    func navigate(_ action: DiscNavigation)

    var videoDimensions: VideoDimensions? { get }
    /// Renders into `host`, or stops rendering when `nil`.
    func attachVideoOutput(to host: (any VideoOutputHost)?)

    // MARK: Picture (Level 2)

    var fillMode: VideoFillMode { get set }
    /// `nil` keeps the file's own shape. Requires `.aspectRatioOverride`.
    var aspectRatio: VideoRatio? { get set }
    /// `nil` shows the whole picture. Requires `.crop`.
    var cropRatio: VideoRatio? { get set }
    /// Requires `.videoAdjustments`.
    var videoAdjustments: VideoAdjustments { get set }
    /// Requires `.deinterlacing`.
    var deinterlace: DeinterlaceMode { get set }
    /// Which libVLC filter does the deinterlacing. Requires `.deinterlacing`.
    var deinterlaceFilter: DeinterlaceFilter { get set }

    // MARK: 360° video

    /// How the playing picture is laid out: 360° videos are spherical.
    var projection: VideoProjection { get }
    /// Which way a 360° video looks. Requires `.viewpoint360`.
    var viewpoint: Viewpoint { get set }

    // MARK: Sound (Level 2)

    /// Requires `.stereoModes`.
    var stereoMode: StereoMode { get set }
    /// Requires `.equalizer`.
    var equalizer: EqualizerSettings { get set }

    // MARK: Subtitles (Level 2)

    /// Text size relative to the engine's default. Requires `.subtitleStyling`.
    var subtitleScale: Float { get set }
    /// Font, colour, outline, background and height. AVFoundation applies it
    /// straight away; VLC reads it when an engine is created (see
    /// `EngineConfiguration.subtitleStyle`). Requires `.subtitleStyling`.
    var subtitleStyle: SubtitleStyle { get set }
    /// Shows a second subtitle track at the same time, or hides it (`nil`).
    /// Requires `.dualSubtitles`.
    func selectSecondarySubtitleTrack(id: MediaTrack.ID?)

    // MARK: Navigation (Level 2)

    /// Shows the next (or previous) frame, pausing first. Requires `.frameStepping`.
    func stepFrame(forward: Bool)
    /// Writes the frame on screen to `url` as a PNG. Requires `.snapshots`.
    func saveSnapshot(to url: URL) async throws

    // MARK: Media info

    /// What's inside the media, stream by stream.
    func mediaInfo() async -> MediaInfo
    /// Live figures (bitrate, dropped pictures); `nil` when the engine has none.
    var statistics: PlaybackStatistics? { get }

    /// Stops playback and releases every resource. The engine is unusable afterwards.
    func shutdown() async
}
