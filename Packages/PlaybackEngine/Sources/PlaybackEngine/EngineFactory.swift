import Foundation
import PlaybackCore

/// Creates engines with the current configuration. The libVLC instance is
/// shared between VLC engines and rebuilt only when global options change.
@MainActor
final class EngineFactory {
    var configuration: EngineConfiguration
    private let vlcLibraries = VLCLibraryProvider()

    init(configuration: EngineConfiguration) {
        self.configuration = configuration
    }

    func makeEngine(_ kind: EngineKind) -> any PlaybackEngine {
        switch kind {
        case .vlc:
            VLCKitEngine(
                library: vlcLibraries.library(options: configuration.libVLCLibraryOptions),
                mediaOptions: configuration.libVLCMediaOptions
            )
        case .avFoundation:
            AVPlayerEngine()
        }
    }

    /// The options a VLC engine created right now would use. The controller
    /// compares these to decide whether an existing VLC engine is stale.
    var vlcOptionsFingerprint: [String] {
        configuration.libVLCLibraryOptions + configuration.libVLCMediaOptions
    }

    var vlcVersionDescription: String {
        vlcLibraries.versionDescription(options: configuration.libVLCLibraryOptions)
    }
}

/// Versions shown in Settings → About.
public enum EngineVersions {
    /// The VLCKit release pinned in Package.swift.
    public static let vlcKit = "4.0.0a25"
}
