#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// The frame a scrub preview shows has to be the frame playback lands on.
/// The test movie's bar moves 4 pixels a frame, so a frame's time can be read
/// back from where the bar is.
@MainActor
@Suite("Scrub preview accuracy", .serialized)
struct ScrubPreviewAccuracyTests {
    /// Times in the middle of frames, away from the bar wrapping round.
    static let times: [TimeInterval] = [2.05, 5.52, 9.31]

    @Test func avFoundationFramesAreExact() async throws {
        let movie = try await TestMovie.url(seconds: 12)
        for time in Self.times {
            let data = await FrameGrabber.shared.frameJPEG(from: movie, at: time, maxPixelSize: 480, precise: true)
            try expectFrame(data, at: time, source: "AVFoundation")
        }
    }

    @Test func vlcFramesAreExact() async throws {
        let movie = try await TestMovie.url(seconds: 12)
        for time in Self.times {
            let data = await FrameGrabber.shared.vlcFrameJPEG(from: movie, at: time, maxPixelSize: 480, precise: true)
            try expectFrame(data, at: time, source: "VLC")
        }
    }

    /// The bubble asks for the frame where the pointer rests and gets the
    /// exact one shortly after.
    @Test func previewsMakeTheExactFrameWhereThePointerRests() async throws {
        let movie = try await TestMovie.url(seconds: 12)
        let previews = ScrubPreviews()
        previews.prepare(for: PlaybackItem(url: movie, kind: .video, title: "Smoke"), duration: 12, hasVideo: true)
        let time = 5.52
        #expect(previews.exactImage(at: time) == nil, "nothing is ready straight away")
        var image: CGImage?
        let deadline = Date().addingTimeInterval(8)
        while image == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            image = previews.exactImage(at: time)
        }
        let frame = try #require(image, "no exact frame after 8 seconds")
        try expectBar(in: frame, at: time, source: "ScrubPreviews")
        previews.reset()
    }

    // MARK: Reading the bar

    private func expectFrame(_ data: Data?, at time: TimeInterval, source: String) throws {
        let data = try #require(data, "\(source) made no frame at \(time) s")
        let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        try expectBar(in: image, at: time, source: source)
    }

    /// The bar's centre is where the frame at `time` has it, give or take one
    /// frame (engines differ on which side of a frame boundary they land).
    private func expectBar(in image: CGImage, at time: TimeInterval, source: String) throws {
        let measured = try #require(barCentre(in: image), "\(source): no bar found at \(time) s")
        let frame = Int(time * Double(TestMovie.framesPerSecond))
        let expected = Double(TestMovie.barStart(frame: frame)) + Double(TestMovie.barWidth) / 2
        // In the movie's own pixels (the image may be scaled).
        let scaled = measured * Double(TestMovie.width) / Double(image.width)
        let framesOff = abs(scaled - expected) / 4
        Trace.write("accuracy: \(source) at \(time) s is \(String(format: "%.1f", framesOff)) frames off")
        #expect(framesOff <= 1.5, "\(source) at \(time) s shows the bar at \(Int(scaled)) px, expected \(Int(expected)) px (\(String(format: "%.1f", framesOff)) frames off)")
    }

    /// The middle of the bright columns along the middle row.
    private func barCentre(in image: CGImage) -> Double? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let row = height / 2
        var bright: [Int] = []
        for x in 0..<width {
            let offset = (row * width + x) * 4
            let brightness = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            if brightness > 180 {
                bright.append(x)
            }
        }
        guard let first = bright.first, let last = bright.last else { return nil }
        return Double(first + last) / 2
    }
}
#endif
