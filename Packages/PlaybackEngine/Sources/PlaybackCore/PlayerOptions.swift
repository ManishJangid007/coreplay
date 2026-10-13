import Foundation

// Level 2 options: what the player's options panel and the Mac's Audio,
// Video and Subtitles menus change. Plain values, so they can be remembered,
// compared and re-applied after the controller moves an item to another engine.

/// How the picture sits in the player.
public enum VideoFillMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// The whole picture, with black bars where the shapes differ (the default).
    case fit
    /// Fills the player, trimming the edges, like the TV app's zoom.
    case fill

    public var title: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        }
    }

    public var systemImage: String {
        switch self {
        case .fit: "arrow.down.right.and.arrow.up.left"
        case .fill: "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// A picture shape, for forcing the aspect ratio or cropping.
public struct VideoRatio: Hashable, Sendable, Codable, Identifiable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var id: String { description }

    /// "16:9", the form libVLC expects.
    public var description: String { "\(width):\(height)" }

    public var value: Double { Double(width) / Double(height) }

    /// Readable name: "16:9", "2.39:1 (Scope)", "1:1 (Square)".
    public var title: String {
        switch (width, height) {
        case (239, 100): "2.39:1 (Scope)"
        case (185, 100): "1.85:1 (Flat)"
        case (221, 100): "2.21:1 (70 mm)"
        case (1, 1): "1:1 (Square)"
        default:
            if height == 100 {
                "\((Double(width) / 100).formatted(.number.precision(.fractionLength(2)))):1"
            } else {
                description
            }
        }
    }

    /// Parses "16:9", "2.39:1" or "1.85".
    public init?(parsing text: String) {
        let parts = text.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        func scaled(_ string: String) -> Double? {
            guard let value = Double(string), value.isFinite, value > 0 else { return nil }
            return value
        }
        switch parts.count {
        case 1:
            guard let value = scaled(parts[0]) else { return nil }
            self.init(Int((value * 100).rounded()), 100)
        case 2:
            guard let width = scaled(parts[0]), let height = scaled(parts[1]) else { return nil }
            if width.rounded() == width, height.rounded() == height {
                self.init(Int(width), Int(height))
            } else {
                self.init(Int((width / height * 100).rounded()), 100)
            }
        default:
            return nil
        }
    }

    /// Shapes offered for "Aspect Ratio" (the picture is stretched to them).
    public static let aspectPresets: [VideoRatio] = [
        VideoRatio(16, 9), VideoRatio(4, 3), VideoRatio(16, 10), VideoRatio(185, 100),
        VideoRatio(239, 100), VideoRatio(21, 9), VideoRatio(5, 4), VideoRatio(1, 1),
    ]

    /// Shapes offered for "Crop" (edges are trimmed to them, e.g. to remove
    /// black bars burnt into a 4:3 broadcast of a widescreen film).
    public static let cropPresets: [VideoRatio] = [
        VideoRatio(16, 9), VideoRatio(4, 3), VideoRatio(16, 10), VideoRatio(185, 100),
        VideoRatio(239, 100), VideoRatio(21, 9), VideoRatio(1, 1),
    ]
}

/// Deinterlacing for interlaced sources (DVDs, TV recordings).
public enum DeinterlaceMode: String, Hashable, Sendable, Codable, CaseIterable {
    case automatic
    case on
    case off

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .on: "On"
        case .off: "Off"
        }
    }
}

/// Picture adjustments, in libVLC's units.
public struct VideoAdjustments: Hashable, Sendable, Codable {
    /// 0…2, 1 is unchanged.
    public var brightness: Float
    /// 0…2, 1 is unchanged.
    public var contrast: Float
    /// 0…3, 1 is unchanged.
    public var saturation: Float
    /// Degrees, −180…180, 0 is unchanged.
    public var hue: Float
    /// 0.01…10, 1 is unchanged.
    public var gamma: Float

    public init(brightness: Float = 1, contrast: Float = 1, saturation: Float = 1, hue: Float = 0, gamma: Float = 1) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
        self.gamma = gamma
    }

    public static let neutral = VideoAdjustments()

    public var isNeutral: Bool { self == .neutral }

    /// Every value kept inside the range libVLC accepts.
    public var clamped: VideoAdjustments {
        VideoAdjustments(
            brightness: min(max(brightness, 0), 2),
            contrast: min(max(contrast, 0), 2),
            saturation: min(max(saturation, 0), 3),
            hue: min(max(hue, -180), 180),
            gamma: min(max(gamma, 0.01), 10)
        )
    }
}

/// How stereo audio comes out of the speakers.
public enum StereoMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// Whatever the file and the output device agree on.
    case automatic
    case stereo
    case mono
    case left
    case right
    /// Left and right swapped.
    case reversed
    case dolbySurround

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .stereo: "Stereo"
        case .mono: "Mono"
        case .left: "Left Channel Only"
        case .right: "Right Channel Only"
        case .reversed: "Swap Left and Right"
        case .dolbySurround: "Dolby Surround"
        }
    }
}

/// The 10-band equalizer. Values are in decibels, −20…20.
public struct EqualizerSettings: Hashable, Sendable, Codable {
    public static let bandCount = 10

    public var isEnabled: Bool
    /// The preset last chosen, if the bands still match it.
    public var presetName: String?
    public var preamp: Float
    public var bands: [Float]

    public init(isEnabled: Bool = false, presetName: String? = nil, preamp: Float = 0, bands: [Float] = Array(repeating: 0, count: EqualizerSettings.bandCount)) {
        self.isEnabled = isEnabled
        self.presetName = presetName
        self.preamp = EqualizerSettings.clampGain(preamp)
        self.bands = EqualizerSettings.normalized(bands)
    }

    public static let flat = EqualizerSettings()

    /// Band centre frequencies used for labels when the engine can't say
    /// (libVLC's default ISO bands).
    public static let defaultFrequencies: [Float] = [31.25, 62.5, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    public static func clampGain(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -20), 20)
    }

    /// Exactly `bandCount` values, each clamped.
    public static func normalized(_ values: [Float]) -> [Float] {
        var result = values.prefix(bandCount).map(clampGain)
        while result.count < bandCount {
            result.append(0)
        }
        return result
    }

    /// "60 Hz", "1 kHz", "16 kHz".
    public static func frequencyLabel(_ hertz: Float) -> String {
        if hertz >= 1_000 {
            let kilohertz = Double(hertz) / 1_000
            return "\(kilohertz.formatted(.number.precision(.fractionLength(0...1)))) kHz"
        }
        return "\(Double(hertz).formatted(.number.precision(.fractionLength(0...1)))) Hz"
    }
}

/// Subtitle text size, as a scale on the engine's default.
public enum SubtitleSize: String, Hashable, Sendable, Codable, CaseIterable {
    case small
    case standard
    case large
    case extraLarge

    public var scale: Float {
        switch self {
        case .small: 0.75
        case .standard: 1
        case .large: 1.35
        case .extraLarge: 1.75
        }
    }

    public var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

/// An A–B loop: playback returns to `start` whenever it reaches `end`.
///
/// Engines don't all support loops, so the controller watches the clock
/// itself; this type holds the rules.
public struct ABLoop: Hashable, Sendable {
    public private(set) var start: TimeInterval?
    public private(set) var end: TimeInterval?

    public init(start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.start = start
        self.end = end
    }

    public enum Phase: Hashable, Sendable {
        case off
        /// A is set; the next press sets B.
        case waitingForEnd
        case looping
    }

    public var phase: Phase {
        switch (start, end) {
        case (nil, _): .off
        case (_?, nil): .waitingForEnd
        case (_?, _?): .looping
        }
    }

    /// The loop is shorter than this, B is ignored (a double press, most likely).
    public static let minimumLength: TimeInterval = 0.5

    /// One button cycles through: set A → set B → clear.
    public mutating func advance(at time: TimeInterval) {
        switch phase {
        case .off:
            start = max(0, time)
            end = nil
        case .waitingForEnd:
            guard let start else { return }
            if time - start >= Self.minimumLength {
                end = time
            } else if start - time >= Self.minimumLength {
                // Pressed B before A: swap, so the loop still makes sense.
                end = start
                self.start = max(0, time)
            }
        case .looping:
            clear()
        }
    }

    public mutating func clear() {
        start = nil
        end = nil
    }

    /// Where to jump when playback reaches `time`, or `nil` to carry on.
    public func jumpTarget(at time: TimeInterval) -> TimeInterval? {
        guard let start, let end, time >= end else { return nil }
        return start
    }
}
