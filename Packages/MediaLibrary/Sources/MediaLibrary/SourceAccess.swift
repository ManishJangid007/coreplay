import CryptoKit
import Foundation
import MetadataProviders
import PlaybackCore

/// Security-scoped bookmarks and the fixed folders sources point at.
public enum SourceAccess {
    /// A bookmark for a folder or file the user picked. Call it while the
    /// URL's security scope is active (straight after the picker returns).
    public static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// Resolves a bookmark. `isStale` means it should be recreated.
    public static func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(macOS)
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        return (url, isStale)
    }

    /// The app's Documents folder: "On My iPhone ▸ Coreplay" in Files.
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    #if os(macOS)
    /// ~/Music. Inside the sandbox this path leads to the real folder thanks
    /// to the Music read-only entitlement.
    public static var musicDirectory: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
    }

    public static var moviesDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
    }
    #endif
}

/// A fingerprint of a file's size and its first and last 64 KB. Cheap to
/// compute, stable across renames and moves, and different for different
/// encodes of the same song.
enum ContentKey {
    static func compute(_ source: ByteSource) throws -> String {
        let chunk = 64 * 1024
        var hasher = SHA256()
        withUnsafeBytes(of: source.size.bigEndian) { hasher.update(bufferPointer: $0) }
        hasher.update(data: try source.read(at: 0, count: chunk))
        if source.size > Int64(chunk) {
            hasher.update(data: try source.read(at: max(Int64(chunk), source.size - Int64(chunk)), count: chunk))
        }
        return hasher.finalize().prefix(16).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }
}

/// Folder artwork (`cover.jpg`, `folder.jpg`…), looked up once per folder per scan.
final class FolderArtworkCache: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: String?] = [:]

    private static let preferredNames = ["cover", "folder", "front", "album", "albumart", "artwork"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "gif", "bmp"]

    func key(forDirectory directory: URL, store: ArtworkStore) -> String? {
        let path = directory.path(percentEncoded: false)
        lock.lock()
        if let cached = keys[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var result: String?
        if let imageURL = Self.bestImage(in: directory), let data = try? Data(contentsOf: imageURL) {
            result = store.store(data)
        }
        lock.lock()
        keys[path] = result
        lock.unlock()
        return result
    }

    static func bestImage(in directory: URL) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return nil }
        let images = names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            let ext = (name.split(separator: ".").last.map(String.init) ?? "").lowercased()
            return imageExtensions.contains(ext)
        }
        guard !images.isEmpty else { return nil }
        func base(_ name: String) -> String {
            PathMetadata.removingExtension(name).lowercased()
        }
        for preferred in preferredNames {
            if let match = images.first(where: { base($0) == preferred }) {
                return directory.appending(path: match)
            }
        }
        // Windows Media Player's "AlbumArt_{GUID}_Large.jpg".
        if let match = images.first(where: { base($0).hasPrefix("albumart_") && base($0).hasSuffix("_large") }) {
            return directory.appending(path: match)
        }
        if let match = images.first(where: { base($0).contains("cover") || base($0).contains("front") }) {
            return directory.appending(path: match)
        }
        return images.count == 1 ? directory.appending(path: images[0]) : nil
    }
}
