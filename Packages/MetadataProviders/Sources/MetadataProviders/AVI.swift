import Foundation

/// AVI: the `hdrl` list at the start of the file has the frame size,
/// each stream's codec and length, and (in OpenDML files) the real frame count.
enum AVI {
    static func read(_ source: ByteSource) throws -> VideoInfo? {
        // RIFF header (12 bytes), then LIST 'hdrl' — always first.
        let listHeader = try source.bytes(at: 12, count: 12)
        guard listHeader.count == 12, Bytes.matches(listHeader, 0, "LIST"), Bytes.matches(listHeader, 8, "hdrl") else { return nil }
        let listSize = Int(try Bytes.u32le(listHeader, 4))
        let hdrl = try source.bytes(at: 24, count: min(max(listSize - 4, 0), 1_048_576))

        var info = VideoInfo(container: "AVI")
        var microsecondsPerFrame: UInt32 = 0
        var totalFrames: UInt32 = 0
        var videoLength: Double?

        for chunk in chunks(hdrl, from: 0, to: hdrl.count) {
            switch chunk.id {
            case "avih":
                microsecondsPerFrame = (try? Bytes.u32le(hdrl, chunk.start)) ?? 0
                totalFrames = (try? Bytes.u32le(hdrl, chunk.start + 16)) ?? 0
                if let width = try? Bytes.u32le(hdrl, chunk.start + 32), let height = try? Bytes.u32le(hdrl, chunk.start + 36), width > 0, height > 0 {
                    info.width = Int(width)
                    info.height = Int(height)
                }
            case "LIST" where Bytes.matches(hdrl, chunk.start, "strl"):
                readStream(hdrl, from: chunk.start + 4, to: chunk.end, into: &info, videoLength: &videoLength)
            case "LIST" where Bytes.matches(hdrl, chunk.start, "odml"):
                for inner in chunks(hdrl, from: chunk.start + 4, to: chunk.end) where inner.id == "dmlh" {
                    if let frames = try? Bytes.u32le(hdrl, inner.start), frames > totalFrames {
                        totalFrames = frames
                    }
                }
            default:
                break
            }
        }
        if let videoLength, videoLength > 0 {
            info.duration = videoLength
        } else if microsecondsPerFrame > 0, totalFrames > 0 {
            info.duration = Double(totalFrames) * Double(microsecondsPerFrame) / 1_000_000
        }
        if info.frameRate == nil, microsecondsPerFrame > 0 {
            info.frameRate = (1_000_000 / Double(microsecondsPerFrame) * 1_000).rounded() / 1_000
        }
        info.dynamicRange = info.videoCodec == nil ? nil : .sdr
        guard info.videoCodec != nil || !info.audioTracks.isEmpty else { return nil }
        return info
    }

    private struct Chunk {
        var id: String
        var start: Int
        var end: Int
    }

    private static func chunks(_ bytes: [UInt8], from start: Int, to end: Int) -> [Chunk] {
        var result: [Chunk] = []
        var position = start
        while position + 8 <= end, result.count < 256 {
            guard let id = Bytes.fourCC(bytes, position), let size = try? Bytes.u32le(bytes, position + 4) else { break }
            let chunkEnd = min(position + 8 + Int(size), end)
            result.append(Chunk(id: id, start: position + 8, end: chunkEnd))
            position += 8 + Int(size) + Int(size % 2)
        }
        return result
    }

    /// `strh` (stream header) and `strf` (format) of one stream.
    private static func readStream(_ bytes: [UInt8], from start: Int, to end: Int, into info: inout VideoInfo, videoLength: inout Double?) {
        var type = ""
        var scale: UInt32 = 0
        var rate: UInt32 = 0
        var length: UInt32 = 0
        var name: String?
        for chunk in chunks(bytes, from: start, to: end) {
            switch chunk.id {
            case "strh":
                type = Bytes.fourCC(bytes, chunk.start) ?? ""
                scale = (try? Bytes.u32le(bytes, chunk.start + 20)) ?? 0
                rate = (try? Bytes.u32le(bytes, chunk.start + 24)) ?? 0
                length = (try? Bytes.u32le(bytes, chunk.start + 32)) ?? 0
            case "strn":
                name = Text.cleaned(String(decoding: bytes[chunk.start..<chunk.end].prefix { $0 != 0 }, as: UTF8.self))
            case "strf" where type == "vids":
                if info.videoCodec == nil, let fourCC = Bytes.fourCC(bytes, chunk.start + 16) {
                    info.videoCodec = videoCodec(fourCC: fourCC)
                    if let width = try? Bytes.u32le(bytes, chunk.start + 4), width > 0, info.width == nil {
                        info.width = Int(width)
                    }
                }
            case "strf" where type == "auds":
                let tag = (try? Bytes.u16le(bytes, chunk.start)) ?? 0
                let channels = (try? Bytes.u16le(bytes, chunk.start + 2)).map(Int.init)
                info.audioTracks.append(VideoInfo.AudioTrack(codec: audioCodec(formatTag: tag), channels: channels, title: name))
            default:
                break
            }
        }
        if type == "vids", scale > 0, rate > 0 {
            info.frameRate = (Double(rate) / Double(scale) * 1_000).rounded() / 1_000
            if length > 0 {
                videoLength = Double(length) * Double(scale) / Double(rate)
            }
        }
    }

    static func videoCodec(fourCC: String) -> String {
        switch fourCC.uppercased() {
        case "XVID": return "Xvid"
        case "DIVX", "DX50", "DIV3", "DIV4", "DIV5", "DIV6": return "DivX"
        case "FMP4", "MP4V": return "MPEG-4"
        case "H264", "X264", "AVC1", "DAVC": return "H.264"
        case "HEVC", "HEV1", "HVC1", "H265", "X265": return "HEVC"
        case "MJPG", "AVRN", "LJPG": return "Motion JPEG"
        case "WMV1", "WMV2", "WMV3", "WVC1": return "Windows Media Video"
        case "MP42", "MP43": return "Microsoft MPEG-4"
        case "MPG1", "MPG2": return "MPEG"
        case "VP80": return "VP8"
        case "VP90": return "VP9"
        case "AV01": return "AV1"
        case "CVID": return "Cinepak"
        case "IV50", "IV41", "IV32", "IV31": return "Indeo"
        default: return fourCC.trimmingCharacters(in: .whitespaces)
        }
    }

    static func audioCodec(formatTag: UInt16) -> String {
        switch formatTag {
        case 0x0001: return "PCM"
        case 0x0003: return "PCM (Float)"
        case 0x0050: return "MP2"
        case 0x0055: return "MP3"
        case 0x00FF, 0x1610, 0x706D: return "AAC"
        case 0x0161, 0x0162, 0x0163: return "Windows Media Audio"
        case 0x2000: return "Dolby Digital"
        case 0x2001: return "DTS"
        case 0x674F, 0x6750, 0x6751: return "Vorbis"
        case 0xF1AC: return "FLAC"
        default: return String(format: "0x%04X", formatTag)
        }
    }
}
