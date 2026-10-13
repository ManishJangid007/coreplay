import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Album artwork on disk, deduplicated by content and stored in the sizes the
/// interface needs, so grids never decode full-size covers.
///
/// Files are named `<key>-<variant>.jpg`; the key is a hash of the original
/// image, so the same cover embedded in twelve tracks is stored once.
public struct ArtworkStore: Sendable {
    public enum Variant: String, Sendable, CaseIterable {
        /// Rows and the mini player.
        case thumbnail
        /// Album grids.
        case grid
        /// Album pages and Now Playing.
        case large

        var maxPixelSize: Int {
            switch self {
            case .thumbnail: 160
            case .grid: 600
            case .large: 1400
            }
        }
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Application Support/Artwork.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "Artwork", directoryHint: .isDirectory)
    }

    public func url(for key: String, variant: Variant) -> URL {
        directory.appending(path: "\(key)-\(variant.rawValue).jpg", directoryHint: .notDirectory)
    }

    public func contains(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key, variant: .grid).path(percentEncoded: false))
    }

    /// Stores an image in every variant and returns its key, or `nil` when the
    /// data isn't a decodable image. Safe to call from any thread.
    public func store(_ data: Data) -> String? {
        let key = Self.key(for: data)
        if contains(key) {
            return key
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        // Largest first: if decoding fails, nothing is half-written.
        for variant in Variant.allCases.reversed() {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: variant.maxPixelSize,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let encoded = Self.jpeg(image) else { return nil }
            do {
                try encoded.write(to: url(for: key, variant: variant), options: .atomic)
            } catch {
                return nil
            }
        }
        return key
    }

    /// Removes artwork no library item uses any more.
    public func removeAll(except keysInUse: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names {
            guard let dash = name.lastIndex(of: "-") else { continue }
            let key = String(name[..<dash])
            if !keysInUse.contains(key) {
                try? FileManager.default.removeItem(at: directory.appending(path: name))
            }
        }
    }

    static func key(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
