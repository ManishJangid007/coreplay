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

    public static var autoplaysNextEpisode: Bool {
        UserDefaults.standard.object(forKey: autoplaysNextEpisodeKey) as? Bool ?? true
    }

    public static var playsPreviews: Bool {
        UserDefaults.standard.object(forKey: playsPreviewsKey) as? Bool ?? true
    }
}
