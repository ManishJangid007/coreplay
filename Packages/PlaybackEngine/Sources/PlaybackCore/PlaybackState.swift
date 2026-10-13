import Foundation

/// The state of an engine, as the UI sees it.
public enum PlaybackState: Hashable, Sendable {
    /// Nothing loaded, or playback was stopped.
    case idle
    /// The media is being opened.
    case opening
    /// Playing is requested but the engine is waiting for data.
    case buffering
    case playing
    case paused
    /// The item played to its end.
    case ended
    case failed(PlaybackError)

    /// `true` while the user expects sound and moving pictures.
    public var isActive: Bool {
        switch self {
        case .playing, .buffering, .opening: true
        default: false
        }
    }

    public var error: PlaybackError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// An error surfaced to the user in plain language.
public struct PlaybackError: Error, Hashable, Sendable, LocalizedError {
    public enum Code: String, Hashable, Sendable {
        case cannotOpen
        case unsupportedFormat
        case accessDenied
        case networkFailure
        case engineFailure
    }

    public var code: Code
    public var message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    public static func cannotOpen(_ url: URL) -> PlaybackError {
        PlaybackError(.cannotOpen, "Couldn\u{2019}t open \u{201C}\(url.lastPathComponent)\u{201D}.")
    }
}

/// Pixel dimensions of the video being displayed.
public struct VideoDimensions: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 16.0 / 9.0
    }

    /// Short resolution badge, e.g. "4K", "1080p", "720p", "SD".
    public var resolutionBadge: String {
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        switch (longEdge, shortEdge) {
        case (7_000..., _): return "8K"
        case (3_400..., _), (_, 2_000...): return "4K"
        case (2_400..., _), (_, 1_400...): return "1440p"
        case (1_800..., _), (_, 1_000...): return "1080p"
        case (1_200..., _), (_, 700...): return "720p"
        default: return "SD"
        }
    }
}
