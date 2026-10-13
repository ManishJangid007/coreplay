import Foundation

/// What a file's name and folders say about it, for files with missing tags.
///
/// Understands the common layouts:
/// - `Artist/Album/01 Title.mp3` and `Artist/Album (2004)/01 - Title.flac`
/// - `Artist - Album/03. Title.m4a`
/// - `Album/CD2/04 Title.mp3` (disc folders)
/// - `1-04 Title.m4a` (disc and track in the file name, as iTunes names them)
/// - `Artist - Title.mp3` in a flat folder
public struct PathMetadata: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?

    /// - Parameter relativePath: The path below the library source's root,
    ///   e.g. `"Radiohead/OK Computer/01 Airbag.flac"`. Folders above the
    ///   source root are never used.
    public init(relativePath: String) {
        var components = relativePath.split(separator: "/").map(String.init)
        let fileName = components.popLast() ?? relativePath
        var base = Self.removingExtension(fileName)

        // Disc and track numbers at the start of the file name.
        var trackNumber: Int?
        var discNumber: Int?
        if let match = Self.leadingDiscAndTrack(base) {
            (discNumber, trackNumber, base) = match
        } else if let match = Self.leadingTrack(base) {
            (trackNumber, base) = match
        }

        // Folders: [.., artist, album, (disc)].
        var folders = components
        if let last = folders.last, let disc = Self.discFolderNumber(last) {
            discNumber = discNumber ?? disc
            folders.removeLast()
        }
        var album: String?
        var artist: String?
        var year: Int?
        if let albumFolder = folders.last {
            var name = albumFolder
            if let (stripped, foundYear) = Self.strippingYear(name) {
                name = stripped
                year = foundYear
            }
            if let (folderArtist, folderAlbum) = Self.splitArtistAndTitle(name) {
                artist = folderArtist
                name = folderAlbum
                if let (stripped, foundYear) = Self.strippingYear(name) {
                    name = stripped
                    year = year ?? foundYear
                }
            }
            album = name
            if artist == nil, folders.count >= 2 {
                artist = folders[folders.count - 2]
            }
        }

        // "Artist - Title" in the file name itself.
        var title = base
        if let (fileArtist, fileTitle) = Self.splitArtistAndTitle(base) {
            if let artist, fileArtist.caseInsensitiveCompare(artist) == .orderedSame {
                title = fileTitle
            } else if artist == nil {
                artist = fileArtist
                title = fileTitle
            }
        }

        self.title = Self.tidy(title)
        self.artist = artist.map(Self.tidy)
        self.album = album.map(Self.tidy)
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
    }

    // MARK: - Patterns

    /// "01 Song.flac" → "01 Song"; names without an extension are unchanged.
    public static func removingExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        let ext = fileName[fileName.index(after: dot)...]
        guard !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return fileName }
        return String(fileName[..<dot])
    }

    /// "1-04 Title", "2-11. Title" → (disc, track, title).
    static func leadingDiscAndTrack(_ name: String) -> (Int, Int, String)? {
        let characters = Array(name)
        var index = 0
        var disc = ""
        while index < characters.count, characters[index].isASCII, characters[index].isNumber, disc.count < 2 {
            disc.append(characters[index])
            index += 1
        }
        guard !disc.isEmpty, index < characters.count, characters[index] == "-" else { return nil }
        index += 1
        var track = ""
        while index < characters.count, characters[index].isASCII, characters[index].isNumber, track.count < 3 {
            track.append(characters[index])
            index += 1
        }
        guard track.count >= 2, let discValue = Int(disc), let trackValue = Int(track), discValue > 0, trackValue > 0 else { return nil }
        let rest = dropSeparators(String(characters[index...]))
        guard !rest.isEmpty else { return nil }
        return (discValue, trackValue, rest)
    }

    /// "01 Title", "01. Title", "01 - Title", "1) Title" → (track, title).
    static func leadingTrack(_ name: String) -> (Int, String)? {
        let characters = Array(name)
        var digits = ""
        var index = 0
        while index < characters.count, characters[index].isASCII, characters[index].isNumber, digits.count < 3 {
            digits.append(characters[index])
            index += 1
        }
        guard !digits.isEmpty, index < characters.count, let number = Int(digits), number > 0 else { return nil }
        let separator = characters[index]
        let hasPunctuation = ".-_)".contains(separator)
        // A lone digit needs punctuation ("1. Title"), so titles such as
        // "7 Seconds" survive; two or three digits ("01 Title") don't.
        guard hasPunctuation || (separator == " " && digits.count >= 2) else { return nil }
        let rest = dropSeparators(String(characters[index...]))
        guard !rest.isEmpty else { return nil }
        return (number, rest)
    }

    /// "CD1", "CD 2", "Disc 1", "Disk2" → the disc number.
    static func discFolderNumber(_ name: String) -> Int? {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["cd", "disc", "disk"] where lowered.hasPrefix(prefix) {
            let rest = lowered.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let number = Int(rest), number > 0, number < 100 {
                return number
            }
        }
        return nil
    }

    /// "OK Computer (1997)", "OK Computer [1997]", "1997 - OK Computer".
    static func strippingYear(_ name: String) -> (String, Int)? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for (open, close) in [("(", ")"), ("[", "]")] where trimmed.hasSuffix(close) {
            if let openIndex = trimmed.lastIndex(of: Character(open)) {
                let inner = trimmed[trimmed.index(after: openIndex)..<trimmed.index(before: trimmed.endIndex)]
                if inner.count == 4, let year = Int(inner), (1900...2100).contains(year) {
                    let rest = trimmed[..<openIndex].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { return (rest, year) }
                }
            }
        }
        // A leading year needs a hyphen or full stop after it, so titles such
        // as "2001 A Space Odyssey" stay intact.
        let prefix = trimmed.prefix(4)
        if prefix.count == 4, let year = Int(prefix), (1900...2100).contains(year) {
            let after = trimmed.dropFirst(4).drop(while: { $0 == " " })
            if let mark = after.first, mark == "-" || mark == "." || mark == "\u{2013}" {
                let rest = dropSeparators(String(after))
                if !rest.isEmpty { return (rest, year) }
            }
        }
        return nil
    }

    /// "Artist - Title" (a spaced hyphen or en dash) → (artist, title).
    static func splitArtistAndTitle(_ name: String) -> (String, String)? {
        for separator in [" - ", " \u{2013} ", " \u{2014} "] {
            guard let range = name.range(of: separator) else { continue }
            let left = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !left.isEmpty, !right.isEmpty {
                return (left, right)
            }
        }
        return nil
    }

    private static func dropSeparators(_ text: String) -> String {
        String(text.drop(while: { $0 == " " || $0 == "." || $0 == "-" || $0 == "_" || $0 == ")" || $0 == "\u{2013}" }))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Underscores to spaces, collapsed whitespace.
    static func tidy(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "_", with: " ")
        let words = spaced.split(whereSeparator: \.isWhitespace)
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? text : joined
    }
}
