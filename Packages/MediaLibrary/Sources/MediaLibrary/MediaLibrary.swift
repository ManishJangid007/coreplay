import Foundation
import SwiftData

/// Version 1 of the library schema (Milestone 3). Later versions add their
/// models here with a migration stage, so existing libraries are upgraded
/// rather than rebuilt.
public enum LibrarySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Source.self, MediaFile.self, Track.self, Album.self, Artist.self, Genre.self, PlaybackRecord.self]
    }
}

public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum LibraryStore {
    /// The on-disk library (Application Support/Library.store), or an
    /// in-memory one for tests and previews.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = ModelConfiguration("Library", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
    }
}
