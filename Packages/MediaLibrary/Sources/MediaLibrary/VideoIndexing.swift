import Foundation
import MetadataProviders
import PlaybackCore
import SwiftData

/// What scanning a video file produced: container details, what its name
/// says it is, `.nfo` details and artwork found next to it.
struct ParsedVideo: Sendable {
    var info: VideoInfo?
    var name: VideoName
    var nfo: NFOInfo?
    var showNFO: NFOInfo?
    var posterKey: String?
    var backdropKey: String?
    var stillKey: String?
    var showPosterKey: String?
    var showBackdropKey: String?
    var seasonPosterKey: String?
}

/// Directory listings, `.nfo` files and images, each read once per scan
/// (a season folder holds many episodes that share them).
final class VideoFolderCache: @unchecked Sendable {
    private let lock = NSLock()
    private var listings: [String: [String: URL]] = [:]
    private var imageKeys: [String: String?] = [:]
    private var nfos: [String: NFOInfo?] = [:]

    static let imageExtensions = ["jpg", "jpeg", "png", "webp", "tbn"]
    static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "smi", "sup", "ttml", "dfxp"]

    /// Lowercased file name → URL, for the files in `directory`.
    func listing(_ directory: URL) -> [String: URL] {
        let path = directory.path(percentEncoded: false)
        lock.lock()
        if let cached = listings[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        var result: [String: URL] = [:]
        if let names = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for name in names where !name.hasPrefix(".") {
                result[name.lowercased()] = directory.appending(path: name, directoryHint: .notDirectory)
            }
        }
        lock.lock()
        listings[path] = result
        lock.unlock()
        return result
    }

    /// The first image named `base` + an image extension, stored as artwork.
    func imageKey(in directory: URL, names: [String], store: ArtworkStore) -> String? {
        let listing = listing(directory)
        for name in names {
            for ext in Self.imageExtensions {
                if let url = listing["\(name.lowercased()).\(ext)"] {
                    return imageKey(url, store: store)
                }
            }
        }
        return nil
    }

    func imageKey(_ url: URL, store: ArtworkStore) -> String? {
        let path = url.path(percentEncoded: false)
        lock.lock()
        if let cached = imageKeys[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let key = (try? Data(contentsOf: url)).flatMap { store.store($0) }
        lock.lock()
        imageKeys[path] = key
        lock.unlock()
        return key
    }

    func nfo(in directory: URL, named name: String) -> NFOInfo? {
        guard let url = listing(directory)[name.lowercased()] else { return nil }
        let path = url.path(percentEncoded: false)
        lock.lock()
        if let cached = nfos[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let info = NFOInfo.read(url: url)
        lock.lock()
        nfos[path] = info
        lock.unlock()
        return info
    }

    /// How many videos a folder holds (posters named `poster.jpg` only
    /// belong to a movie when it has the folder to itself).
    func videoCount(in directory: URL) -> Int {
        listing(directory).keys.count { name in
            let ext = (name.split(separator: ".").last.map(String.init) ?? "")
            return ContainerFormat(fileExtension: ext).kindHint == .video
        }
    }
}

extension LibraryIndexer {
    /// Bump when `VideoProbe` or the name parser learn something that
    /// existing files should be read again for.
    /// Bumped when parsing learns something new, so unchanged videos are read
    /// again on the next scan. 2: local artwork is remembered (Milestone 5).
    /// 3: DVD and Blu-ray folders and images (Milestone 6).
    static let videoProbeVersion = 3

    /// Reads everything about a video file (off the actor).
    static func parseVideo(_ file: FoundFile, source: ByteSource?, hint: VideoContentHint, artworkStore: ArtworkStore, folders: VideoFolderCache) -> ParsedVideo {
        var info = source.flatMap { try? VideoProbe.read($0) }
        let disc = file.disc != nil ? DiscLayout.disc(at: file.url) : nil
        if let disc, info == nil || file.isDiscFolder {
            info = discVideoInfo(disc)
        }
        // A disc that is a whole source is named after its folder or image.
        let relative = file.relativePath.isEmpty ? disc?.displayName ?? file.url.lastPathComponent : file.relativePath
        var name = VideoNameParser.parse(relativePath: relative, hint: hint, duration: info?.duration)
        // A disc folder keeps its artwork and .nfo inside it (as Kodi does):
        // poster.jpg and movie.nfo next to VIDEO_TS or BDMV.
        let directory = file.isDiscFolder ? file.url : file.url.deletingLastPathComponent()
        let base = file.isDiscFolder ? "movie" : file.url.deletingPathExtension().lastPathComponent

        // An .nfo file beside the video says what it is.
        var nfo = folders.nfo(in: directory, named: "\(base).nfo")
        if nfo == nil, name.kind != .episode, folders.videoCount(in: directory) <= 1 {
            nfo = folders.nfo(in: directory, named: "movie.nfo")
        }
        if nfo == nil, file.isDiscFolder, let disc {
            // Or VIDEO_TS.nfo in VIDEO_TS, index.nfo in BDMV.
            let structure = disc.kind == .dvd ? disc.playbackURL : DiscLayout.entries(of: disc.root)["BDMV"]
            if let structure {
                nfo = folders.nfo(in: structure, named: disc.kind == .dvd ? "VIDEO_TS.nfo" : "index.nfo")
            }
        }
        if let nfo, hint != .homeVideos {
            switch nfo.kind {
            case .movie where name.kind != .movie:
                var movie = VideoName(kind: .movie, title: nfo.title ?? name.title)
                movie.year = nfo.year
                name = movie
            case .episode where name.kind != .episode:
                var episode = VideoName(kind: .episode, title: nfo.title ?? "")
                episode.showTitle = nfo.showTitle ?? name.showTitle
                episode.season = nfo.season
                episode.episode = nfo.episode
                name = episode
            default:
                break
            }
        }

        var parsed = ParsedVideo(info: nil, name: name, nfo: nfo)
        switch name.kind {
        case .movie, .homeVideo:
            // poster.jpg and fanart.jpg only when the movie has the folder to itself.
            let ownsFolder = folders.videoCount(in: directory) <= 1 || name.part != nil
            let posterNames = ["\(base)-poster", "\(base)"] + (ownsFolder ? ["poster", "folder", "cover", "movie"] : [])
            let backdropNames = ["\(base)-fanart", "\(base)-backdrop"] + (ownsFolder ? ["fanart", "backdrop", "background"] : [])
            parsed.posterKey = folders.imageKey(in: directory, names: posterNames, store: artworkStore)
            parsed.backdropKey = folders.imageKey(in: directory, names: backdropNames, store: artworkStore)
        case .episode:
            parsed.stillKey = folders.imageKey(in: directory, names: ["\(base)-thumb", base], store: artworkStore)
            if let showDirectory = showDirectory(for: file, name: name) {
                parsed.showNFO = folders.nfo(in: showDirectory, named: "tvshow.nfo")
                parsed.showPosterKey = folders.imageKey(in: showDirectory, names: ["poster", "folder", "show"], store: artworkStore)
                parsed.showBackdropKey = folders.imageKey(in: showDirectory, names: ["fanart", "backdrop", "background"], store: artworkStore)
                if let season = name.season {
                    let padded = String(format: "%02d", season)
                    let names = season == 0
                        ? ["season-specials-poster", "season00-poster", "season-specials"]
                        : ["season\(padded)-poster", "season\(season)-poster", "season\(padded)", "season\(season)"]
                    parsed.seasonPosterKey = folders.imageKey(in: showDirectory, names: names, store: artworkStore)
                }
            }
            // A season folder's own poster.
            if parsed.seasonPosterKey == nil, VideoNameParser.seasonNumber(folder: directory.lastPathComponent) != nil {
                parsed.seasonPosterKey = folders.imageKey(in: directory, names: ["poster", "folder", "cover"], store: artworkStore)
            }
        }
        // Cover art inside the file (Matroska attachments, MP4 covr).
        if parsed.posterKey == nil, name.kind == .movie, let cover = info?.coverArt {
            parsed.posterKey = artworkStore.store(cover)
        }
        info?.coverArt = nil
        parsed.info = info
        return parsed
    }

    /// What a DVD's IFO files or a Blu-ray's playlists say, as a container
    /// probe would: the film's length, picture, sound and subtitles.
    static func discVideoInfo(_ disc: Disc) -> VideoInfo? {
        switch disc.kind {
        case .dvd:
            guard let dvd = DVDVideoInfo.read(disc) else { return nil }
            var info = VideoInfo(container: "DVD-Video")
            info.duration = dvd.mainTitle?.duration
            info.chapterCount = dvd.mainTitle?.chapters
            if let video = dvd.video {
                info.width = video.width
                info.height = video.height
                info.frameRate = video.frameRate
                info.videoCodec = video.codec
            }
            info.audioTracks = dvd.audio.enumerated().map { index, audio in
                VideoInfo.AudioTrack(codec: audio.codec, channels: audio.channels, language: audio.language, title: audio.isCommentary ? "Commentary" : nil, isDefault: index == 0)
            }
            info.subtitleTracks = dvd.subtitles.map { VideoInfo.SubtitleTrack(codec: "DVD", language: $0.language) }
            return info
        case .bluray:
            var info = VideoInfo(container: "Blu-ray")
            guard let main = BlurayInfo.read(disc)?.mainPlaylist else { return info }
            info.duration = main.duration
            info.chapterCount = main.chapters
            if let video = main.video, video.width > 0 {
                info.width = video.width
                info.height = video.height
                info.frameRate = video.frameRate
                info.videoCodec = video.codec
            }
            info.audioTracks = main.audio.enumerated().map { index, audio in
                VideoInfo.AudioTrack(codec: audio.codec, channels: audio.channels, language: audio.language, isDefault: index == 0)
            }
            info.subtitleTracks = main.subtitles.map { VideoInfo.SubtitleTrack(codec: "PGS", language: $0) }
            return info
        }
    }

    /// The show's folder: the one above a season folder, or the file's own
    /// folder when its name is the show's name.
    private static func showDirectory(for file: FoundFile, name: VideoName) -> URL? {
        let directory = file.url.deletingLastPathComponent()
        if VideoNameParser.seasonNumber(folder: directory.lastPathComponent) != nil, !file.relativePath.isEmpty,
           file.relativePath.split(separator: "/").count >= 3 {
            return directory.deletingLastPathComponent()
        }
        guard let show = name.showTitle, !file.relativePath.isEmpty, file.relativePath.contains("/") else { return nil }
        let folder = VideoNameParser.normalize(directory.lastPathComponent)
        return NameNormalizer.groupKey(VideoNameParser.titleBeforeJunk(folder)).hasPrefix(NameNormalizer.groupKey(show)) ? directory : nil
    }

    // MARK: - Merging (on the actor)

    func upsertVideo(_ parsed: ParsedVideo, file: MediaFile, grouper: VideoGrouper) {
        if let info = parsed.info {
            Self.applyTechnical(info, to: file)
        }
        file.videoProbeVersion = Self.videoProbeVersion

        let video: Video
        if let current = file.video {
            video = current
        } else {
            video = Video()
            modelContext.insert(video)
            file.video = video
        }
        Self.apply(parsed, to: video)
        if video.kind == .episode {
            grouper.attach(video, showTitle: parsed.nfo?.showTitle ?? parsed.name.showTitle, showYear: parsed.name.showYear)
            if let show = video.show {
                Self.applyShowDetails(parsed, to: show)
                if let season = video.season, season.posterKey == nil {
                    season.posterKey = parsed.seasonPosterKey
                }
                if video.showTitle != show.title {
                    video.showTitle = show.title
                }
            }
        } else {
            grouper.detach(video)
        }
    }

    static func applyTechnical(_ info: VideoInfo, to file: MediaFile) {
        if let duration = info.duration, duration > 0 {
            file.duration = duration
        }
        file.width = info.width
        file.height = info.height
        file.frameRate = info.frameRate
        file.videoCodec = info.videoCodec
        file.audioCodec = info.audioTracks.first(where: \.isDefault)?.codec ?? info.audioTracks.first?.codec
        file.channels = info.maximumAudioChannels
        file.dynamicRangeRaw = info.dynamicRange?.rawValue
        file.hasAtmos = info.hasAtmos
        let audio = unique(info.audioTracks.compactMap(\.language))
        file.audioLanguages = audio.isEmpty ? nil : audio.joined(separator: ",")
        let subtitles = unique(info.subtitleTracks.compactMap(\.language))
        file.subtitleLanguages = subtitles.isEmpty ? nil : subtitles.joined(separator: ",")
        file.hasSubtitles = !info.subtitleTracks.isEmpty
        file.hasSDHSubtitles = info.subtitleTracks.contains(where: \.isHearingImpaired)
        file.recordedDate = info.creationDate
        file.location = info.location
        if file.codec == nil, let codec = info.videoCodec {
            file.codec = codec
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Names, `.nfo` details and local artwork. Edited fields are never
    /// touched, `.nfo` fields win over names, and names never replace what a
    /// TMDB match supplied.
    static func apply(_ parsed: ParsedVideo, to video: Video) {
        let edited = Set(video.editedFields)
        func unedited(_ field: VideoField) -> Bool { !edited.contains(field.rawValue) }
        let name = parsed.name
        let nfo = parsed.nfo
        var local = Set<String>()

        let newKind = VideoKind(name.kind)
        if unedited(.kind), video.kind != newKind {
            // A different kind of video: an old match no longer applies.
            video.kind = newKind
            resetLookup(video)
        }
        if video.kind == .homeVideo {
            video.matchState = .local
        }
        let isLookedUp = video.matchState == .matched || video.matchState == .manual || video.matchState == .keyless

        if unedited(.title) {
            if let title = nfo?.title {
                video.title = title
                local.insert(VideoField.title.rawValue)
            } else if !isLookedUp {
                video.title = name.title
            }
            video.sortTitle = NameNormalizer.sortKey(nfo?.sortTitle ?? (video.title.isEmpty ? video.displayTitle : video.title))
        }
        if unedited(.year) {
            if let year = nfo?.year {
                video.year = year
                local.insert(VideoField.year.rawValue)
            } else if !isLookedUp {
                video.year = name.year
            }
        }
        if unedited(.episode) {
            video.seasonNumber = nfo?.season ?? name.season
            video.episodeNumber = nfo?.episode ?? name.episode
            video.lastEpisodeNumber = name.lastEpisode
        }
        video.edition = name.edition
        video.part = name.part

        if let nfo {
            if unedited(.overview), let overview = nfo.overview {
                video.overview = overview
                local.insert(VideoField.overview.rawValue)
            }
            if unedited(.genres), !nfo.genres.isEmpty {
                video.genres = nfo.genres
                local.insert(VideoField.genres.rawValue)
            }
            if unedited(.contentRating), let rating = nfo.contentRating {
                video.contentRating = rating
                local.insert(VideoField.contentRating.rawValue)
            }
            if unedited(.releaseDate), let date = nfo.releaseDate {
                video.releaseDate = date
                local.insert(VideoField.releaseDate.rawValue)
            }
            if unedited(.runtime), let minutes = nfo.runtime, minutes > 0 {
                video.runtime = Double(minutes * 60)
                local.insert(VideoField.runtime.rawValue)
            }
            if unedited(.cast), !nfo.cast.isEmpty {
                video.cast = nfo.cast.map { CastMember(name: $0.name, role: $0.role, imageURL: $0.imageURL.flatMap(URL.init(string:))) }
                local.insert(VideoField.cast.rawValue)
            }
            video.originalTitle = nfo.originalTitle ?? video.originalTitle
            video.tagline = nfo.tagline ?? video.tagline
            video.rating = nfo.rating ?? video.rating
            if !nfo.directors.isEmpty { video.directors = nfo.directors }
            video.studio = nfo.studios.first ?? video.studio
            if video.tmdbID == nil, let tmdbID = nfo.tmdbID, nfo.kind != .episode {
                video.tmdbID = tmdbID
            }
            video.imdbID = video.imdbID ?? nfo.imdbID
        }
        // Local artwork beats a frame and the free sources' small posters; it
        // never replaces the user's choice.
        if parsed.posterKey != nil || parsed.stillKey != nil {
            local.insert(VideoField.artwork.rawValue)
        }
        video.localFields = local.sorted()
        if let key = parsed.posterKey { video.posterKey = key }
        if let key = parsed.backdropKey { video.backdropKey = key }
        if let key = parsed.stillKey { video.stillKey = key }
    }

    /// Show details from `tvshow.nfo` and the show folder's artwork.
    static func applyShowDetails(_ parsed: ParsedVideo, to show: TVShow) {
        if show.posterKey == nil { show.posterKey = parsed.showPosterKey }
        if show.backdropKey == nil { show.backdropKey = parsed.showBackdropKey }
        guard let nfo = parsed.showNFO else { return }
        let edited = Set(show.editedFields)
        var local = Set(show.localFields)
        if !edited.contains(VideoField.title.rawValue), let title = nfo.title {
            show.title = title
            show.sortTitle = NameNormalizer.sortKey(nfo.sortTitle ?? title)
            local.insert(VideoField.title.rawValue)
        }
        if !edited.contains(VideoField.overview.rawValue), let overview = nfo.overview {
            show.overview = overview
            local.insert(VideoField.overview.rawValue)
        }
        if !edited.contains(VideoField.genres.rawValue), !nfo.genres.isEmpty {
            show.genres = nfo.genres
            local.insert(VideoField.genres.rawValue)
        }
        if !edited.contains(VideoField.year.rawValue), let year = nfo.year {
            show.year = year
            local.insert(VideoField.year.rawValue)
        }
        if !nfo.cast.isEmpty, !edited.contains(VideoField.cast.rawValue) {
            show.cast = nfo.cast.map { CastMember(name: $0.name, role: $0.role, imageURL: $0.imageURL.flatMap(URL.init(string:))) }
            local.insert(VideoField.cast.rawValue)
        }
        show.contentRating = nfo.contentRating ?? show.contentRating
        show.network = nfo.studios.first ?? show.network
        show.tmdbID = show.tmdbID ?? nfo.tmdbID
        show.imdbID = show.imdbID ?? nfo.imdbID
        show.localFields = local.sorted()
    }

    /// Forgets a lookup (the video turned out to be something else).
    static func resetLookup(_ video: Video) {
        let edited = Set(video.editedFields)
        video.matchState = video.kind == .homeVideo ? .local : .pending
        video.lastMatchAttempt = nil
        video.tmdbID = nil
        if !edited.contains(VideoField.overview.rawValue) { video.overview = nil }
        if !edited.contains(VideoField.genres.rawValue) { video.genres = [] }
        if !edited.contains(VideoField.cast.rawValue) { video.castData = nil }
        video.tagline = nil
        video.rating = nil
        video.directors = []
        video.posterKey = nil
        video.backdropKey = nil
        video.stillKey = nil
    }
}

/// Finds or creates the show and season an episode belongs to, and removes
/// shows and seasons nothing refers to any more.
final class VideoGrouper {
    static let unknownShow = "Unknown Show"

    let context: ModelContext
    private var shows: [String: TVShow] = [:]
    private var seasons: [String: Season] = [:]

    init(context: ModelContext) {
        self.context = context
    }

    static func showKey(title: String, year: Int?) -> String {
        let base = NameNormalizer.groupKey(title)
        return year.map { "\(base)|\($0)" } ?? base
    }

    func show(title rawTitle: String?, year: Int?) -> TVShow {
        let title = rawTitle.flatMap { $0.isEmpty ? nil : $0 } ?? Self.unknownShow
        let key = Self.showKey(title: title, year: year)
        if let cached = shows[key] {
            return cached
        }
        var descriptor = FetchDescriptor<TVShow>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            shows[key] = existing
            return existing
        }
        if year == nil {
            // "Doctor Who" typed in Edit Info joins "Doctor Who (2005)" when that's the only one.
            let prefix = key + "|"
            let candidates = (try? context.fetch(FetchDescriptor<TVShow>(predicate: #Predicate { $0.key.starts(with: prefix) }))) ?? []
            if candidates.count == 1, let only = candidates.first {
                shows[key] = only
                return only
            }
        }
        let show = TVShow()
        show.key = key
        show.title = title
        show.sortTitle = NameNormalizer.sortKey(title)
        show.year = year
        context.insert(show)
        shows[key] = show
        return show
    }

    func season(_ number: Int, of show: TVShow) -> Season {
        let key = "\(show.key)#\(number)"
        if let cached = seasons[key], cached.show?.persistentModelID == show.persistentModelID {
            return cached
        }
        if let existing = show.seasons.first(where: { $0.number == number }) {
            seasons[key] = existing
            return existing
        }
        let season = Season()
        season.key = key
        season.number = number
        context.insert(season)
        season.show = show
        seasons[key] = season
        return season
    }

    /// Points an episode at its show and season.
    func attach(_ video: Video, showTitle: String?, showYear: Int?) {
        let edited = Set(video.editedFields)
        let title = edited.contains(VideoField.show.rawValue) ? video.showTitle : showTitle
        let year = edited.contains(VideoField.show.rawValue) ? nil : showYear
        let show = show(title: title, year: year)
        if video.show?.persistentModelID != show.persistentModelID {
            video.show = show
        }
        let season = season(video.seasonNumber ?? 1, of: show)
        if video.season?.persistentModelID != season.persistentModelID {
            video.season = season
        }
        if video.showTitle != show.title {
            video.showTitle = show.title
        }
        if show.dateAdded > video.dateAdded {
            show.dateAdded = video.dateAdded
        }
    }

    /// A movie or home video belongs to no show.
    func detach(_ video: Video) {
        if video.show != nil { video.show = nil }
        if video.season != nil { video.season = nil }
        if video.showTitle != nil { video.showTitle = nil }
    }

    /// Deletes seasons without episodes, then shows without episodes.
    func removeOrphans() throws {
        try context.save()
        for season in try context.fetch(FetchDescriptor<Season>()) where season.episodes.isEmpty {
            seasons = seasons.filter { $0.value.persistentModelID != season.persistentModelID }
            context.delete(season)
        }
        try context.save()
        for show in try context.fetch(FetchDescriptor<TVShow>()) where show.episodes.isEmpty {
            shows.removeValue(forKey: show.key)
            context.delete(show)
        }
        try context.save()
    }
}
