import Foundation
import Observation
import PlaybackCore

/// User settings, persisted in `UserDefaults`.
///
/// The build prompt puts settings in SwiftData with CloudKit sync; that move
/// happens with the library and sync milestones. Keys are stable so values
/// can be migrated then.
@MainActor
@Observable
public final class AppSettings {
    public enum Key {
        public static let alwaysUseVLC = "playback.alwaysUseVLC"
        public static let hardwareDecoding = "video.hardwareDecoding"
        public static let networkCaching = "network.cachingMilliseconds"
        public static let customLibVLCOptions = "advanced.customLibVLCOptions"
    }

    public var alwaysUseVLC: Bool {
        didSet { store(alwaysUseVLC, for: Key.alwaysUseVLC) }
    }

    public var hardwareDecoding: Bool {
        didSet { store(hardwareDecoding, for: Key.hardwareDecoding) }
    }

    public var networkCachingMilliseconds: Int {
        didSet { store(networkCachingMilliseconds, for: Key.networkCaching) }
    }

    public var customLibVLCOptions: String {
        didSet { store(customLibVLCOptions, for: Key.customLibVLCOptions) }
    }

    /// Called whenever a setting that affects playback changes.
    @ObservationIgnored public var onEngineConfigurationChange: (@MainActor (EngineConfiguration) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = EngineConfiguration()
        alwaysUseVLC = defaults.object(forKey: Key.alwaysUseVLC) as? Bool ?? fallback.alwaysUseVLC
        hardwareDecoding = defaults.object(forKey: Key.hardwareDecoding) as? Bool ?? fallback.hardwareDecoding
        networkCachingMilliseconds = defaults.object(forKey: Key.networkCaching) as? Int ?? fallback.networkCachingMilliseconds
        customLibVLCOptions = defaults.string(forKey: Key.customLibVLCOptions) ?? fallback.customLibVLCOptions
    }

    public var engineConfiguration: EngineConfiguration {
        EngineConfiguration(
            alwaysUseVLC: alwaysUseVLC,
            hardwareDecoding: hardwareDecoding,
            networkCachingMilliseconds: networkCachingMilliseconds,
            customLibVLCOptions: customLibVLCOptions
        )
    }

    private func store(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
        onEngineConfigurationChange?(engineConfiguration)
    }
}
