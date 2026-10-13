import Foundation

/// Keys for grouping and sorting names the way Apple Music does.
public enum NameNormalizer {
    /// Two names are the same artist, album or genre when their keys match:
    /// case, accents, width and extra spaces are ignored ("Beyoncé" and
    /// "beyonce ", "AC/DC" and "ac/dc").
    public static func groupKey(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Sorts "The Beatles" under B and "A Tribe Called Quest" under T, like
    /// Apple Music. Names that start with digits or symbols sort first.
    public static func sortKey(_ name: String) -> String {
        var key = groupKey(name)
        for article in ["the ", "a ", "an "] where key.hasPrefix(article) && key.count > article.count {
            key.removeFirst(article.count)
            break
        }
        return key
    }

    /// The letter a name is filed under in an index: "A"–"Z", or "#".
    public static func indexLetter(forSortKey key: String) -> String {
        guard let first = key.unicodeScalars.first, first.isASCII,
              CharacterSet.lowercaseLetters.contains(first) else { return "#" }
        return String(first).uppercased()
    }
}
