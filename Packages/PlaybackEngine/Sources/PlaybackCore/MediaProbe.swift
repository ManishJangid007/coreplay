import Foundation

/// What a quick, Apple-framework probe found inside a media file.
///
/// Produced by `MediaProber` (AVFoundation) in the PlaybackEngine module and
/// consumed by the pure `EngineRouter`, which keeps routing decisions testable.
public struct MediaProbe: Hashable, Sendable {
    public struct Track: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case video
            case audio
            /// Subtitles, captions and other text the user can switch on.
            case text
            /// Tracks the player ignores: timecode, chapters, metadata.
            case auxiliary
        }

        public var kind: Kind
        public var codec: FourCC
        /// AVFoundation's own verdict on whether it can play this track here.
        public var isPlayable: Bool

        public init(kind: Kind, codec: FourCC, isPlayable: Bool) {
            self.kind = kind
            self.codec = codec
            self.isPlayable = isPlayable
        }
    }

    /// AVFoundation can open the container at all.
    public var isPlayable: Bool
    public var hasProtectedContent: Bool
    public var tracks: [Track]
    /// A 360° video (see `SphericalVideoDetector`).
    public var projection: VideoProjection

    public init(isPlayable: Bool, hasProtectedContent: Bool = false, tracks: [Track], projection: VideoProjection = .flat) {
        self.isPlayable = isPlayable
        self.hasProtectedContent = hasProtectedContent
        self.tracks = tracks
        self.projection = projection
    }
}
