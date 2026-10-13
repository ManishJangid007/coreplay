import Foundation

/// WAV (RIFF, little-endian chunks) and AIFF (IFF, big-endian chunks). Both
/// can carry an ID3v2 tag in a chunk; WAV can also have LIST/INFO text.
enum RIFF {
    private struct Chunk {
        var id: String
        var dataOffset: Int64
        var size: Int64
    }

    private static func chunks(_ source: ByteSource, from start: Int64, bigEndian: Bool) throws -> [Chunk] {
        var result: [Chunk] = []
        var position = start
        while position + 8 <= source.size, result.count < 512 {
            let header = try source.bytes(at: position, count: 8)
            guard header.count == 8 else { break }
            let id = Bytes.ascii(header[0..<4])
            let size = Int64(bigEndian ? try Bytes.u32be(header, 4) : try Bytes.u32le(header, 4))
            result.append(Chunk(id: id, dataOffset: position + 8, size: size))
            position += 8 + size + (size % 2) // chunks are padded to even sizes
        }
        return result
    }

    static func parseWAV(_ source: ByteSource) throws -> AudioTags {
        var tags = AudioTags()
        var info = AudioTags()
        var byteRate = 0
        var dataSize: Int64?
        for chunk in try chunks(source, from: 12, bigEndian: false) {
            switch chunk.id {
            case "fmt ":
                let fmt = try source.bytes(at: chunk.dataOffset, count: min(Int(chunk.size), 40))
                guard fmt.count >= 16 else { continue }
                var formatTag = try Bytes.u16le(fmt, 0)
                if formatTag == 0xFFFE, fmt.count >= 26 {
                    formatTag = try Bytes.u16le(fmt, 24) // WAVE_FORMAT_EXTENSIBLE subformat
                }
                let channels = Int(try Bytes.u16le(fmt, 2))
                let sampleRate = Int(try Bytes.u32le(fmt, 4))
                byteRate = Int(try Bytes.u32le(fmt, 8))
                let bits = Int(try Bytes.u16le(fmt, 14))
                let codec: String
                var lossless = false
                switch formatTag {
                case 1: codec = "PCM"; lossless = true
                case 3: codec = "PCM (Float)"; lossless = true
                case 0x55: codec = "MP3"
                case 0x2000: codec = "Dolby Digital"
                default: codec = "WAV"
                }
                tags.format = AudioFormatInfo(codec: codec, sampleRate: sampleRate, channels: channels, bitsPerSample: lossless ? bits : nil, bitRate: byteRate * 8, isLossless: lossless)
            case "data":
                dataSize = chunk.size
            case "LIST":
                let list = try source.bytes(at: chunk.dataOffset, count: min(Int(chunk.size), 1_048_576))
                guard Bytes.matches(list, 0, "INFO") else { continue }
                info.fillMissing(from: infoList(list))
            case "id3 ", "ID3 ":
                if chunk.size <= Int64(TagReader.maximumArtworkBytes) * 2,
                   let id3 = ID3v2.parse(try source.bytes(at: chunk.dataOffset, count: Int(chunk.size))) {
                    tags.fillMissing(from: id3)
                }
            default:
                break
            }
        }
        tags.fillMissing(from: info)
        if let dataSize, byteRate > 0 {
            tags.duration = Double(dataSize) / Double(byteRate)
        }
        return tags
    }

    /// LIST/INFO sub-chunks: INAM, IART, IPRD, ICRD, IGNR, ITRK, ICMT.
    private static func infoList(_ list: [UInt8]) -> AudioTags {
        var tags = AudioTags()
        var position = 4
        while position + 8 <= list.count {
            let id = Bytes.ascii(list[position..<(position + 4)])
            guard let size = try? Bytes.u32le(list, position + 4) else { break }
            let start = position + 8
            let end = min(start + Int(size), list.count)
            let raw = list[start..<end]
            let trimmed = raw.prefix(while: { $0 != 0 })
            // INFO text is officially ASCII; in practice UTF-8 or Latin-1.
            let value = Text.cleaned(String(bytes: trimmed, encoding: .utf8) ?? Text.latin1(trimmed))
            switch id {
            case "INAM": tags.title = value
            case "IART": tags.artist = value
            case "IPRD": tags.album = value
            case "ICRD": tags.year = Text.year(value)
            case "IGNR": tags.genre = value
            case "ITRK", "IPRT": tags.trackNumber = Text.numberPair(value).0
            case "ICMT": tags.comment = value
            default: break
            }
            position = start + Int(size) + Int(size % 2)
        }
        return tags
    }

    static func parseAIFF(_ source: ByteSource, isCompressed: Bool) throws -> AudioTags {
        var tags = AudioTags()
        var name: String?
        var author: String?
        for chunk in try chunks(source, from: 12, bigEndian: true) {
            switch chunk.id {
            case "COMM":
                let comm = try source.bytes(at: chunk.dataOffset, count: min(Int(chunk.size), 64))
                guard comm.count >= 18 else { continue }
                let channels = Int(try Bytes.u16be(comm, 0))
                let frames = Int64(try Bytes.u32be(comm, 2))
                let bits = Int(try Bytes.u16be(comm, 6))
                let sampleRate = extendedFloat(Array(comm[8..<18]))
                var codec = "PCM"
                var lossless = true
                if isCompressed, comm.count >= 22 {
                    let compression = Bytes.ascii(comm[18..<22])
                    switch compression {
                    case "NONE", "sowt", "twos", "fl32", "fl64", "in24", "in32": break
                    default:
                        codec = compression.trimmingCharacters(in: .whitespaces).uppercased()
                        lossless = false
                    }
                }
                if sampleRate > 0 {
                    tags.duration = Double(frames) / sampleRate
                }
                tags.format = AudioFormatInfo(codec: codec, sampleRate: Int(sampleRate), channels: channels, bitsPerSample: lossless ? bits : nil, isLossless: lossless)
            case "ID3 ", "id3 ":
                if chunk.size <= Int64(TagReader.maximumArtworkBytes) * 2,
                   let id3 = ID3v2.parse(try source.bytes(at: chunk.dataOffset, count: Int(chunk.size))) {
                    tags.fillMissing(from: id3)
                }
            case "NAME":
                name = Text.cleaned(Text.latin1(try source.bytes(at: chunk.dataOffset, count: min(Int(chunk.size), 1024))[...]))
            case "AUTH":
                author = Text.cleaned(Text.latin1(try source.bytes(at: chunk.dataOffset, count: min(Int(chunk.size), 1024))[...]))
            default:
                break
            }
        }
        tags.title = tags.title ?? name
        tags.artist = tags.artist ?? author
        return tags
    }

    /// The 80-bit IEEE 754 extended float AIFF uses for its sample rate.
    static func extendedFloat(_ bytes: [UInt8]) -> Double {
        guard bytes.count == 10 else { return 0 }
        let sign: Double = bytes[0] & 0x80 != 0 ? -1 : 1
        let exponent = Int(bytes[0] & 0x7F) << 8 | Int(bytes[1])
        var mantissa: UInt64 = 0
        for index in 2..<10 {
            mantissa = mantissa << 8 | UInt64(bytes[index])
        }
        guard exponent != 0 || mantissa != 0 else { return 0 }
        return sign * Double(mantissa) * pow(2, Double(exponent - 16383 - 63))
    }
}
