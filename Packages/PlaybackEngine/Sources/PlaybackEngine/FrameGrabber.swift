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
        let request = ThumbnailRequest()
        return await request.run(media: media, library: library(), time: time, size: maxPixelSize, precise: precise)
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

/// One VLC thumbnail. The delegate is called on a libVLC thread, so the
/// picture is encoded there and only the bytes are handed back.
private final class ThumbnailRequest: NSObject, VLCMediaThumbnailerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var thumbnailer: VLCMediaThumbnailer?
    private var isFinished = false

    func run(media: VLCMedia, library: VLCLibrary, time: TimeInterval?, size: Int, precise: Bool) async -> Data? {
        let result: Data? = await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            let thumbnailer = VLCMediaThumbnailer(media: media, delegate: self, andVLCLibrary: library)
            thumbnailer.thumbnailWidth = CGFloat(size)
            thumbnailer.thumbnailHeight = CGFloat(size)
            thumbnailer.cropsToFit = false
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
