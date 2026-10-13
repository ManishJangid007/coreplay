import Foundation

/// The two playback engines Coreplay ships with.
public enum EngineKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// libVLC through VLCKit: plays everything VLC plays.
    case vlc
    /// AVPlayer: best battery life, HDR handling and AirPlay video for native formats.
    case avFoundation

    /// Name shown in the Media Info panel and the Advanced settings.
    public var displayName: String {
        switch self {
        case .vlc: "VLC"
        case .avFoundation: "AVFoundation"
        }
    }
}

/// Features an engine can provide. When the user asks for one the current
/// engine lacks, the `PlaybackController` hands playback over to VLC at the
/// same position.
public struct EngineCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let audioDelay          = EngineCapabilities(rawValue: 1 << 0)
    public static let subtitleDelay       = EngineCapabilities(rawValue: 1 << 1)
    public static let externalSubtitles   = EngineCapabilities(rawValue: 1 << 2)
    public static let subtitleStyling     = EngineCapabilities(rawValue: 1 << 3)
    public static let dualSubtitles       = EngineCapabilities(rawValue: 1 << 4)
    public static let equalizer           = EngineCapabilities(rawValue: 1 << 5)
    public static let videoAdjustments    = EngineCapabilities(rawValue: 1 << 6)
    public static let deinterlacing       = EngineCapabilities(rawValue: 1 << 7)
    public static let aspectRatioOverride = EngineCapabilities(rawValue: 1 << 8)
    public static let crop                = EngineCapabilities(rawValue: 1 << 9)
    /// Playback rates above 2×.
    public static let highRates           = EngineCapabilities(rawValue: 1 << 10)
    public static let frameStepping       = EngineCapabilities(rawValue: 1 << 11)
    public static let chapters            = EngineCapabilities(rawValue: 1 << 12)
    public static let discMenus           = EngineCapabilities(rawValue: 1 << 13)
    public static let snapshots           = EngineCapabilities(rawValue: 1 << 14)
    public static let viewpoint360        = EngineCapabilities(rawValue: 1 << 15)
    public static let stereoModes         = EngineCapabilities(rawValue: 1 << 16)
    public static let volumeBoost         = EngineCapabilities(rawValue: 1 << 17)
    /// AirPlay video handled by the system (AVPlayer's external playback).
    public static let nativeAirPlayVideo  = EngineCapabilities(rawValue: 1 << 18)
    public static let pictureInPicture    = EngineCapabilities(rawValue: 1 << 19)

    /// What `VLCKitEngine` offers (some are wired up in later milestones).
    public static let vlc: EngineCapabilities = [
        .audioDelay, .subtitleDelay, .externalSubtitles, .subtitleStyling, .dualSubtitles,
        .equalizer, .videoAdjustments, .deinterlacing, .aspectRatioOverride, .crop,
        .highRates, .frameStepping, .chapters, .discMenus, .snapshots, .viewpoint360,
        .stereoModes, .volumeBoost, .pictureInPicture,
    ]

    /// What `AVPlayerEngine` offers.
    public static let avFoundation: EngineCapabilities = [
        .frameStepping, .chapters, .nativeAirPlayVideo, .pictureInPicture,
    ]
}
