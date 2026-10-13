import Foundation

/// Metadata and artwork lookups: embedded tags, folder artwork, `.nfo` files,
/// TMDB (movies and TV, user-supplied API key), MusicBrainz + Cover Art
/// Archive, and LRCLIB lyrics. Every network lookup is opt-in.
///
/// Status: placeholder. Embedded tags and folder artwork arrive in
/// Milestone 3, TMDB in Milestone 4, lyrics in Milestone 8.
public enum MetadataProviders {
    public static let plannedMilestone = 3
}
