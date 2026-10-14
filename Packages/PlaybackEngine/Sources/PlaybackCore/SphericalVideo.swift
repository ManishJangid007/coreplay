import Foundation

/// Finds 360° metadata in MP4 and QuickTime files.
///
/// AVFoundation would play such a file as a flat, distorted picture, so the
/// router sends it to VLC, which projects it and lets you look around. MKV and
/// WebM go to VLC anyway. Three kinds of marking are recognised, all inside
/// the `moov` box:
/// - Google's Spherical Video V2: an `sv3d` box (its `proj` holds `equi` or `cbmp`);
/// - Spherical Video V1: an XML `uuid` box saying `<GSpherical:Spherical>true`;
/// - Apple's projected media: a `prji` box whose projection kind is `equi`.
public enum SphericalVideoDetector {
    /// Reads at most this much of the movie box.
    static let movieBoxLimit = 32 << 20
    /// Gives up after this many top-level boxes.
    static let boxLimit = 64

    /// Spherical Video V1's box: `uuid` ffcc8263-f855-4a93-8814-587a02521fdd.
    static let sphericalV1UUID: [UInt8] = [
        0xFF, 0xCC, 0x82, 0x63, 0xF8, 0x55, 0x4A, 0x93, 0x88, 0x14, 0x58, 0x7A, 0x02, 0x52, 0x1F, 0xDD,
    ]

    /// The projection a file declares; `.flat` when it declares none or can't be read.
    public static func projection(ofFileAt url: URL) -> VideoProjection {
        guard url.isFileURL, let movie = movieBox(at: url) else { return .flat }
        return projection(inMovieBox: movie)
    }

    /// The projection declared somewhere inside a `moov` box's contents.
    static func projection(inMovieBox data: Data) -> VideoProjection {
        if data.range(of: Data("sv3d".utf8)) != nil {
            return data.range(of: Data("cbmp".utf8)) != nil ? .cubeMap : .equirectangular
        }
        var searchStart = data.startIndex
        while let prji = data.range(of: Data("prji".utf8), in: searchStart..<data.endIndex) {
            // A full box: version and flags, then the projection kind.
            let kindStart = prji.upperBound + 4
            if kindStart + 4 <= data.endIndex, data[kindStart..<kindStart + 4] == Data("equi".utf8) {
                return .equirectangular
            }
            searchStart = prji.upperBound
        }
        if data.range(of: Data(sphericalV1UUID)) != nil, data.range(of: Data("Spherical>true".utf8)) != nil {
            return .equirectangular
        }
        return .flat
    }

    /// The contents of the file's top-level `moov` box, wherever it is.
    static func movieBox(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd() else { return nil }
        var offset: UInt64 = 0
        for _ in 0..<boxLimit {
            guard offset + 8 <= fileSize else { return nil }
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16), header.count >= 8 else { return nil }
            var size = UInt64(bigEndian32(header, at: 0))
            let type = header.subdata(in: 4..<8)
            var headerSize: UInt64 = 8
            if size == 1 {
                // A 64-bit size follows the type.
                guard header.count >= 16 else { return nil }
                size = bigEndian64(header, at: 8)
                headerSize = 16
            } else if size == 0 {
                // The box runs to the end of the file.
                size = fileSize - offset
            }
            guard size >= headerSize else { return nil }
            if type == Data("moov".utf8) {
                let length = min(size - headerSize, UInt64(movieBoxLimit), fileSize - offset - headerSize)
                guard (try? handle.seek(toOffset: offset + headerSize)) != nil else { return nil }
                return try? handle.read(upToCount: Int(length))
            }
            offset += size
        }
        return nil
    }

    private static func bigEndian32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return data[start..<start + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func bigEndian64(_ data: Data, at offset: Int) -> UInt64 {
        let start = data.startIndex + offset
        return data[start..<start + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
