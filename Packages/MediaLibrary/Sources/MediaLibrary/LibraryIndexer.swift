import Foundation
import MetadataProviders
import PlaybackCore
import SwiftData

public struct ScanProgress: Sendable, Equatable {
    public var sourceID: UUID
    /// Files read so far (unchanged files are skipped and don't count).
    public var processed: Int
    /// Files that need reading in this scan.
    public var total: Int
}

public struct ScanSummary: Sendable, Equatable {
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    /// Files that disappeared and are now marked unavailable.
    public var missing = 0

    public init() {}
}

/// A media file found on disk.
struct FoundFile: Sendable {
    var url: URL
    /// Below the source root; "" for single-file sources.
    var relativePath: String
    var size: Int64
    var modificationDate: Date
    var kind: PlaybackItem.Kind
    /// A DVD or Blu-ray: `url` is the folder holding VIDEO_TS or BDMV (or,
    /// when the source is that folder, VIDEO_TS or BDMV itself), or the image.
    var disc: DiscKind?
    var isDiscFolder: Bool { disc != nil && !DiscLayout.imageExtensions.contains(url.pathExtension.lowercased()) }
}

/// What reading a file produced, ready to merge into the model.
struct ParsedFile: Sendable {
    var found: FoundFile
    var contentKey: String
    var tags: AudioTags?
    var artworkKey: String?
    var path: PathMetadata
    var video: ParsedVideo?
}

/// Fields Edit Info can change. Rescans leave edited fields alone.
public enum TrackField: String, Sendable, CaseIterable {
    case title, artist, album, albumArtist, genre, year, trackNumber, discNumber, composer, compilation
}

/// Scans sources into the library on a background model context.
///
/// Scans are incremental: a file whose size and modification date haven't
/// changed is never read again. Files that vanish are marked unavailable
/// rather than deleted, so their history survives an unplugged drive.
@ModelActor
public actor LibraryIndexer {
    static let skippedExtensions: Set<String> = ["m3u8", "m3u", "pls", "xspf", "cue"]
    private static let batchSize = 16
    private static let saveInterval = 128

    public func scan(
        sourceID: UUID,
        root: URL,
        isSingleFile: Bool,
        artworkStore: ArtworkStore,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanSummary {
        guard let source = try source(id: sourceID) else { return ScanSummary() }
        let found = isSingleFile ? Self.singleFile(root) : Self.enumerate(root)
        let hint = source.videoHint

        var summary = ScanSummary()
        var existing: [String: MediaFile] = [:]
        for file in source.files {
            existing[file.relativePath] = file
        }

        var pending: [FoundFile] = []
        for file in found {
            if let current = existing[file.relativePath],
               current.fileSize == file.size,
               abs(current.modificationDate.timeIntervalSince(file.modificationDate)) < 0.001,
               current.kind == file.kind,
               // Videos from before the video library (or an older reader) are read again.
               current.kind != .video || (current.video != nil && current.videoProbeVersion >= Self.videoProbeVersion) {
                if !current.isAvailable {
                    current.isAvailable = true
                }
                summary.unchanged += 1
            } else {
                pending.append(file)
            }
        }
        let foundPaths = Set(found.map(\.relativePath))
        // A source that is a disc's VIDEO_TS or BDMV: everything listed before is part of the disc.
        let sourceIsInsideDisc = !isSingleFile && DiscLayout.structureFolders.contains(root.lastPathComponent.uppercased())
        var removedDiscParts = false
        for (path, file) in existing where !foundPaths.contains(path) {
            if DiscLayout.canPlayDiscs, sourceIsInsideDisc || Self.isInsideDisc(path) {
                // A VOB or M2TS listed before Coreplay knew discs: the disc
                // around it is one video now.
                modelContext.delete(file)
                existing[path] = nil
                removedDiscParts = true
            } else if file.isAvailable {
                file.isAvailable = false
                summary.missing += 1
            }
        }
        try modelContext.save()

        let grouper = LibraryGrouper(context: modelContext)
        let videoGrouper = VideoGrouper(context: modelContext)
        let folderArtwork = FolderArtworkCache()
        let videoFolders = VideoFolderCache()
        var touchedVideos = removedDiscParts
        progress(ScanProgress(sourceID: sourceID, processed: 0, total: pending.count))

        var index = 0
        var sinceSave = 0
        while index < pending.count {
            try Task.checkCancellation()
            let batch = Array(pending[index..<min(index + Self.batchSize, pending.count)])
            index += batch.count
            let parsed = await withTaskGroup(of: ParsedFile.self) { group in
                for file in batch {
                    group.addTask {
                        Self.parse(file, hint: hint, artworkStore: artworkStore, folderArtwork: folderArtwork, videoFolders: videoFolders)
                    }
                }
                var results: [ParsedFile] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            for item in parsed.sorted(by: { $0.found.relativePath < $1.found.relativePath }) {
                if existing[item.found.relativePath] == nil {
                    summary.added += 1
                } else {
                    summary.updated += 1
                }
                upsert(item, source: source, existing: &existing, grouper: grouper, videoGrouper: videoGrouper)
                touchedVideos = touchedVideos || item.found.kind == .video
            }
            sinceSave += batch.count
            if sinceSave >= Self.saveInterval || index >= pending.count {
                try modelContext.save()
                sinceSave = 0
            }
            progress(ScanProgress(sourceID: sourceID, processed: index, total: pending.count))
        }

        if summary.updated > 0 {
            try grouper.removeOrphans()
        }
        if touchedVideos {
            try videoGrouper.removeOrphans()
        }
        source.isAvailable = true
        source.lastScanDate = .now
        source.audioFileCount = source.files.count { $0.kindRaw == PlaybackItem.Kind.audio.rawValue }
        source.videoFileCount = source.files.count { $0.kindRaw == PlaybackItem.Kind.video.rawValue }
        try modelContext.save()
        return summary
    }

    /// The source's folder can't be reached (drive unplugged, bookmark broken).
    public func markUnavailable(sourceID: UUID) throws {
        guard let source = try source(id: sourceID) else { return }
        source.isAvailable = false
        for file in source.files where file.isAvailable {
            file.isAvailable = false
        }
        try modelContext.save()
    }

    /// Removes a source and everything found in it. Play history (kept by
    /// content fingerprint) stays, so re-adding the folder restores it.
    public func removeSource(id: UUID) throws {
        guard let source = try source(id: id) else { return }
        modelContext.delete(source)
        try modelContext.save()
        try LibraryGrouper(context: modelContext).removeOrphans()
        try VideoGrouper(context: modelContext).removeOrphans()
    }

    /// Artwork keys that anything in the library still uses.
    public func artworkKeysInUse() throws -> Set<String> {
        var keys = Set<String>()
        for track in try modelContext.fetch(FetchDescriptor<Track>()) {
            if let key = track.artworkKey { keys.insert(key) }
        }
        for album in try modelContext.fetch(FetchDescriptor<Album>()) {
            if let key = album.artworkKey { keys.insert(key) }
        }
        for video in try modelContext.fetch(FetchDescriptor<Video>()) {
            for key in [video.posterKey, video.backdropKey, video.stillKey, video.thumbnailKey, video.customArtworkKey] {
                if let key { keys.insert(key) }
            }
        }
        for show in try modelContext.fetch(FetchDescriptor<TVShow>()) {
            for key in [show.posterKey, show.backdropKey, show.customArtworkKey] {
                if let key { keys.insert(key) }
            }
        }
        for season in try modelContext.fetch(FetchDescriptor<Season>()) {
            if let key = season.posterKey { keys.insert(key) }
        }
        return keys
    }

    // MARK: - Merging

    func source(id: UUID) throws -> Source? {
        var descriptor = FetchDescriptor<Source>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func upsert(_ parsed: ParsedFile, source: Source, existing: inout [String: MediaFile], grouper: LibraryGrouper, videoGrouper: VideoGrouper) {
        let found = parsed.found
        let file: MediaFile
        if let current = existing[found.relativePath] {
            file = current
        } else {
            file = MediaFile()
            modelContext.insert(file)
            file.source = source
            file.relativePath = found.relativePath
            existing[found.relativePath] = file
        }
        file.fileName = found.url.lastPathComponent
        // A disc folder has no extension of its own: "dvd" or "bluray" marks it.
        file.fileExtension = found.isDiscFolder ? found.disc?.rawValue ?? "" : found.url.pathExtension.lowercased()
        file.kindRaw = found.kind.rawValue
        file.fileSize = found.size
        file.modificationDate = found.modificationDate
        file.contentKey = parsed.contentKey
        file.isAvailable = true
        if let duration = parsed.tags?.duration, duration > 0 {
            file.duration = duration
        }
        if let format = parsed.tags?.format {
            file.codec = format.codec
            file.sampleRate = format.sampleRate
            file.bitsPerSample = format.bitsPerSample
            file.channels = format.channels
            file.bitRate = format.bitRate
            file.isLossless = format.isLossless
        }

        if found.kind != .video, let video = file.video {
            file.video = nil
            modelContext.delete(video)
        }
        if found.kind == .video, let parsedVideo = parsed.video {
            upsertVideo(parsedVideo, file: file, grouper: videoGrouper)
        }
        guard found.kind == .audio else {
            if let track = file.track {
                file.track = nil
                modelContext.delete(track)
            }
            return
        }
        let track: Track
        if let current = file.track {
            track = current
        } else {
            track = Track()
            modelContext.insert(track)
            file.track = track
        }
        Self.apply(parsed, to: track)
        grouper.attach(
            track,
            sortArtist: parsed.tags?.sortArtist,
            sortAlbum: parsed.tags?.sortAlbum,
            sortAlbumArtist: parsed.tags?.sortAlbumArtist
        )
    }

    /// Tags first, then file and folder names; edited fields are left alone.
    static func apply(_ parsed: ParsedFile, to track: Track) {
        let tags = parsed.tags ?? AudioTags()
        let path = parsed.path
        let edited = Set(track.editedFields)
        func unedited(_ field: TrackField) -> Bool { !edited.contains(field.rawValue) }

        if unedited(.title) {
            let title = tags.title ?? path.title
            track.title = title
            track.sortTitle = NameNormalizer.sortKey(tags.sortTitle ?? title)
        }
        let artist = tags.artist ?? tags.albumArtist ?? path.artist ?? LibraryGrouper.unknownArtist
        if unedited(.artist) {
            track.artistName = artist
        }
        if unedited(.album) {
            track.albumTitle = tags.album ?? path.album ?? LibraryGrouper.unknownAlbum
        }
        if unedited(.albumArtist) {
            track.albumArtistName = tags.albumArtist ?? artist
        }
        if unedited(.compilation) {
            track.isCompilation = tags.isCompilation
                ?? (NameNormalizer.groupKey(tags.albumArtist ?? "") == NameNormalizer.groupKey(LibraryGrouper.variousArtists))
        }
        if unedited(.genre) {
            track.genreName = tags.genre
        }
        if unedited(.year) {
            track.year = tags.year ?? path.year
        }
        if unedited(.trackNumber) {
            track.trackNumber = tags.trackNumber ?? path.trackNumber
            track.trackCount = tags.trackCount
        }
        if unedited(.discNumber) {
            track.discNumber = tags.discNumber ?? path.discNumber
            track.discCount = tags.discCount
        }
        if unedited(.composer) {
            track.composer = tags.composer
        }
        track.lyrics = tags.lyrics
        if let duration = tags.duration, duration > 0 {
            track.duration = duration
        }
        track.artworkKey = parsed.artworkKey
    }

    /// A disc folder's fingerprint: its VIDEO_TS.IFO's or index.bdmv's, so
    /// its history follows it when the folder moves.
    static func discContentKey(_ file: FoundFile) -> String? {
        guard let kind = file.disc else { return nil }
        let marker: URL?
        switch kind {
        case .dvd:
            let videoTS = file.url.lastPathComponent.uppercased() == "VIDEO_TS" ? file.url : DiscLayout.entries(of: file.url)["VIDEO_TS"]
            marker = videoTS.flatMap { DiscLayout.entries(of: $0)["VIDEO_TS.IFO"] }
        case .bluray:
            let bdmv = file.url.lastPathComponent.uppercased() == "BDMV" ? file.url : DiscLayout.entries(of: file.url)["BDMV"]
            marker = bdmv.flatMap { DiscLayout.entries(of: $0)["INDEX.BDMV"] }
        }
        guard let marker, let source = try? FileByteSource(url: marker), let key = try? ContentKey.compute(source) else { return nil }
        return "\(kind.rawValue):\(key)#\(file.size)"
    }

    /// `true` for a path inside a disc's VIDEO_TS or BDMV.
    static func isInsideDisc(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").dropLast().contains { DiscLayout.structureFolders.contains($0.uppercased()) }
    }

    // MARK: - Reading files (off the actor)

    private static let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

    static func enumerate(_ root: URL) -> [FoundFile] {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let baseComponents = base.pathComponents
        // A source that is a disc's VIDEO_TS or BDMV folder is one video.
        if DiscLayout.canPlayDiscs, DiscLayout.structureFolders.contains(base.lastPathComponent.uppercased()), let disc = DiscLayout.disc(at: base) {
            return foundDisc(disc.kind, structureFolder: base, url: base, relativePath: "").map { [$0] } ?? []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: Array(resourceKeys) + [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [FoundFile] = []
        while let url = enumerator.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                // A DVD's VIDEO_TS or a Blu-ray's BDMV: the folder around it
                // is one video, and nothing inside is listed on its own.
                if DiscLayout.canPlayDiscs, DiscLayout.structureFolders.contains(url.lastPathComponent.uppercased()) {
                    enumerator.skipDescendants()
                    if let file = foundDisc(inStructureFolder: url, relativeTo: baseComponents) {
                        found.append(file)
                    }
                }
                continue
            }
            if let file = Self.found(url, relativeTo: baseComponents) {
                found.append(file)
            }
        }
        return found
    }

    static func singleFile(_ url: URL) -> [FoundFile] {
        Self.found(url, relativeTo: nil).map { [$0] } ?? []
    }

    /// The disc a VIDEO_TS or BDMV folder belongs to (`nil` for AUDIO_TS and
    /// the rest, and for folders that only look like one).
    private static func foundDisc(inStructureFolder folder: URL, relativeTo baseComponents: [String]) -> FoundFile? {
        let kind: DiscKind
        switch folder.lastPathComponent.uppercased() {
        case "VIDEO_TS" where DiscLayout.entries(of: folder)["VIDEO_TS.IFO"] != nil:
            kind = .dvd
        case "BDMV" where DiscLayout.entries(of: folder)["INDEX.BDMV"] != nil:
            kind = .bluray
        default:
            return nil
        }
        let root = folder.deletingLastPathComponent().standardizedFileURL
        let components = root.pathComponents
        guard components.count >= baseComponents.count,
              Array(components.prefix(baseComponents.count)) == baseComponents else { return nil }
        let relativePath = components.dropFirst(baseComponents.count).joined(separator: "/")
        return foundDisc(kind, structureFolder: folder, url: root, relativePath: relativePath)
    }

    /// One video for a disc folder. Its size and date are those of the files
    /// in its VIDEO_TS, or in BDMV and the folders in it (STREAM holds a
    /// Blu-ray's video), so a changed disc is read again.
    private static func foundDisc(_ kind: DiscKind, structureFolder: URL, url: URL, relativePath: String) -> FoundFile? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        func contents(of folder: URL) -> [URL]? {
            try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        }
        guard let top = contents(of: structureFolder) else { return nil }
        var size: Int64 = 0
        var date = Date.distantPast
        func add(_ item: URL) {
            let values = try? item.resourceValues(forKeys: keys)
            size += Int64(values?.fileSize ?? 0)
            date = max(date, values?.contentModificationDate ?? .distantPast)
        }
        for item in top {
            if (try? item.resourceValues(forKeys: keys))?.isDirectory == true {
                (contents(of: item) ?? []).forEach(add)
            } else {
                add(item)
            }
        }
        return FoundFile(url: url, relativePath: relativePath, size: size, modificationDate: date, kind: .video, disc: kind)
    }

    static func found(_ url: URL, relativeTo baseComponents: [String]?) -> FoundFile? {
        let ext = url.pathExtension.lowercased()
        guard !skippedExtensions.contains(ext) else { return nil }
        let kind = ContainerFormat(fileExtension: ext).kindHint
        guard kind == .audio || kind == .video,
              let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true else { return nil }
        // Disc images: DVDs and Blu-rays only, not software or data discs.
        var disc: DiscKind?
        if DiscLayout.imageExtensions.contains(ext) {
            // Images play only with a VLCKit built with disc support.
            guard DiscLayout.canPlayDiscs, let image = DiscLayout.disc(at: url) else { return nil }
            disc = image.kind
        }
        var relativePath = ""
        if let baseComponents {
            let components = url.standardizedFileURL.pathComponents
            guard components.count > baseComponents.count,
                  Array(components.prefix(baseComponents.count)) == baseComponents else { return nil }
            relativePath = components.dropFirst(baseComponents.count).joined(separator: "/")
        }
        return FoundFile(
            url: url,
            relativePath: relativePath,
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast,
            kind: kind,
            disc: disc
        )
    }

    static func parse(_ file: FoundFile, hint: VideoContentHint, artworkStore: ArtworkStore, folderArtwork: FolderArtworkCache, videoFolders: VideoFolderCache) -> ParsedFile {
        var tags: AudioTags?
        var contentKey = ""
        var video: ParsedVideo?
        let source = file.isDiscFolder ? nil : try? FileByteSource(url: file.url)
        if let source {
            contentKey = (try? ContentKey.compute(source)) ?? ""
            if file.kind == .audio {
                tags = try? TagReader.read(source)
            }
        }
        if file.isDiscFolder {
            contentKey = discContentKey(file) ?? ""
        }
        if file.kind == .video {
            video = parseVideo(file, source: source, hint: hint, artworkStore: artworkStore, folders: videoFolders)
        }
        if contentKey.isEmpty {
            contentKey = "path:\(file.relativePath)#\(file.size)"
        }
        var artworkKey: String?
        if file.kind == .audio {
            if let data = tags?.artwork?.data {
                artworkKey = artworkStore.store(data)
            }
            if artworkKey == nil {
                artworkKey = folderArtwork.key(forDirectory: file.url.deletingLastPathComponent(), store: artworkStore)
            }
            tags?.artwork = nil
        }
        let name = file.relativePath.isEmpty ? file.url.lastPathComponent : file.relativePath
        return ParsedFile(found: file, contentKey: contentKey, tags: tags, artworkKey: artworkKey, path: PathMetadata(relativePath: name), video: video)
    }
}
