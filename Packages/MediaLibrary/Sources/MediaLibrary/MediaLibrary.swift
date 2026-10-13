import Foundation

/// Scanning, indexing, classification, artwork and the SwiftData model.
///
/// Status: placeholder. Built in Milestone 3 (sources, scanning, music tags,
/// artwork) and Milestone 4 (filename parsing, movies and TV, progress rules).
///
/// Planned contents, from the build prompt:
/// - `MediaFile` (bookmark, path, size, hash, duration, container, track info,
///   engine preference) with `Track`, `Album`, `Artist`, `Genre`, `Movie`,
///   `TVShow`, `Season`, `Episode`, `HomeVideo`, `Playlist` (manual and smart),
///   `PlaybackState` and `Source` on top.
/// - An incremental scanner actor keyed on path, size and modification date,
///   FSEvents on macOS, background refresh on iOS; missing files are marked
///   unavailable, never deleted.
/// - Evaluate VLCMediaLibraryKit first; fall back to a SwiftData indexer.
public enum MediaLibrary {
    /// The milestone that turns this package from a placeholder into the library.
    public static let plannedMilestone = 3
}
