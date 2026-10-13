import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// A decoded image that can cross actor boundaries (CGImage is immutable).
public struct DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
}

/// Decodes artwork off the main thread with ImageIO, downsampled to the size
/// it's shown at, so grids and Now Playing never stutter. Images decoded from
/// files are kept in a small memory cache, so scrolling back is instant.
public enum ArtworkDecoder {
    public static func decode(_ data: Data, maxPixelSize: Int) async -> DecodedImage? {
        await Task.detached(priority: .userInitiated) {
            decodeSynchronously(data, maxPixelSize: maxPixelSize)
        }.value
    }

    /// Decodes a file, or downloads and decodes a web image (cast photos).
    public static func decode(contentsOf url: URL, maxPixelSize: Int) async -> DecodedImage? {
        if let cached = cachedImage(contentsOf: url, maxPixelSize: maxPixelSize) {
            return cached
        }
        let decoded: DecodedImage?
        if url.isFileURL {
            decoded = await Task.detached(priority: .userInitiated) {
                decodeFileSynchronously(url, maxPixelSize: maxPixelSize)
            }.value
        } else {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            decoded = await decode(data, maxPixelSize: maxPixelSize)
        }
        if let decoded {
            ArtworkImageCache.shared.insert(decoded, for: cacheKey(url, maxPixelSize))
        }
        return decoded
    }

    /// An already-decoded image, if one is cached.
    public static func cachedImage(contentsOf url: URL, maxPixelSize: Int) -> DecodedImage? {
        ArtworkImageCache.shared.image(for: cacheKey(url, maxPixelSize))
    }

    static func decodeSynchronously(_ data: Data, maxPixelSize: Int) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source, maxPixelSize: maxPixelSize)
    }

    static func decodeFileSynchronously(_ url: URL, maxPixelSize: Int) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnail(_ source: CGImageSource, maxPixelSize: Int) -> DecodedImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(cgImage: image)
    }

    private static func cacheKey(_ url: URL, _ maxPixelSize: Int) -> String {
        "\(url.path(percentEncoded: false))#\(maxPixelSize)"
    }
}

/// Decoded artwork, bounded by total pixel count (NSCache is thread-safe).
final class ArtworkImageCache: @unchecked Sendable {
    static let shared = ArtworkImageCache()

    private final class Entry {
        let image: DecodedImage
        init(_ image: DecodedImage) { self.image = image }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 120 * 1_000_000 // about 120 MB of pixels
        return cache
    }()

    func image(for key: String) -> DecodedImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func insert(_ image: DecodedImage, for key: String) {
        let cost = image.cgImage.bytesPerRow * image.cgImage.height
        cache.setObject(Entry(image), forKey: key as NSString, cost: cost)
    }
}

/// Rounded artwork with a placeholder, in one of the three artwork shapes.
/// "Artwork is the interface": callers pass whatever image they have and
/// never fall back to showing a filename.
public struct ArtworkView: View {
    private enum Source: Hashable {
        case none
        case data(Data)
        case file(URL)
    }

    private let source: Source
    private let shape: ArtworkShape
    private let maxPixelSize: Int
    private let placeholderSymbol: String?
    @State private var image: DecodedImage?
    @State private var shownSource: Source?

    /// - Parameters:
    ///   - data: Encoded image data (JPEG, PNG, HEIC…), or `nil` for the placeholder.
    ///   - maxPixelSize: Longest edge to decode to. Use the displayed size × screen scale.
    public init(data: Data?, shape: ArtworkShape = .square, maxPixelSize: Int = 600, placeholderSymbol: String? = nil) {
        self.source = data.map(Source.data) ?? .none
        self.shape = shape
        self.maxPixelSize = maxPixelSize
        self.placeholderSymbol = placeholderSymbol
    }

    /// Artwork from an image file, such as the library's artwork cache.
    public init(url: URL?, shape: ArtworkShape = .square, maxPixelSize: Int = 600, placeholderSymbol: String? = nil) {
        self.source = url.map(Source.file) ?? .none
        self.shape = shape
        self.maxPixelSize = maxPixelSize
        self.placeholderSymbol = placeholderSymbol
    }

    public var body: some View {
        let displayed = shownSource == source ? image : cachedImage
        RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if let displayed {
                    Image(decorative: displayed.cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous))
            .aspectRatio(shape.aspectRatio, contentMode: .fit)
            .task(id: source) {
                await load()
            }
    }

    /// Cached file artwork shows immediately, without a placeholder flash.
    private var cachedImage: DecodedImage? {
        guard case .file(let url) = source else { return nil }
        return ArtworkDecoder.cachedImage(contentsOf: url, maxPixelSize: maxPixelSize)
    }

    private func load() async {
        let requested = source
        let decoded: DecodedImage?
        switch requested {
        case .none:
            decoded = nil
        case .data(let data):
            decoded = await ArtworkDecoder.decode(data, maxPixelSize: maxPixelSize)
        case .file(let url):
            decoded = await ArtworkDecoder.decode(contentsOf: url, maxPixelSize: maxPixelSize)
        }
        guard !Task.isCancelled else { return }
        if image == nil, decoded != nil, cachedImage == nil {
            withAnimation(.easeOut(duration: 0.2)) {
                image = decoded
            }
        } else {
            image = decoded
        }
        shownSource = requested
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: placeholderSymbol ?? shape.placeholderSymbol)
                .font(.system(size: 64, weight: .regular))
                .minimumScaleFactor(0.1)
                .padding(18)
                .foregroundStyle(.secondary)
        }
    }
}

/// Samples artwork into a 3×3 grid of colours for mesh-gradient backgrounds.
public enum DominantColors {
    public static func grid(from data: Data) async -> [Color] {
        await Task.detached(priority: .utility) {
            sampleGrid(from: data)
        }.value
    }

    static func sampleGrid(from data: Data) -> [Color] {
        guard let decoded = ArtworkDecoder.decodeSynchronously(data, maxPixelSize: 48) else { return [] }
        let side = 3
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(decoded.cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return [] }
        return stride(from: 0, to: pixels.count, by: 4).map { index in
            // Darken a little so white text stays legible on top.
            Color(
                red: Double(pixels[index]) / 255 * 0.78,
                green: Double(pixels[index + 1]) / 255 * 0.78,
                blue: Double(pixels[index + 2]) / 255 * 0.78
            )
        }
    }
}

/// Apple Music-style background: a slowly moving mesh gradient sampled from
/// the artwork, darkened for legibility. Static when Reduce Motion is on.
public struct ArtworkBackground: View {
    private let artworkData: Data?
    @State private var colors: [Color] = Palette.fallbackMesh
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(artworkData: Data?) {
        self.artworkData = artworkData
    }

    public var body: some View {
        ZStack {
            Palette.playerBackground
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
            Color.black.opacity(0.22)
        }
        .ignoresSafeArea()
        .task(id: artworkData) {
            var sampled: [Color] = []
            if let artworkData {
                sampled = await DominantColors.grid(from: artworkData)
            }
            withAnimation(.easeInOut(duration: 0.8)) {
                colors = sampled.count == 9 ? sampled : Palette.fallbackMesh
            }
        }
    }

    private func mesh(at time: TimeInterval) -> some View {
        MeshGradient(width: 3, height: 3, points: Self.points(at: time), colors: colors)
    }

    /// Corner and edge points stay put; the inner points drift slowly.
    static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time.truncatingRemainder(dividingBy: 3_600))
        let dx = 0.12 * sin(t * 0.21)
        let dy = 0.10 * cos(t * 0.17)
        let edge = 0.06 * sin(t * 0.13)
        return [
            [0, 0], [0.5 + edge, 0], [1, 0],
            [0, 0.5 - edge], [0.5 + dx, 0.5 + dy], [1, 0.5 + edge],
            [0, 1], [0.5 - edge, 1], [1, 1],
        ]
    }
}

/// Artwork that fills whatever frame it's given (cropping as needed), with
/// no shape of its own: backdrops and full-bleed backgrounds.
public struct FilledArtwork: View {
    private let url: URL?
    private let maxPixelSize: Int
    @State private var image: DecodedImage?
    @State private var shownURL: URL?

    public init(url: URL?, maxPixelSize: Int = 1_600) {
        self.url = url
        self.maxPixelSize = maxPixelSize
    }

    public var body: some View {
        let displayed = shownURL == url ? image : url.flatMap { ArtworkDecoder.cachedImage(contentsOf: $0, maxPixelSize: maxPixelSize) }
        Color.clear
            .overlay {
                if let displayed {
                    Image(decorative: displayed.cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else {
                    image = nil
                    shownURL = nil
                    return
                }
                let decoded = await ArtworkDecoder.decode(contentsOf: url, maxPixelSize: maxPixelSize)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    image = decoded
                }
                shownURL = url
            }
    }
}
