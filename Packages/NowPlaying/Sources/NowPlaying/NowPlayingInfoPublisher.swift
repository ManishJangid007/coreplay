import Foundation
import MediaPlayer
import PlaybackCore

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

/// Publishes the current item to `MPNowPlayingInfoCenter`, which drives the
/// Lock Screen, Control Center, the Dynamic Island, CarPlay, AirPods and the
/// macOS Now Playing menu. It works the same whichever engine is playing.
///
/// Elapsed time is only sent on discontinuities (play, pause, seek, rate
/// change); the system extrapolates in between.
@MainActor
final class NowPlayingInfoPublisher {
    private var info: [String: Any] = [:]
    private var artworkData: Data?

    func updateItem(
        title: String,
        artist: String?,
        albumTitle: String?,
        artworkData newArtworkData: Data?,
        duration: TimeInterval?,
        isVideo: Bool,
        assetURL: URL?
    ) {
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPMediaItemPropertyAlbumTitle] = albumTitle
        info[MPMediaItemPropertyPlaybackDuration] = duration.map { NSNumber(value: $0) }
        info[MPNowPlayingInfoPropertyIsLiveStream] = NSNumber(value: duration == nil)
        let mediaType: MPNowPlayingInfoMediaType = isVideo ? .video : .audio
        info[MPNowPlayingInfoPropertyMediaType] = NSNumber(value: mediaType.rawValue)
        info[MPNowPlayingInfoPropertyAssetURL] = assetURL
        if newArtworkData != artworkData {
            artworkData = newArtworkData
            info[MPMediaItemPropertyArtwork] = newArtworkData.flatMap(Self.makeArtwork)
        }
        push()
    }

    func updatePlayback(elapsed: TimeInterval, rate: Float, isPlaying: Bool) {
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: elapsed)
        info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: isPlaying ? rate : 0)
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = NSNumber(value: 1.0)
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
        push()
    }

    func clear() {
        info = [:]
        artworkData = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    private func push() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Builds the artwork outside the main actor's isolation: the system calls
    /// the request handler on a background queue.
    private nonisolated static func makeArtwork(_ data: Data) -> MPMediaItemArtwork? {
        guard let image = PlatformImage(data: data) else { return nil }
        let box = ArtworkImageBox(image: image)
        return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in
            box.image
        }
    }
}

/// Images are immutable once decoded; the box only lets them cross into the
/// artwork request handler.
private final class ArtworkImageBox: @unchecked Sendable {
    let image: PlatformImage

    init(image: PlatformImage) {
        self.image = image
    }
}
