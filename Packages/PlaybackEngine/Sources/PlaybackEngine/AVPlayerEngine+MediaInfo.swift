import AVFoundation
import CoreMedia
import Foundation
import PlaybackCore

// Media Info for the AVFoundation engine: each asset track's format
// description, and the player item's access log for live figures.

extension AVPlayerEngine {
    func mediaInfo() async -> MediaInfo {
        guard let asset, let tracks = try? await asset.load(.tracks) else { return MediaInfo() }
        // Which tracks are playing right now (audio and subtitle choices).
        let enabled = Set((playerItem?.tracks ?? []).filter(\.isEnabled).compactMap { $0.assetTrack?.trackID })
        var streams: [MediaInfo.Stream] = []
        for track in tracks {
            let kind: MediaInfo.Stream.Kind
            switch track.mediaType {
            case .video: kind = .video
            case .audio: kind = .audio
            case .subtitle, .closedCaption, .text: kind = .subtitle
            default: continue
            }
            streams.append(await Self.stream(from: track, kind: kind, isSelected: enabled.contains(track.trackID)))
        }
        return MediaInfo(streams: streams)
    }

    var statistics: PlaybackStatistics? {
        guard let event = playerItem?.accessLog()?.events.last else { return nil }
        let bitrate = event.observedBitrate > 0 ? event.observedBitrate : event.indicatedBitrate
        return PlaybackStatistics(
            inputBitrate: max(bitrate, 0),
            displayedPictures: 0,
            lostPictures: max(event.numberOfDroppedVideoFrames, 0),
            lostAudioBuffers: 0
        )
    }

    private static func stream(from track: AVAssetTrack, kind: MediaInfo.Stream.Kind, isSelected: Bool) async -> MediaInfo.Stream {
        var stream = MediaInfo.Stream(id: "\(kind.rawValue)-\(track.trackID)", kind: kind, isSelected: isSelected)
        guard let loaded = try? await track.load(
            .formatDescriptions, .estimatedDataRate, .nominalFrameRate, .naturalSize, .preferredTransform,
            .languageCode, .extendedLanguageTag, .commonMetadata
        ) else { return stream }
        let (descriptions, dataRate, frameRate, size, transform, language, tag, metadata) = loaded

        if let description = descriptions.first {
            let code = FourCC(rawValue: CMFormatDescriptionGetMediaSubType(description)).description
            stream.fourCC = code.trimmingCharacters(in: .whitespaces)
            stream.codec = CodecNames.name(for: code)
            if kind == .video {
                stream.dynamicRange = dynamicRange(of: description, code: code)
            }
            if kind == .audio, let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                stream.channels = format.mChannelsPerFrame > 0 ? Int(format.mChannelsPerFrame) : nil
                stream.sampleRate = format.mSampleRate > 0 ? Int(format.mSampleRate.rounded()) : nil
            }
        }
        stream.language = tag ?? language
        stream.bitrate = dataRate > 0 ? Int(dataRate.rounded()) : nil
        if kind == .video {
            stream.width = size.width > 0 ? Int(size.width.rounded()) : nil
            stream.height = size.height > 0 ? Int(size.height.rounded()) : nil
            stream.frameRate = frameRate > 0 ? Double(frameRate) : nil
            let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
            stream.rotation = (degrees + 360) % 360
        }
        let titles = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
        if let title = titles.first, let value = try? await title.load(.stringValue), !value.isEmpty {
            stream.title = value
        }
        return stream
    }

    /// HDR10, HLG or Dolby Vision, from the video's format description.
    private static func dynamicRange(of description: CMFormatDescription, code: String) -> String? {
        if code.hasPrefix("dv") {
            return "Dolby Vision"
        }
        guard let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else {
            return nil
        }
        if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            return "HDR10"
        }
        if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            return "HLG"
        }
        return nil
    }
}
