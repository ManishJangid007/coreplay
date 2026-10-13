import Foundation

/// What a video's file and folder names say it is: a movie, a TV episode or
/// a home video, with the title, year, show, season and episode numbers.
///
/// Understands release-style and hand-made names:
/// - Movies: `Heat (1995).mkv`, `The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv`,
///   `Heat (1995)/heat-1080p.mkv` (the folder names the movie).
/// - Episodes: `Show.S01E02.Title.mkv`, `Show - 1x02 - Title.mkv`,
///   `S01E01E02` and `S01E01-02` (two episodes in one file),
///   `Show/Season 1/02 - Title.mkv`, and `[Group] Show - 05 [1080p].mkv`.
/// - Home videos: anything else, and camera names such as `IMG_1234.MOV`.
public struct VideoName: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case movie
        case episode
        case homeVideo
    }

    public var kind: Kind
    /// The movie's title, the episode's title (empty when the name has none)
    /// or the home video's name.
    public var title: String
    public var year: Int?
    public var showTitle: String?
    public var showYear: Int?
    public var season: Int?
    public var episode: Int?
    /// The last episode in a file that holds several (`S01E01E02`).
    public var lastEpisode: Int?
    /// "2024-03-15", for daily shows named by air date.
    public var airDate: String?
    /// "Director's Cut", "Extended Edition"…
    public var edition: String?
    /// `CD1`, `Part 2`: one piece of a movie split across files.
    public var part: Int?

    public init(kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }
}

/// What the user said a source folder holds (Sources ▸ Videos in This Folder).
public enum VideoContentHint: String, Sendable, Codable, CaseIterable {
    /// Decide from each file's name.
    case automatic
    case movies
    case tvShows
    case homeVideos
}

public enum VideoNameParser {
    /// - Parameters:
    ///   - relativePath: The path below the source's root, e.g.
    ///     `"Breaking Bad/Season 1/Breaking.Bad.S01E01.mkv"`.
    ///   - hint: What the source holds, when the user said so.
    ///   - currentYear: Years after this (plus one) aren't release years
    ///     ("Blade Runner 2049").
    public static func parse(
        relativePath: String,
        hint: VideoContentHint = .automatic,
        duration: TimeInterval? = nil,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) -> VideoName {
        let components = relativePath.split(separator: "/").map(String.init)
        let fileName = components.last ?? relativePath
        let folders = Array(components.dropLast())
        var base = PathMetadata.removingExtension(fileName)
        let hasGroupTag = base.hasPrefix("[")
        base = stripLeadingGroupTag(base)
        let name = normalize(base)
        let maximumYear = currentYear + 1

        if hint == .homeVideos {
            return homeVideo(name, base: base)
        }

        // Season folders: "Season 2", "S02", "Specials".
        let seasonFolderIndex = folders.lastIndex { seasonNumber(folder: $0) != nil }
        let seasonFromFolder = seasonFolderIndex.flatMap { seasonNumber(folder: folders[$0]) }

        if hint != .movies, var episode = episodeName(in: name, hasGroupTag: hasGroupTag, seasonFromFolder: seasonFromFolder, hint: hint, maximumYear: maximumYear) {
            episode.showTitle = showTitle(fromName: episode.showTitle, folders: folders, seasonFolderIndex: seasonFolderIndex, maximumYear: maximumYear, year: &episode.showYear)
            return episode
        }
        if hint == .tvShows || (hint == .automatic && seasonFromFolder != nil) {
            // A file in a season folder without a recognisable number.
            var episode = VideoName(kind: .episode, title: titleBeforeJunk(name))
            episode.season = seasonFromFolder ?? 1
            episode.showTitle = showTitle(fromName: nil, folders: folders, seasonFolderIndex: seasonFolderIndex, maximumYear: maximumYear, year: &episode.showYear)
            return episode
        }

        if hint == .automatic, isCameraName(base) {
            return homeVideo(name, base: base)
        }

        // Movies: a year in brackets, or a year followed by release words, is
        // a movie. A bare year ("Christmas 2019") is too, unless the video is
        // short: plenty of home videos are named that way.
        let isFeatureLength = duration.map { $0 >= 40 * 60 }
        let fromName = movieCandidate(name, isDotted: !base.contains(" "), maximumYear: maximumYear)
        if let fromName, fromName.isConfident(isFeatureLength: isFeatureLength) {
            return fromName.name
        }
        // "Heat (1995)/heat-1080p.mkv": the folder names the movie.
        if let folder = folders.last,
           let fromFolder = movieCandidate(normalize(stripLeadingGroupTag(folder)), isDotted: !folder.contains(" "), maximumYear: maximumYear),
           fromFolder.isConfident(isFeatureLength: isFeatureLength) {
            var movie = fromFolder.name
            movie.part = fromName?.name.part ?? movie.part
            movie.edition = fromName?.name.edition ?? movie.edition
            return movie
        }
        if hint == .movies {
            return fromName?.name ?? VideoName(kind: .movie, title: tidy(name))
        }
        return homeVideo(name, base: base)
    }

    // MARK: - Episodes

    private static func episodeName(in name: String, hasGroupTag: Bool, seasonFromFolder: Int?, hint: VideoContentHint, maximumYear: Int) -> VideoName? {
        let range = NSRange(name.startIndex..., in: name)

        // S01E02, S01E02E03, S01E02-E03, S01E02-03, s1 e2.
        if let match = Patterns.seasonEpisode.regex.firstMatch(in: name, range: range) {
            var result = VideoName(kind: .episode, title: "")
            result.season = int(match, 1, in: name)
            result.episode = int(match, 2, in: name)
            result.lastEpisode = int(match, 3, in: name) ?? int(match, 4, in: name)
            return finishEpisode(result, match: match, in: name)
        }
        // 1x02, 01x02.
        if let match = Patterns.crossEpisode.regex.firstMatch(in: name, range: range) {
            var result = VideoName(kind: .episode, title: "")
            result.season = int(match, 1, in: name)
            result.episode = int(match, 2, in: name)
            return finishEpisode(result, match: match, in: name)
        }
        // "Season 1 Episode 2".
        if let match = Patterns.wordyEpisode.regex.firstMatch(in: name, range: range) {
            var result = VideoName(kind: .episode, title: "")
            result.season = int(match, 1, in: name)
            result.episode = int(match, 2, in: name)
            return finishEpisode(result, match: match, in: name)
        }
        // "[Group] Show - 05 [1080p]": anime-style absolute numbering.
        if hasGroupTag, let match = Patterns.dashEpisode.regex.firstMatch(in: name, range: range) {
            var result = VideoName(kind: .episode, title: "")
            result.season = seasonFromFolder ?? 1
            result.episode = int(match, 1, in: name)
            return finishEpisode(result, match: match, in: name)
        }
        guard seasonFromFolder != nil || hint == .tvShows else { return nil }
        // "Episode 5", "Ep 5", "E05" inside a season folder.
        if let match = Patterns.bareEpisode.regex.firstMatch(in: name, range: range) {
            var result = VideoName(kind: .episode, title: "")
            result.season = seasonFromFolder ?? 1
            result.episode = int(match, 1, in: name)
            return finishEpisode(result, match: match, in: name)
        }
        // "02 - Title", "02. Title" inside a season folder.
        if let match = Patterns.leadingNumber.regex.firstMatch(in: name, range: range) {
            var result = VideoName(kind: .episode, title: "")
            result.season = seasonFromFolder ?? 1
            result.episode = int(match, 1, in: name)
            return finishEpisode(result, match: match, in: name)
        }
        // Daily shows: "Show 2024 03 15" (only for sources marked as TV).
        if hint == .tvShows, let match = Patterns.airDate.regex.firstMatch(in: name, range: range),
           let year = int(match, 1, in: name), let month = int(match, 2, in: name), let day = int(match, 3, in: name),
           (1900...maximumYear).contains(year), (1...12).contains(month), (1...31).contains(day) {
            var result = VideoName(kind: .episode, title: "")
            result.airDate = String(format: "%04d-%02d-%02d", year, month, day)
            return finishEpisode(result, match: match, in: name)
        }
        return nil
    }

    /// Show name before the marker, episode title after it.
    private static func finishEpisode(_ episode: VideoName, match: NSTextCheckingResult, in name: String) -> VideoName {
        var result = episode
        guard let whole = Range(match.range, in: name) else { return result }
        let before = trimSeparators(String(name[..<whole.lowerBound]))
        let after = trimSeparators(String(name[whole.upperBound...]))
        result.showTitle = before.isEmpty ? nil : before
        result.title = titleBeforeJunk(after)
        return result
    }

    /// The show's name from the file name, or from the folders above the
    /// season folder (or the file's own folder) when the name has none.
    private static func showTitle(fromName: String?, folders: [String], seasonFolderIndex: Int?, maximumYear: Int, year: inout Int?) -> String? {
        var candidate: String?
        if let seasonFolderIndex, seasonFolderIndex > 0 {
            // "Show/Season 1/…": the folder is the deliberate name.
            candidate = normalize(stripLeadingGroupTag(folders[seasonFolderIndex - 1]))
        } else if let fromName, !fromName.isEmpty {
            candidate = fromName
        } else if let folder = folders.last, seasonNumber(folder: folder) == nil {
            candidate = normalize(stripLeadingGroupTag(folder))
        }
        guard var show = candidate.map(titleBeforeJunk), !show.isEmpty else { return nil }
        if let (stripped, foundYear) = strippingTrailingYear(show, maximumYear: maximumYear) {
            show = stripped
            year = foundYear
        }
        return show
    }

    /// "Season 2", "Series 2", "S02", "Specials" (season 0).
    public static func seasonNumber(folder: String) -> Int? {
        let lowered = normalize(folder).lowercased()
        if lowered == "specials" || lowered == "special" || lowered == "extras" { return 0 }
        for prefix in ["season", "series", "saison", "staffel", "temporada", "stagione"] where lowered.hasPrefix(prefix) {
            let rest = lowered.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let number = Int(rest.prefix(while: \.isNumber)), (0...3000).contains(number) {
                return number
            }
        }
        if lowered.count <= 4, lowered.hasPrefix("s"), let number = Int(lowered.dropFirst()), (0...999).contains(number) {
            return number
        }
        return nil
    }

    // MARK: - Movies

    private struct MovieCandidate {
        var name: VideoName
        var yearIsBracketed: Bool
        var hasReleaseWords: Bool
        var isDotted: Bool

        func isConfident(isFeatureLength: Bool?) -> Bool {
            guard name.year != nil else { return false }
            if yearIsBracketed || hasReleaseWords { return true }
            // A bare year: trust it unless the video is known to be short.
            return isFeatureLength ?? isDotted
        }
    }

    private static func movieCandidate(_ name: String, isDotted: Bool, maximumYear: Int) -> MovieCandidate? {
        var tokens = name.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        // Plex-style "{edition-Director's Cut}".
        var edition: String?
        if let editionRange = name.range(of: "{edition-", options: .caseInsensitive),
           let close = name[editionRange.upperBound...].firstIndex(of: "}") {
            edition = String(name[editionRange.upperBound..<close])
            let stripped = name.replacingCharacters(in: editionRange.lowerBound...close, with: "")
            tokens = normalize(stripped).split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { return nil }
        }

        // The title ends at the first release word ("1080p", "BluRay"…).
        let junkIndex = tokens.indices.dropFirst().first { isJunk(tokens[$0]) } ?? tokens.count

        // The release year is the last plausible year before that, and never
        // the first word ("2012 (2009)" is the movie 2012, from 2009).
        var yearIndex: Int?
        for index in tokens.indices.dropFirst() where index < junkIndex {
            if let year = year(token: tokens[index]), year <= maximumYear {
                yearIndex = index
            }
        }

        let titleEnd = yearIndex ?? junkIndex
        var titleTokens = Array(tokens[..<titleEnd])
        var part: Int?
        if let (number, length) = partSuffix(titleTokens) {
            part = number
            titleTokens.removeLast(length)
        }
        let rest = Array(tokens[titleEnd...])
        if edition == nil {
            edition = editionPhrase(rest)
        }
        if part == nil, let (number, _) = partSuffix(Array(rest.prefix { !isJunk($0) })) {
            part = number
        }
        let title = trimSeparators(titleTokens.joined(separator: " "))
        guard !title.isEmpty else { return nil }

        var result = VideoName(kind: .movie, title: tidy(title))
        result.year = yearIndex.flatMap { year(token: tokens[$0]) }
        result.edition = edition
        result.part = part
        let yearToken = yearIndex.map { tokens[$0] } ?? ""
        return MovieCandidate(
            name: result,
            yearIsBracketed: yearToken.hasPrefix("(") || yearToken.hasPrefix("[") || yearToken.hasSuffix(")") || yearToken.hasSuffix("]"),
            hasReleaseWords: junkIndex < tokens.count,
            isDotted: isDotted
        )
    }

    /// "Doctor Who (2005)" → ("Doctor Who", 2005).
    static func strippingTrailingYear(_ title: String, maximumYear: Int) -> (String, Int)? {
        var tokens = title.split(separator: " ").map(String.init)
        guard tokens.count >= 2, let last = tokens.last, let year = year(token: last), year <= maximumYear else { return nil }
        tokens.removeLast()
        let rest = trimSeparators(tokens.joined(separator: " "))
        return rest.isEmpty ? nil : (rest, year)
    }

    private static func year(token: String) -> Int? {
        let core = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,-"))
        guard core.count == 4, core.allSatisfy(\.isASCII), let value = Int(core), (1900...2099).contains(value) else { return nil }
        return value
    }

    /// "CD1", "CD 2", "Part 1", "pt2", "Disc 1" at the end of a title.
    private static func partSuffix(_ tokens: [String]) -> (Int, Int)? {
        guard let last = tokens.last?.lowercased() else { return nil }
        for prefix in ["cd", "part", "pt", "disc", "disk"] {
            if last.hasPrefix(prefix), let number = Int(last.dropFirst(prefix.count)), (1...20).contains(number) {
                return (number, 1)
            }
            if tokens.count >= 2, tokens[tokens.count - 2].lowercased() == prefix, let number = Int(last), (1...20).contains(number) {
                return (number, 2)
            }
        }
        return nil
    }

    private static func editionPhrase(_ tokens: [String]) -> String? {
        let text = " " + tokens.joined(separator: " ").lowercased() + " "
        let editions: [(String, String)] = [
            (" director's cut ", "Director\u{2019}s Cut"), (" directors cut ", "Director\u{2019}s Cut"),
            (" extended edition ", "Extended Edition"), (" extended cut ", "Extended Cut"),
            (" theatrical cut ", "Theatrical Cut"), (" final cut ", "Final Cut"),
            (" ultimate edition ", "Ultimate Edition"), (" special edition ", "Special Edition"),
            (" unrated ", "Unrated"), (" extended ", "Extended Edition"), (" remastered ", "Remastered"),
            (" imax ", "IMAX"),
        ]
        return editions.first { text.contains($0.0) }?.1
    }

    // MARK: - Home videos

    private static func homeVideo(_ name: String, base: String) -> VideoName {
        VideoName(kind: .homeVideo, title: tidy(name.isEmpty ? base : name))
    }

    /// Phone, camera and screen-recording names: `IMG_1234`, `VID_20240101_123456`,
    /// `MVI_0042`, `GOPR0042`, `DJI_0001`, `PXL_20240101_…`, `2024-01-01 12.34.56`.
    public static func isCameraName(_ base: String) -> Bool {
        let range = NSRange(base.startIndex..., in: base)
        return Patterns.camera.regex.firstMatch(in: base, range: range) != nil
    }

    // MARK: - Cleaning

    /// Release-style separators to spaces: dots (when the name has no
    /// spaces, so "Mr. Robot" keeps its full stop) and underscores.
    public static func normalize(_ name: String) -> String {
        var text = name.replacingOccurrences(of: "_", with: " ")
        if !text.contains(" ") {
            text = text.replacingOccurrences(of: ".", with: " ")
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "[Group] Show - 01" → "Show - 01".
    private static func stripLeadingGroupTag(_ name: String) -> String {
        guard name.hasPrefix("["), let close = name.firstIndex(of: "]") else { return name }
        let rest = name[name.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? name : rest
    }

    /// Everything before the first release token, tidied.
    public static func titleBeforeJunk(_ name: String) -> String {
        let tokens = name.split(separator: " ").map(String.init)
        let end = tokens.firstIndex(where: isJunk) ?? tokens.count
        return tidy(trimSeparators(tokens[..<end].joined(separator: " ")))
    }

    /// A word that belongs to the release, not the title.
    static func isJunk(_ token: String) -> Bool {
        let core = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}"))
        if core.isEmpty { return false }
        if junkWords.contains(core) || matchesJunkPattern(core) { return true }
        // "x264-GROUP", "DTS-HD.MA": a release word with a group or suffix.
        if let hyphen = core.firstIndex(of: "-"), hyphen != core.startIndex {
            let head = String(core[..<hyphen])
            return junkWords.contains(head) || matchesJunkPattern(head)
        }
        return false
    }

    private static func matchesJunkPattern(_ core: String) -> Bool {
        let range = NSRange(core.startIndex..., in: core)
        return Patterns.junk.regex.firstMatch(in: core, range: range) != nil
    }

    private static let junkWords: Set<String> = [
        "4k", "8k", "uhd", "fhd", "sdr", "hdr", "hdr10", "hdr10+", "hdr10plus", "dv", "dovi", "hlg",
        "bluray", "blu-ray", "bdrip", "brrip", "bdremux", "remux", "web", "webrip", "web-dl", "webdl", "web-rip",
        "hdtv", "pdtv", "dvdrip", "dvdscr", "dvd", "dvd5", "dvd9", "hdrip", "hddvd", "uhdbd",
        "amzn", "nf", "dsnp", "hmax", "atvp", "hulu", "itunes", "pcok", "pmtp",
        "x264", "x265", "h264", "h265", "h.264", "h.265", "hevc", "avc", "xvid", "divx", "av1", "vp9",
        "10bit", "8bit", "12bit", "10-bit", "8-bit",
        "aac", "ac3", "eac3", "dd", "ddp", "dts", "dtshd", "dts-hd", "truehd", "atmos", "flac", "mp3", "opus", "pcm", "lpcm",
        "5.1", "7.1", "2.0", "6ch", "8ch",
        "proper", "repack", "rerip", "internal", "limited", "unrated", "extended", "remastered", "criterion",
        "multi", "subbed", "dubbed", "readnfo", "hc", "sample", "uncut", "theatrical",
    ]

    static func trimSeparators(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " -\u{2013}\u{2014}.,_:;([{"))
            .trimmingCharacters(in: .whitespaces)
    }

    static func tidy(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Unbalanced trailing brackets left by cutting at a release token.
        var result = collapsed
        while let last = result.last, "([{".contains(last) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? text : result
    }

    private static func int(_ match: NSTextCheckingResult, _ group: Int, in text: String) -> Int? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }
}

/// Compiled patterns. `NSRegularExpression` is immutable and thread-safe.
private struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String) {
        // The patterns are constants; a typo is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

private enum Patterns {
    static let seasonEpisode = Pattern(#"(?<![a-z0-9])s(\d{1,4})[ ._-]?e(\d{1,4})(?:[ ._-]?-?[ ._-]?e(\d{1,4})|-(\d{1,4})(?![0-9p]))?(?![0-9])"#)
    static let crossEpisode = Pattern(#"(?<![a-z0-9])(\d{1,2})x(\d{2,3})(?![0-9])"#)
    static let wordyEpisode = Pattern(#"season[ ._-]?(\d{1,4})[ ._-]*(?:episode|ep|e)[ ._-]?(\d{1,4})(?![0-9])"#)
    static let dashEpisode = Pattern(#" - (\d{1,4})(?:v\d)?(?= |\[|\(|$)"#)
    static let bareEpisode = Pattern(#"(?<![a-z0-9])(?:episode|ep|e)[ ._-]?(\d{1,3})(?![0-9])"#)
    static let leadingNumber = Pattern(#"^(\d{1,3})(?:[ ._-]|$)"#)
    static let airDate = Pattern(#"(?<![0-9])(\d{4})[ .-](\d{2})[ .-](\d{2})(?![0-9])"#)
    static let camera = Pattern(#"^(?:img|vid|mvi|mov|dsc|dscn|dscf|dji|gopr|gh\d\d|gx\d\d|pxl)[ _-]?\d|^rpreplay|^screen recording|^\d{8}[ _-]\d{6}|^\d{4}-\d{2}-\d{2}[ _]\d{2}[.:-]\d{2}"#)
    static let junk = Pattern(#"^(?:\d{3,4}[pi]|(?:dd|ddp|eac3|ac3|aac|dts|truehd|atmos)\d(?:[ .]?\d)?)$"#)
}
