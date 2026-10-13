import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// A decoded image that can cross actor boundaries (CGImage is immutable).
public struct DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
}

/// Decodes artwork off the main thread with ImageIO, downsampled to the size
/// it's shown at, so grids and Now Playing never stutter.
public enum ArtworkDecoder {
    public static func decode(_ data: Data, maxPixelSize: Int) async -> DecodedImage? {
        await Task.detached(priority: .userInitiated) {
            decodeSynchronously(data, maxPixelSize: maxPixelSize)
        }.value
    }

    static func decodeSynchronously(_ data: Data, maxPixelSize: Int) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(cgImage: image)
    }
}

/// Rounded artwork with a placeholder, in one of the three artwork shapes.
/// "Artwork is the interface": callers pass whatever image data they have and
/// never fall back to showing a filename.
public struct ArtworkView: View {
    private let data: Data?
    private let shape: ArtworkShape
    private let maxPixelSize: Int
    private let placeholderSymbol: String?
    @State private var image: DecodedImage?

    /// - Parameters:
    ///   - data: Encoded image data (JPEG, PNG, HEIC…), or `nil` for the placeholder.
    ///   - maxPixelSize: Longest edge to decode to. Use the displayed size × screen scale.
    public init(data: Data?, shape: ArtworkShape = .square, maxPixelSize: Int = 600, placeholderSymbol: String? = nil) {
        self.data = data
        self.shape = shape
        self.maxPixelSize = maxPixelSize
        self.placeholderSymbol = placeholderSymbol
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous))
            .aspectRatio(shape.aspectRatio, contentMode: .fit)
            .task(id: data) {
                guard let data else {
                    image = nil
                    return
                }
                let decoded = await ArtworkDecoder.decode(data, maxPixelSize: maxPixelSize)
                withAnimation(.easeOut(duration: 0.2)) {
                    image = decoded
                }
            }
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
