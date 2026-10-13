import Foundation
import MetadataProviders
import PlaybackCore
import SwiftData

/// The values Edit Info shows and changes for a video.
public struct VideoEdit: Sendable, Equatable {
    public var kind: VideoKind
    public var title: String
    public var year: Int?
    public var overview: String
    public var showTitle: String
    public var seasonNumber: Int?
    public var episodeNumber: Int?

    public init(video: Video) {
        kind = video.kind
        title = video.title
        year = video.year
        overview = video.overview ?? ""
        showTitle = video.showTitle ?? ""
        seasonNumber = video.seasonNumber
        episodeNumber = video.episodeNumber
    }
}

/// The values Edit Info shows and changes for a show.
public struct ShowEdit: Sendable, Equatable {
    public var title: String
    public var year: Int?
    public var overview: String

    public init(show: TVShow) {
        title = show.title
        year = show.year
        overview = show.overview ?? ""
    }
}

extension LibraryIndexer {
    // MARK: - Frames as artwork

    /// Takes a frame from videos that have no artwork at all (home videos,
    /// and anything TMDB doesn't know). Returns how many it tried.
    public func generateThumbnails(frameSource: any VideoFrameSource, roots: [UUID: URL], artworkStore: ArtworkStore, batchSize: Int = 6) async -> Int {
        // Typed constants keep the predicate quick to type-check.
        let none: String? = nil
        let maximumAttempts = 2
        let predicate = #Predicate<Video> { video in
            video.thumbnailKey == none && video.posterKey == none && video.stillKey == none
                && video.customArtworkKey == none && video.thumbnailAttempts < maximumAttempts
        }
        var descriptor = FetchDescriptor<Video>(predicate: predicate, sortBy: [SortDescriptor(\Video.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 60
        guard let candidates = try? modelContext.fetch(descriptor) else { return 0 }

        struct Job: Sendable {
            var id: UUID
            var url: URL
            var time: TimeInterval?
        }
        var jobs: [Job] = []
        for video in candidates where jobs.count < batchSize {
            guard let file = video.file, file.isAvailable, let sourceID = file.source?.id, let root = roots[sourceID] else { continue }
            let url = file.relativePath.isEmpty ? root : root.appending(path: file.relativePath, directoryHint: .notDirectory)
            jobs.append(Job(id: video.id, url: url, time: Self.representativeTime(duration: video.duration)))
        }
        guard !jobs.isEmpty else { return 0 }

        var results: [(UUID, String?)] = []
        for chunk in jobs.chunked(2) {
            await withTaskGroup(of: (UUID, String?).self) { group in
                for job in chunk {
                    group.addTask {
                        guard let jpeg = await frameSource.frameJPEG(from: job.url, at: job.time, maxPixelSize: 1_280, precise: false) else { return (job.id, nil) }
                        let key = await Task.detached(priority: .utility) { artworkStore.store(jpeg) }.value
                        return (job.id, key)
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }
        }
        for (id, key) in results {
            guard let video = try? video(id: id) else { continue }
            if let key {
                video.thumbnailKey = key
            } else {
                video.thumbnailAttempts += 1
            }
        }
        try? modelContext.save()
        return jobs.count
    }

    /// A tenth of the way in skips black intros and title cards.
    static func representativeTime(duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration > 0 else { return nil }
        if duration < 30 { return duration * 0.3 }
        return min(duration * 0.1, 600)
    }

    // MARK: - Edits

    /// Applies Edit Info to a video; edited fields are remembered so rescans
    /// and lookups never overwrite them.
    public func applyVideoEdit(_ edit: VideoEdit, videoID: UUID) throws {
        guard let video = try video(id: videoID) else { return }
        var edited = Set(video.editedFields)
        let grouper = VideoGrouper(context: modelContext)
        let trimmedTitle = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShow = edit.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let overview = edit.overview.trimmingCharacters(in: .whitespacesAndNewlines)

        if edit.kind != video.kind {
            video.kind = edit.kind
            edited.insert(VideoField.kind.rawValue)
            Self.resetLookup(video)
        }
        if trimmedTitle != video.title {
            video.title = trimmedTitle
            video.sortTitle = NameNormalizer.sortKey(trimmedTitle.isEmpty ? video.displayTitle : trimmedTitle)
            edited.insert(VideoField.title.rawValue)
        }
        if edit.year != video.year {
            video.year = edit.year
            edited.insert(VideoField.year.rawValue)
        }
        if overview != (video.overview ?? "") {
            video.overview = overview.isEmpty ? nil : overview
            edited.insert(VideoField.overview.rawValue)
        }
        if video.kind == .episode {
            if edit.seasonNumber != video.seasonNumber || edit.episodeNumber != video.episodeNumber {
                video.seasonNumber = edit.seasonNumber
                video.episodeNumber = edit.episodeNumber
                video.lastEpisodeNumber = nil
                edited.insert(VideoField.episode.rawValue)
            }
            if !trimmedShow.isEmpty, trimmedShow != video.showTitle {
                video.showTitle = trimmedShow
                edited.insert(VideoField.show.rawValue)
            }
            video.editedFields = edited.sorted()
            grouper.attach(video, showTitle: video.showTitle, showYear: video.show?.year)
            if video.matchState != .local, video.show?.matchState == .matched || video.show?.matchState == .manual {
                video.matchState = .pending // new numbers: fetch that episode's details
            }
        } else {
            video.editedFields = edited.sorted()
            grouper.detach(video)
        }
        try modelContext.save()
        try grouper.removeOrphans()
    }

    public func applyShowEdit(_ edit: ShowEdit, showID: UUID) throws {
        guard let show = try show(id: showID) else { return }
        var edited = Set(show.editedFields)
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let overview = edit.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != show.title {
            show.title = title
            show.sortTitle = NameNormalizer.sortKey(title)
            edited.insert(VideoField.title.rawValue)
            for episode in show.episodes {
                episode.showTitle = title
            }
        }
        if edit.year != show.year {
            show.year = edit.year
            edited.insert(VideoField.year.rawValue)
        }
        if overview != (show.overview ?? "") {
            show.overview = overview.isEmpty ? nil : overview
            edited.insert(VideoField.overview.rawValue)
        }
        show.editedFields = edited.sorted()
        try modelContext.save()
    }

    /// The user's own artwork (an image they chose, or a frame they picked);
    /// `nil` goes back to automatic artwork.
    public func setArtwork(videoID: UUID, key: String?) throws {
        guard let video = try video(id: videoID) else { return }
        video.customArtworkKey = key
        var edited = Set(video.editedFields)
        if key == nil { edited.remove(VideoField.artwork.rawValue) } else { edited.insert(VideoField.artwork.rawValue) }
        video.editedFields = edited.sorted()
        try modelContext.save()
    }

    public func setArtwork(showID: UUID, key: String?) throws {
        guard let show = try show(id: showID) else { return }
        show.customArtworkKey = key
        try modelContext.save()
    }

    /// Looks the video up again (after a rename, or when TMDB found nothing).
    public func requestLookup(videoID: UUID) throws {
        guard let video = try video(id: videoID), video.kind != .homeVideo else { return }
        if video.kind == .episode, let show = video.show {
            show.matchState = .pending
            for episode in show.episodes where episode.matchState != .local {
                episode.matchState = .pending
            }
        } else {
            video.matchState = .pending
        }
        try modelContext.save()
    }

    public func requestLookup(showID: UUID) throws {
        guard let show = try show(id: showID) else { return }
        show.matchState = .pending
        for episode in show.episodes {
            episode.matchState = .pending
        }
        try modelContext.save()
    }

    /// What a source's videos are; its videos are read again on the next scan.
    public func setVideoHint(sourceID: UUID, hint: VideoContentHint) throws {
        guard let source = try source(id: sourceID) else { return }
        source.videoHint = hint
        for file in source.files where file.kind == .video {
            file.videoProbeVersion = 0
        }
        try modelContext.save()
    }
}
