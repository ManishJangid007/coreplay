import Foundation

/// Raw AAC in ADTS frames (`.aac` files). There's no header with the total
/// length, so the duration is estimated from the average frame size near the
/// start of the stream.
enum ADTS {
    private static let sampleRates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    static func analyse(_ source: ByteSource, audioStart: Int64, audioEnd: Int64) throws -> (duration: TimeInterval?, format: AudioFormatInfo?) {
        let window = try source.bytes(at: audioStart, count: 64 * 1024)
        guard window.count >= 7 else { return (nil, nil) }
        let sampleRateIndex = Int((window[2] >> 2) & 0x0F)
        guard sampleRateIndex < sampleRates.count else { return (nil, nil) }
        let sampleRate = sampleRates[sampleRateIndex]
        let channels = Int((window[2] & 0x01) << 2 | window[3] >> 6)

        var index = 0
        var frames = 0
        var bytes = 0
        while index + 7 <= window.count, window[index] == 0xFF, window[index + 1] & 0xF6 == 0xF0 {
            let length = Int(window[index + 3] & 0x03) << 11 | Int(window[index + 4]) << 3 | Int(window[index + 5]) >> 5
            guard length >= 7 else { break }
            frames += 1
            bytes += length
            index += length
        }

        var duration: TimeInterval?
        var bitRate: Int?
        if frames > 0 {
            let averageFrame = Double(bytes) / Double(frames)
            let totalFrames = Double(audioEnd - audioStart) / averageFrame
            let seconds = totalFrames * 1024 / Double(sampleRate)
            duration = seconds
            bitRate = Int(averageFrame * 8 * Double(sampleRate) / 1024)
        }
        let format = AudioFormatInfo(codec: "AAC", sampleRate: sampleRate, channels: channels > 0 ? channels : nil, bitRate: bitRate, isLossless: false)
        return (duration, format)
    }
}
