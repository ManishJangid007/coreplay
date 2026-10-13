// MetadataProviders: where Coreplay's metadata comes from.
//
// - Embedded tags and artwork (`TagReader`): ID3v1/v2, FLAC and Ogg Vorbis
//   comments, MP4 atoms and APEv2, plus duration and format from the streams.
// - File and folder names for untagged files (`PathMetadata`).
// - Name keys for grouping and sorting (`NameNormalizer`).
//
// Still to come: TMDB for movies and TV (Milestone 4, with the user's own API
// key), MusicBrainz + Cover Art Archive and LRCLIB lyrics (opt-in lookups).
//
// Everything here is Foundation-only and runs off the main actor.
