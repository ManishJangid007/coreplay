import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PlaybackCore
import UniformTypeIdentifiers
internal import VLCKit

/// Still frames from videos, for library artwork and the frame picker:
/// AVFoundation for the formats Apple opens, VLC's thumbnailer for the rest.
///
/// Frames come back as JPEG data, so nothing but bytes crosses threads.
public final class FrameGrabber: VideoFrameSource, @unchecked Sendable {
    public static let shared = FrameGrabber()

    private let lock = NSLock()
    private var vlcLibrary: VLCLibrary?
    /// Display aspect ratios (width ÷ height) of files VLC has read, so a
    /// video's many scrub frames parse it once.
    private var aspectRatios: [URL: Double] = [:]

    public init() {}

    public func frameJPEG(from url: URL, at time: TimeInterval?, maxPixelSize: Int, precise: Bool) async -> Data? {
        let size = max(64, maxPixelSize)
        if ContainerFormat(url: url).support == .native,
           let data = await Self.avFrame(url, at: time, maxPixelSize: size, precise: precise) {
            return data
        }
        return await vlcFrame(url, at: time, maxPixelSize: size, precise: precise)
    }

    /// VLC's frame, even for files AVFoundation could open (for tests).
    func vlcFrameJPEG(from url: URL, at time: TimeInterval?, maxPixelSize: Int, precise: Bool) async -> Data? {
        await vlcFrame(url, at: time, maxPixelSize: max(64, maxPixelSize), precise: precise)
    }

    // MARK: - AVFoundation

    private static func avFrame(_ url: URL, at time: TimeInterval?, maxPixelSize: Int, precise: Bool) async -> Data? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: precise])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 3, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var seconds = time
        if seconds == nil, let duration = try? await asset.load(.duration), duration.isNumeric {
            seconds = duration.seconds * 0.1
        }
        do {
            let (image, _) = try await generator.image(at: CMTime(seconds: max(seconds ?? 0, 0), preferredTimescale: 600))
            return jpeg(image)
        } catch {
            return nil
        }
    }

    // MARK: - VLC

    private func vlcFrame(_ url: URL, at time: TimeInterval?, maxPixelSize: Int, precise: Bool) async -> Data? {
        guard let media = VLCMedia(url: url) else { return nil }
        // VLC scales a thumbnail to exactly the box it's given, so the box
        // must have the picture's own shape (a square box stretched wide
        // films tall). Without the shape, a 16:9 box cropped to fit at least
        // never distorts.
        let box: ThumbnailBox
        if let aspect = await displayAspectRatio(of: url) {
            box = ThumbnailBox.fitting(aspectRatio: aspect, maxPixelSize: maxPixelSize)
        } else {
            box = ThumbnailBox(width: maxPixelSize, height: max(16, maxPixelSize * 9 / 16), crops: true)
        }
        let request = ThumbnailRequest()
        return await request.run(media: media, library: library(), time: time, box: box, precise: precise)
    }

    /// The video's shape as shown (pixel aspect ratio included), read by VLC.
    private func displayAspectRatio(of url: URL) async -> Double? {
        if let known = lock.withLock({ aspectRatios[url] }) {
            return known
        }
        guard let media = VLCMedia(url: url) else { return nil }
        let aspect = await AspectProbe().run(media: media, library: library())
        if let aspect {
            lock.withLock {
                if aspectRatios.count > 200 { aspectRatios.removeAll() }
                aspectRatios[url] = aspect
            }
        }
        return aspect
    }

    /// A libVLC instance just for thumbnails, so they never disturb playback.
    private func library() -> VLCLibrary {
        lock.lock()
        defer { lock.unlock() }
        if let vlcLibrary {
            return vlcLibrary
        }
        let library = VLCLibrary(options: ["--no-audio", "--no-sub-autodetect-file"])
        vlcLibrary = library
        return library
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// The size VLC scales a thumbnail to.
struct ThumbnailBox: Equatable, Sendable {
    var width: Int
    var height: Int
    /// Crop to the box's shape instead of scaling into it.
    var crops = false

    /// The largest box of `aspectRatio` (width ÷ height) whose long side is
    /// `maxPixelSize`.
    static func fitting(aspectRatio: Double, maxPixelSize: Int) -> ThumbnailBox {
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return ThumbnailBox(width: maxPixelSize, height: max(16, maxPixelSize * 9 / 16), crops: true)
        }
        if aspectRatio >= 1 {
            return ThumbnailBox(width: maxPixelSize, height: max(16, Int((Double(maxPixelSize) / aspectRatio).rounded())))
        }
        return ThumbnailBox(width: max(16, Int((Double(maxPixelSize) * aspectRatio).rounded())), height: maxPixelSize)
    }
}

/// Reads a file's video size and pixel shape with libVLC's parser.
private final class AspectProbe: NSObject, VLCMediaParserDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Double?, Never>?
    private var parser: VLCMediaParser?
    private var isFinished = false

    func run(media: VLCMedia, library: VLCLibrary) async -> Double? {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            let parser = VLCMediaParser(library: library, timeout: 5_000)
            parser.delegate = self
            lock.withLock { self.parser = parser }
            if parser.queue(media, options: .parse) != 0 {
                finish(nil)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                self?.finish(nil, cancelsParsing: true)
            }
        }
    }

    func mediaFinishedParsing(_ media: VLCMedia, with status: VLCMediaParsedStatus) {
        guard let video = media.videoTracks.first?.video, video.width > 0, video.height > 0 else {
            finish(nil)
            return
        }
        var pixelAspect = 1.0
        if video.sourceAspectRatio > 0, video.sourceAspectRatioDenominator > 0 {
            pixelAspect = Double(video.sourceAspectRatio) / Double(video.sourceAspectRatioDenominator)
        }
        var aspect = Double(video.width) * pixelAspect / Double(video.height)
        // Phone videos filmed upright are stored sideways.
        if video.orientation == .rightTop || video.orientation == .leftBottom {
            aspect = 1 / aspect
        }
        finish(aspect)
    }

    /// - Parameter cancelsParsing: Only when giving up from outside: called
    ///   from the parser's own callback, cancelling would wait on itself.
    private func finish(_ aspect: Double?, cancelsParsing: Bool = false) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        let parser = self.parser
        lock.unlock()
        if cancelsParsing {
            parser?.cancelAllParsing()
        }
        continuation.resume(returning: aspect)
    }
}

/// One VLC thumbnail. The delegate is called on a libVLC thread, so the
/// picture is encoded there and only the bytes are handed back.
private final class ThumbnailRequest: NSObject, VLCMediaThumbnailerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var thumbnailer: VLCMediaThumbnailer?
    private var isFinished = false

    func run(media: VLCMedia, library: VLCLibrary, time: TimeInterval?, box: ThumbnailBox, precise: Bool) async -> Data? {
        let result: Data? = await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            let thumbnailer = VLCMediaThumbnailer(media: media, delegate: self, andVLCLibrary: library)
            thumbnailer.thumbnailWidth = CGFloat(box.width)
            thumbnailer.thumbnailHeight = CGFloat(box.height)
            thumbnailer.cropsToFit = box.crops
            thumbnailer.preciseSeek = precise
            // An exact frame decodes everything from the keyframe before it:
            // fast with VideoToolbox, seconds in software for 4K. libVLC
            // falls back to software by itself when it has to.
            thumbnailer.hardwareDecodingEnabled = true
            if let time, time.isFinite, time >= 0 {
                thumbnailer.snapshotTime = VLCTime(int: Int32(clamping: Int((time * 1_000).rounded())))
            } else {
                thumbnailer.snapshotPosition = 0.1
            }
            lock.lock()
            self.thumbnailer = thumbnailer
            lock.unlock()
            thumbnailer.fetchThumbnail()

            // VLC gives up on its own after about ten seconds, but not in every
            // failure path; never wait forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.finish(nil)
            }
        }
        let thumbnailer = lock.withLock { self.thumbnailer }
        if result == nil {
            thumbnailer?.cancel()
        }
        return result
    }

    private func finish(_ data: Data?) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: data)
    }

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        finish(nil)
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        finish(FrameGrabber.jpeg(thumbnail))
    }
}
