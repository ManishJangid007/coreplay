import Foundation

// Loudness: ReplayGain levelling between tracks, VLC's volume normaliser,
// and volume boost. Plain values and rules, applied by the controller to
// whichever engine plays.

/// Levelling loudness between tracks with their ReplayGain values (what the
/// Music app calls Sound Check).
public enum ReplayGainMode: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case off
    /// Every track at the same loudness.
    case track
    /// Whole albums at the same loudness, so quiet songs stay quieter than loud ones.
    case album

    public var id: Self { self }

    public var title: String {
        switch self {
        case .off: "Off"
        case .track: "Track"
        case .album: "Album"
        }
    }
}

/// A track's ReplayGain values, read from its tags.
public struct ReplayGainValues: Hashable, Sendable {
    /// Decibels to turn the track up (or down, when negative).
    public var trackGain: Double?
    /// The loudest sample, 1 being full scale.
    public var trackPeak: Double?
    public var albumGain: Double?
    public var albumPeak: Double?

    public init(trackGain: Double? = nil, trackPeak: Double? = nil, albumGain: Double? = nil, albumPeak: Double? = nil) {
        self.trackGain = trackGain
        self.trackPeak = trackPeak
        self.albumGain = albumGain
        self.albumPeak = albumPeak
    }

    public var hasGain: Bool {
        trackGain != nil || albumGain != nil
    }
}

/// How ReplayGain is applied.
public struct ReplayGainSettings: Hashable, Sendable, Codable {
    public static let preampRange: ClosedRange<Double> = -15...15

    public var mode: ReplayGainMode
    /// Added to every track's gain, in decibels.
    public var preamp: Double
    /// For tracks that were never scanned, in decibels. 0 leaves them alone.
    public var fallbackGain: Double
    /// Never turns a track up so far that its loudest moment clips.
    public var preventsClipping: Bool

    public init(mode: ReplayGainMode = .off, preamp: Double = 0, fallbackGain: Double = 0, preventsClipping: Bool = true) {
        self.mode = mode
        self.preamp = min(max(preamp, Self.preampRange.lowerBound), Self.preampRange.upperBound)
        self.fallbackGain = min(max(fallbackGain, Self.preampRange.lowerBound), Self.preampRange.upperBound)
        self.preventsClipping = preventsClipping
    }

    public static let off = ReplayGainSettings()

    /// The decibels a track is changed by: its own (or its album's) gain
    /// plus the preamp; the fallback for tracks without values.
    public func gain(for values: ReplayGainValues?) -> Double {
        guard mode != .off else { return 0 }
        guard let values, values.hasGain else { return fallbackGain }
        let own = switch mode {
        case .off, .track: values.trackGain ?? values.albumGain
        case .album: values.albumGain ?? values.trackGain
        }
        return (own ?? 0) + preamp
    }

    /// What to multiply the volume by: 1 leaves the track as it is.
    public func scale(for values: ReplayGainValues?) -> Double {
        guard mode != .off else { return 1 }
        var factor = pow(10, gain(for: values) / 20)
        if preventsClipping, let values {
            let peak = switch mode {
            case .off, .track: values.trackPeak ?? values.albumPeak
            case .album: values.albumPeak ?? values.trackPeak
            }
            if let peak, peak > 0 {
                factor = min(factor, 1 / peak)
            }
        }
        return factor.isFinite ? factor : 1
    }
}

/// Volume levels the engines take: AVFoundation stops at full volume, VLC
/// goes up to twice that (volume boost).
public enum VolumeLimits {
    public static let normal: Float = 1
    public static let boosted: Float = 2

    /// What the engine is given: the volume you chose, levelled by
    /// ReplayGain, never above what the engine can do.
    public static func engineVolume(chosen: Float, replayGainScale: Double, limit: Float) -> Float {
        let scaled = Double(chosen) * (replayGainScale.isFinite ? replayGainScale : 1)
        return Float(min(max(scaled, 0), Double(limit)))
    }

    /// "100%", "150%".
    public static func percent(_ volume: Float) -> String {
        "\(Int((volume * 100).rounded()))%"
    }
}
