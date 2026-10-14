import AVFoundation
import CoreMedia
import Foundation
import PlaybackCore

/// Asks AVFoundation what's inside a local file, so the router can decide
/// whether AVPlayer can play every track. Runs off the main actor and gives
/// up after a few seconds (slow network volumes, huge files), in which case
/// the router falls back to VLC.
actor MediaProber {
    private var cache: [URL: MediaProbe] = [:]

    func probe(_ url: URL, timeout: Duration = .seconds(3)) async -> MediaProbe? {
        if let cached = cache[url] {
            return cached
        }
        // A task group would wait for a hung AVFoundation load even after
        // cancellation, so race two unstructured tasks and take the first answer.
        let result: MediaProbe? = await withCheckedContinuation { continuation in
            let gate = FirstResultGate(continuation)
            Task.detached(priority: .userInitiated) {
                gate.resume(with: await MediaProber.inspect(url))
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                gate.resume(with: nil)
            }
        }
        if let result {
            cache[url] = result
        }
        return result
    }

    private static func inspect(_ url: URL) async -> MediaProbe? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        do {
            let (isPlayable, hasProtectedContent, tracks) = try await asset.load(.isPlayable, .hasProtectedContent, .tracks)
            var probedTracks: [MediaProbe.Track] = []
            for track in tracks {
                // mediaType is a plain property; only the others are loaded asynchronously.
                let mediaType = track.mediaType
                let (formatDescriptions, trackIsPlayable) = try await track.load(.formatDescriptions, .isPlayable)
                let kind: MediaProbe.Track.Kind
                switch mediaType {
                case .video, .muxed:
                    kind = .video
                case .audio:
                    kind = .audio
                case .subtitle, .closedCaption, .text:
                    kind = .text
                default:
                    kind = .auxiliary
                }
                if formatDescriptions.isEmpty {
                    probedTracks.append(MediaProbe.Track(kind: kind, codec: FourCC(rawValue: 0), isPlayable: trackIsPlayable))
                }
                for description in formatDescriptions {
                    let subtype = CMFormatDescriptionGetMediaSubType(description)
                    probedTracks.append(MediaProbe.Track(kind: kind, codec: FourCC(rawValue: subtype), isPlayable: trackIsPlayable))
                }
            }
            // A few kilobytes of the movie box; AVFoundation doesn't say.
            let projection = probedTracks.contains { $0.kind == .video } ? SphericalVideoDetector.projection(ofFileAt: url) : .flat
            return MediaProbe(isPlayable: isPlayable, hasProtectedContent: hasProtectedContent, tracks: probedTracks, projection: projection)
        } catch {
            return nil
        }
    }
}

/// Resumes a continuation with whichever result arrives first.
private final class FirstResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MediaProbe?, Never>?

    init(_ continuation: CheckedContinuation<MediaProbe?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: MediaProbe?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
