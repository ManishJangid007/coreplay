import Foundation

/// MPEG-1/2/2.5 Layer I–III frame headers, for MP3 duration and format.
///
/// Duration comes from a Xing/Info or VBRI header when the encoder wrote one
/// (every VBR file and most CBR files from LAME), otherwise from the bit rate
/// of the first frame and the size of the audio data.
enum MPEGAudio {
    struct FrameHeader: Equatable {
        enum Version { case mpeg1, mpeg2, mpeg25 }
        var version: Version
        var layer: Int
        var bitRate: Int // bits per second
        var sampleRate: Int
        var padding: Bool
        var isMono: Bool

        var samplesPerFrame: Int {
            switch layer {
            case 1: 384
            case 2: 1152
            default: version == .mpeg1 ? 1152 : 576
            }
        }

        var frameLength: Int {
            let pad = padding ? 1 : 0
            switch layer {
            case 1:
                return (12 * bitRate / sampleRate + pad) * 4
            case 3 where version != .mpeg1:
                return 72 * bitRate / sampleRate + pad
            default:
                return 144 * bitRate / sampleRate + pad
            }
        }

        /// Bytes of side information after the 4-byte header (Layer III).
        var sideInfoLength: Int {
            switch (version, isMono) {
            case (.mpeg1, false): 32
            case (.mpeg1, true): 17
            case (_, false): 17
            case (_, true): 9
            }
        }
    }

    private static let bitRates: [[Int]] = [
        // MPEG-1 Layer I, II, III
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
        // MPEG-2/2.5 Layer I, then Layers II and III
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    ]

    static func header(_ bytes: [UInt8], at index: Int) -> FrameHeader? {
        guard index >= 0, index + 4 <= bytes.count,
              bytes[index] == 0xFF, bytes[index + 1] & 0xE0 == 0xE0 else { return nil }
        let versionBits = (bytes[index + 1] >> 3) & 0x03
        let layerBits = (bytes[index + 1] >> 1) & 0x03
        let bitRateIndex = Int(bytes[index + 2] >> 4)
        let sampleRateIndex = Int((bytes[index + 2] >> 2) & 0x03)
        guard versionBits != 1, layerBits != 0, bitRateIndex != 0, bitRateIndex != 15, sampleRateIndex != 3 else { return nil }
        let version: FrameHeader.Version = versionBits == 3 ? .mpeg1 : (versionBits == 2 ? .mpeg2 : .mpeg25)
        let layer = 4 - Int(layerBits)
        let table: [Int]
        if version == .mpeg1 {
            table = bitRates[layer - 1]
        } else {
            table = layer == 1 ? bitRates[3] : bitRates[4]
        }
        let baseRates = [44_100, 48_000, 32_000]
        let sampleRate = switch version {
        case .mpeg1: baseRates[sampleRateIndex]
        case .mpeg2: baseRates[sampleRateIndex] / 2
        case .mpeg25: baseRates[sampleRateIndex] / 4
        }
        return FrameHeader(
            version: version,
            layer: layer,
            bitRate: table[bitRateIndex] * 1000,
            sampleRate: sampleRate,
            padding: (bytes[index + 2] >> 1) & 0x01 == 1,
            isMono: bytes[index + 3] >> 6 == 3
        )
    }

    /// Duration and format of MPEG audio between `audioStart` and `audioEnd`
    /// (the file minus leading and trailing tags).
    static func analyse(_ source: ByteSource, audioStart: Int64, audioEnd: Int64) throws -> (duration: TimeInterval?, format: AudioFormatInfo?) {
        let window = try source.bytes(at: audioStart, count: 64 * 1024)
        // The first header that's followed by another valid header, so stray
        // 0xFF bytes in junk data aren't mistaken for audio.
        var index = 0
        var found: (Int, FrameHeader)?
        while index + 4 <= window.count {
            if let candidate = header(window, at: index) {
                let next = index + candidate.frameLength
                if candidate.frameLength > 0, next + 4 > window.count || header(window, at: next) != nil {
                    found = (index, candidate)
                    break
                }
            }
            index += 1
        }
        guard let (frameIndex, first) = found else { return (nil, nil) }

        var duration: TimeInterval?
        var averageBitRate = first.bitRate
        let xingOffset = frameIndex + 4 + (first.layer == 3 ? first.sideInfoLength : 0)
        if Bytes.matches(window, xingOffset, "Xing") || Bytes.matches(window, xingOffset, "Info"),
           let flags = try? Bytes.u32be(window, xingOffset + 4), flags & 0x01 != 0,
           let frames = try? Bytes.u32be(window, xingOffset + 8), frames > 0 {
            duration = Double(frames) * Double(first.samplesPerFrame) / Double(first.sampleRate)
            if flags & 0x02 != 0, let bytes = try? Bytes.u32be(window, xingOffset + 12), let duration, duration > 0 {
                averageBitRate = Int(Double(bytes) * 8 / duration)
            }
        } else if Bytes.matches(window, frameIndex + 36, "VBRI"),
                  let bytes = try? Bytes.u32be(window, frameIndex + 36 + 10),
                  let frames = try? Bytes.u32be(window, frameIndex + 36 + 14), frames > 0 {
            let seconds = Double(frames) * Double(first.samplesPerFrame) / Double(first.sampleRate)
            duration = seconds
            if seconds > 0 { averageBitRate = Int(Double(bytes) * 8 / seconds) }
        } else if first.bitRate > 0 {
            let audioBytes = audioEnd - audioStart - Int64(frameIndex)
            if audioBytes > 0 {
                duration = Double(audioBytes) * 8 / Double(first.bitRate)
            }
        }

        let codec = switch first.layer {
        case 1: "MP1"
        case 2: "MP2"
        default: "MP3"
        }
        let format = AudioFormatInfo(
            codec: codec,
            sampleRate: first.sampleRate,
            channels: first.isMono ? 1 : 2,
            bitRate: averageBitRate,
            isLossless: false
        )
        return (duration, format)
    }
}
