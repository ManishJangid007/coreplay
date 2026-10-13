internal import VLCKit
import Foundation
import PlaybackCore

// Media Info for the VLC engine: libVLC's view of every track, and its live
// statistics. Names checked against the VLCKit 4.0.0a25 headers
// (VLCMediaPlayer.Track: codec, bitrate, language, trackDescription, audio,
// video, text; VLCMedia.statistics).

extension VLCKitEngine {
    func mediaInfo() async -> MediaInfo {
        var streams: [MediaInfo.Stream] = []
        streams += player.videoTracks.map { Self.stream(from: $0, kind: .video) }
        streams += player.audioTracks.map { Self.stream(from: $0, kind: .audio) }
        streams += player.textTracks.map { Self.stream(from: $0, kind: .subtitle) }
        return MediaInfo(streams: streams)
    }

    var statistics: PlaybackStatistics? {
        guard let media = player.media, state == .playing || state == .paused || state == .buffering else { return nil }
        let figures = media.statistics
        return PlaybackStatistics(
            // libVLC counts bytes per microsecond.
            inputBitrate: Double(figures.inputBitrate) * 8_000_000,
            displayedPictures: Int(clamping: figures.displayedPictures),
            lostPictures: Int(clamping: figures.lostPictures),
            lostAudioBuffers: Int(clamping: figures.lostAudioBuffers)
        )
    }

    private static func stream(from track: VLCMediaPlayer.Track, kind: MediaInfo.Stream.Kind) -> MediaInfo.Stream {
        // libVLC's codes keep the first character in the lowest byte.
        let code = FourCC(rawValue: (track.codec != 0 ? track.codec : track.fourcc).byteSwapped).description
        var stream = MediaInfo.Stream(id: "\(kind.rawValue)-\(track.trackId)", kind: kind)
        stream.fourCC = code.trimmingCharacters(in: .whitespaces)
        stream.codec = CodecNames.name(for: code) ?? track.codecName().nonEmptyValue
        stream.language = track.language?.nonEmptyValue
        stream.title = track.trackDescription?.nonEmptyValue
        stream.bitrate = track.bitrate > 0 ? Int(track.bitrate) : nil
        stream.isSelected = track.isSelected
        if let video = track.video {
            stream.width = video.width > 0 ? Int(video.width) : nil
            stream.height = video.height > 0 ? Int(video.height) : nil
            if video.frameRate > 0, video.frameRateDenominator > 0 {
                stream.frameRate = Double(video.frameRate) / Double(video.frameRateDenominator)
            }
            stream.rotation = switch video.orientation {
            case .topLeft: 0
            case .rightTop: 90
            case .bottomRight: 180
            case .leftBottom: 270
            default: nil
            }
            stream.isSpherical = video.projection == .equiRectangular
        }
        if let audio = track.audio {
            stream.channels = audio.channelsNumber > 0 ? Int(audio.channelsNumber) : nil
            stream.sampleRate = audio.rate > 0 ? Int(audio.rate) : nil
        }
        if let text = track.text {
            stream.textEncoding = text.encoding?.nonEmptyValue
        }
        return stream
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
