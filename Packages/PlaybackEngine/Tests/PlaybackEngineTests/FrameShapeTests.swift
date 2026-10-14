#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// Library frames keep the picture's shape. VLC's thumbnailer scales a frame
/// to exactly the box it's given, so before the box followed the video's own
/// shape, wide films came out stretched tall (and the Continue Watching row
/// showed them squashed).
extension RealMediaTests {
    @MainActor
    @Suite("Frames keep their shape", .serialized)
    struct FrameShapeTests {
        struct Shape: Sendable, CustomTestStringConvertible {
            let name: String
            let width: Int
            let height: Int
            /// Horizontal ÷ vertical pixel spacing, for pixels that aren't square.
            let pixelAspect: (Int, Int)?

            var displayAspect: Double {
                let pixels = pixelAspect.map { Double($0.0) / Double($0.1) } ?? 1
                return Double(width) * pixels / Double(height)
            }

            var testDescription: String { name }
        }

        nonisolated static let shapes = [
            Shape(name: "scope 2.40:1", width: 384, height: 160, pixelAspect: nil),
            Shape(name: "4:3", width: 240, height: 180, pixelAspect: nil),
            Shape(name: "anamorphic 16:9", width: 240, height: 180, pixelAspect: (4, 3)),
        ]

        @Test(arguments: shapes)
        func vlcFramesKeepTheirShape(_ shape: Shape) async throws {
            let movie = try await TestMovie.shaped(width: shape.width, height: shape.height, pixelAspect: shape.pixelAspect)
            defer { try? FileManager.default.removeItem(at: movie) }
            if shape.pixelAspect != nil {
                let stored = try await storesPixelAspect(movie)
                guard stored else {
                    Trace.write("shape: \(shape.name): the writer didn't store the pixel shape; skipped")
                    return
                }
            }
            let data = await FrameGrabber.shared.vlcFrameJPEG(from: movie, at: 1, maxPixelSize: 480, precise: false)
            let image = try #require(Self.image(from: data), "\(shape.name): VLC made no frame")
            let aspect = Double(image.width) / Double(image.height)
            Trace.write("shape: \(shape.name): VLC frame \(image.width)×\(image.height), aspect \(String(format: "%.3f", aspect)), expected \(String(format: "%.3f", shape.displayAspect))")
            #expect(abs(aspect - shape.displayAspect) / shape.displayAspect < 0.03, "\(shape.name): \(image.width)×\(image.height)")
            #expect(max(image.width, image.height) <= 480)
        }

        @Test(arguments: shapes)
        func avFoundationFramesKeepTheirShape(_ shape: Shape) async throws {
            let movie = try await TestMovie.shaped(width: shape.width, height: shape.height, pixelAspect: shape.pixelAspect)
            defer { try? FileManager.default.removeItem(at: movie) }
            if shape.pixelAspect != nil {
                let stored = try await storesPixelAspect(movie)
                guard stored else {
                    Trace.write("shape: \(shape.name): the writer didn't store the pixel shape; skipped")
                    return
                }
            }
            let data = await FrameGrabber.shared.frameJPEG(from: movie, at: 1, maxPixelSize: 480, precise: false)
            let image = try #require(Self.image(from: data), "\(shape.name): AVFoundation made no frame")
            let aspect = Double(image.width) / Double(image.height)
            Trace.write("shape: \(shape.name): AVFoundation frame \(image.width)×\(image.height), aspect \(String(format: "%.3f", aspect))")
            #expect(abs(aspect - shape.displayAspect) / shape.displayAspect < 0.03, "\(shape.name): \(image.width)×\(image.height)")
        }

        /// The box VLC is given has the picture's shape, and its long side is the size asked for.
        @Test func boxesFollowTheShape() {
            #expect(ThumbnailBox.fitting(aspectRatio: 2.4, maxPixelSize: 480) == ThumbnailBox(width: 480, height: 200))
            #expect(ThumbnailBox.fitting(aspectRatio: 0.5625, maxPixelSize: 480) == ThumbnailBox(width: 270, height: 480))
            #expect(ThumbnailBox.fitting(aspectRatio: 1, maxPixelSize: 300) == ThumbnailBox(width: 300, height: 300))
            // Unknown: a 16:9 box, cropped rather than stretched.
            #expect(ThumbnailBox.fitting(aspectRatio: .nan, maxPixelSize: 480) == ThumbnailBox(width: 480, height: 270, crops: true))
            #expect(ThumbnailBox.fitting(aspectRatio: 0, maxPixelSize: 480).crops)
        }

        private func storesPixelAspect(_ movie: URL) async throws -> Bool {
            let asset = AVURLAsset(url: movie)
            guard let track = try await asset.loadTracks(withMediaType: .video).first,
                  let format = try await track.load(.formatDescriptions).first else { return false }
            let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any]
            return extensions?[kCMFormatDescriptionExtension_PixelAspectRatio as String] != nil
        }

        private static func image(from data: Data?) -> CGImage? {
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }
}
#endif
