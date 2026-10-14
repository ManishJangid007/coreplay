import Foundation
import SwiftData

/// Version 1 of the library schema (Milestone 3): sources, files and music.
/// Its models are frozen copies (see SchemaV1.swift), so stores it created
/// can always be recognised and upgraded.
public enum LibrarySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Source.self, MediaFile.self, Track.self, Album.self, Artist.self, Genre.self, PlaybackRecord.self]
    }
}

/// Version 2 (Milestone 4): movies, TV shows and home videos (`Video`,
/// `TVShow`, `Season`), video details on `MediaFile`, what each source holds,
/// and watched state in `PlaybackRecord`. The current, top-level models.
public enum LibrarySchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            MediaLibrary.Source.self, MediaLibrary.MediaFile.self, MediaLibrary.Track.self, MediaLibrary.Album.self,
            MediaLibrary.Artist.self, MediaLibrary.Genre.self, MediaLibrary.PlaybackRecord.self,
            Video.self, TVShow.self, Season.self,
        ]
    }
}

/// Version 3 (Milestone 8): playlists. Version 2's models are unchanged,
/// so it only adds the `Playlist` entity.
public enum LibrarySchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        LibrarySchemaV2.models + [Playlist.self]
    }
}

/// Upgrades existing libraries in place: versions 2 and 3 only add entities
/// and attributes with defaults, so lightweight migrations keep every
/// source, edit and play count.
public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self] }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
            .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self),
        ]
    }
}

public enum LibraryStore {
    public typealias CurrentSchema = LibrarySchemaV3

    /// The on-disk library (Application Support/Library.store), or an
    /// in-memory one for tests and previews.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration("Library", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
    }

    /// A library stored at `url` (tests open copies of old stores this way).
    public static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration("Library", schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
    }
}
