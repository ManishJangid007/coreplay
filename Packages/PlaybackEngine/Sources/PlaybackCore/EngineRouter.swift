import Foundation

/// Picks the engine for an item.
///
/// AVFoundation is used only when the container, every audio and video codec
/// and every subtitle format are natively supported. Everything else, and
/// every non-HTTP network protocol, goes to VLC. Routing is pure logic so it
/// can be unit tested without media files; probing lives in `MediaProber`.
public struct EngineRouter: Sendable {
    public struct Decision: Hashable, Sendable {
        public var engine: EngineKind
        public var reason: Reason

        public init(engine: EngineKind, reason: Reason) {
            self.engine = engine
            self.reason = reason
        }
    }

    public enum Reason: Hashable, Sendable {
        case itemOverride
        case alwaysUseVLCSetting
        case networkProtocol(String)
        case remoteStream
        case unsupportedContainer(String)
        case externalSubtitles
        case unsupportedVideoCodec(FourCC)
        case unsupportedAudioCodec(FourCC)
        case unsupportedSubtitleFormat(FourCC)
        case trackNotPlayable(FourCC)
        case protectedContent
        case probeFailed
        case nativelySupported
        /// The user switched engines from the player (or a feature needed VLC).
        case handoff

        /// Plain-language explanation for the Media Info panel.
        public var explanation: String {
            switch self {
            case .itemOverride: "Engine chosen for this item"
            case .alwaysUseVLCSetting: "\u{201C}Always Use VLC Engine\u{201D} is on"
            case .networkProtocol(let scheme): "\(scheme.uppercased()) streams play with VLC"
            case .remoteStream: "Streaming format supported by Apple"
            case .unsupportedContainer(let ext): ".\(ext) files play with VLC"
            case .externalSubtitles: "External subtitle files need VLC"
            case .unsupportedVideoCodec(let codec): "Video codec \(codec) needs VLC"
            case .unsupportedAudioCodec(let codec): "Audio codec \(codec) needs VLC"
            case .unsupportedSubtitleFormat(let codec): "Subtitle format \(codec) needs VLC"
            case .trackNotPlayable(let codec): "This device can't decode \(codec) natively"
            case .protectedContent: "Protected content plays with AVFoundation"
            case .probeFailed: "Apple's frameworks couldn't open this file"
            case .nativelySupported: "Every track is natively supported"
            case .handoff: "Switched engines during playback"
            }
        }
    }

    public var alwaysUseVLC: Bool

    public init(alwaysUseVLC: Bool = false) {
        self.alwaysUseVLC = alwaysUseVLC
    }

    /// Decides without opening the file when possible. Returns `nil` when the
    /// item needs to be probed first.
    public func quickDecision(for item: PlaybackItem) -> Decision? {
        switch item.enginePreference {
        case .vlc: return Decision(engine: .vlc, reason: .itemOverride)
        case .avFoundation: return Decision(engine: .avFoundation, reason: .itemOverride)
        case .automatic: break
        }
        if alwaysUseVLC {
            return Decision(engine: .vlc, reason: .alwaysUseVLCSetting)
        }

        let scheme = (item.url.scheme ?? "file").lowercased()
        let container = ContainerFormat(url: item.url)
        switch scheme {
        case "file":
            break
        case "http", "https":
            // AVPlayer handles HTTP(S) progressive downloads and HLS well, and
            // AirPlays them natively. Remote files aren't probed (too slow).
            if container.support == .native {
                return Decision(engine: .avFoundation, reason: .remoteStream)
            }
            return Decision(engine: .vlc, reason: .networkProtocol(scheme))
        default:
            // RTSP, RTMP, UDP, MMS, SMB, FTP, SFTP, NFS, UPnP, discs…
            return Decision(engine: .vlc, reason: .networkProtocol(scheme))
        }

        if container.support == .vlcOnly {
            return Decision(engine: .vlc, reason: .unsupportedContainer(container.fileExtension))
        }
        if !item.externalSubtitleURLs.isEmpty {
            return Decision(engine: .vlc, reason: .externalSubtitles)
        }
        return nil
    }

    /// Full decision for a local file, using what the probe found.
    public func decision(for item: PlaybackItem, probe: MediaProbe?) -> Decision {
        if let quick = quickDecision(for: item) {
            return quick
        }
        guard let probe, probe.isPlayable else {
            return Decision(engine: .vlc, reason: .probeFailed)
        }
        if probe.hasProtectedContent {
            // Only AVFoundation can play FairPlay-protected files (e.g. old iTunes purchases).
            return Decision(engine: .avFoundation, reason: .protectedContent)
        }

        var sawAudioOrVideo = false
        for track in probe.tracks {
            switch track.kind {
            case .video:
                sawAudioOrVideo = true
                guard NativeCodecSupport.video.contains(track.codec) else {
                    return Decision(engine: .vlc, reason: .unsupportedVideoCodec(track.codec))
                }
                guard track.isPlayable else {
                    return Decision(engine: .vlc, reason: .trackNotPlayable(track.codec))
                }
            case .audio:
                sawAudioOrVideo = true
                guard NativeCodecSupport.audio.contains(track.codec) else {
                    return Decision(engine: .vlc, reason: .unsupportedAudioCodec(track.codec))
                }
                guard track.isPlayable else {
                    return Decision(engine: .vlc, reason: .trackNotPlayable(track.codec))
                }
            case .text:
                guard NativeCodecSupport.text.contains(track.codec) else {
                    return Decision(engine: .vlc, reason: .unsupportedSubtitleFormat(track.codec))
                }
            case .auxiliary:
                continue
            }
        }
        guard sawAudioOrVideo else {
            return Decision(engine: .vlc, reason: .probeFailed)
        }
        return Decision(engine: .avFoundation, reason: .nativelySupported)
    }
}
