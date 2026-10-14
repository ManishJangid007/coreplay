import Foundation

/// Playback choices from Settings that more than one screen reads. Views
/// bind to the keys with `@AppStorage`; the defaults are on.
public enum PlaybackPreferences {
    /// Settings ▸ Playback ▸ Play Next Episode Automatically: at the end
    /// credits, the next episode starts after a short countdown.
    public static let autoplaysNextEpisodeKey = "player.autoplaysNextEpisode"
    /// Settings ▸ Playback ▸ Play Previews: the hero carousel plays a short,
    /// silent clip from the movie's own file behind its title.
    public static let playsPreviewsKey = "browse.playsPreviews"
    /// Settings ▸ Playback ▸ Volume Boost: volume controls go up to 200%,
    /// played with the VLC engine. Off by default.
    public static let allowsVolumeBoostKey = "player.allowsVolumeBoost"
    /// Settings ▸ Playback ▸ Remember Options for Each File: a video's
    /// tracks, timing, shape, crop and turn come back next time. On by default.
    public static let remembersFileOptionsKey = "player.remembersFileOptions"

    public static var autoplaysNextEpisode: Bool {
        UserDefaults.standard.object(forKey: autoplaysNextEpisodeKey) as? Bool ?? true
    }

    public static var playsPreviews: Bool {
        UserDefaults.standard.object(forKey: playsPreviewsKey) as? Bool ?? true
    }

    public static var remembersFileOptions: Bool {
        UserDefaults.standard.object(forKey: remembersFileOptionsKey) as? Bool ?? true
    }

    public static var allowsVolumeBoost: Bool {
        UserDefaults.standard.bool(forKey: allowsVolumeBoostKey)
    }

    /// The loudest the volume controls go: 100%, or 200% with Volume Boost.
    public static var maximumVolume: Float {
        allowsVolumeBoost ? 2 : 1
    }
}
