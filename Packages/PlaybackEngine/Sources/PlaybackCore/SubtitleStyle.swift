import Foundation

/// How plain-text subtitles look (SRT, WebVTT, MP4 text): the font, colour,
/// outline, background, weight and height on the picture. Styled ASS/SSA
/// subtitles keep their own look, and picture subtitles (DVD, Blu-ray) can't
/// be restyled.
///
/// VLC draws subtitles with its text renderer, which reads these settings
/// when a player starts (`libVLCOptions`); AVFoundation takes them as text
/// style rules on the playing item.
public struct SubtitleStyle: Hashable, Sendable, Codable {
    public enum Font: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
        case standard
        case rounded
        case serif
        case monospaced
        case condensed

        public var id: Self { self }

        public var title: String {
            switch self {
            case .standard: "Default"
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .monospaced: "Monospaced"
            case .condensed: "Condensed"
            }
        }

        /// A family installed on every Apple platform.
        public var familyName: String {
            switch self {
            case .standard: "Helvetica Neue"
            case .rounded: "Arial Rounded MT Bold"
            case .serif: "Georgia"
            case .monospaced: "Menlo"
            case .condensed: "Avenir Next Condensed"
            }
        }
    }

    public enum TextColor: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
        case white
        case yellow
        case cyan
        case green
        case pink

        public var id: Self { self }

        public var title: String {
            switch self {
            case .white: "White"
            case .yellow: "Yellow"
            case .cyan: "Cyan"
            case .green: "Green"
            case .pink: "Pink"
            }
        }

        /// 0xRRGGBB.
        public var rgb: Int {
            switch self {
            case .white: 0xFFFFFF
            case .yellow: 0xFFE14D
            case .cyan: 0x5CE1E6
            case .green: 0x7CE07C
            case .pink: 0xFF8AD8
            }
        }

        /// Red, green and blue from 0 to 1.
        public var components: (red: Double, green: Double, blue: Double) {
            (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
        }
    }

    public enum Outline: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
        case none
        case thin
        case standard
        case thick

        public var id: Self { self }

        public var title: String {
            switch self {
            case .none: "None"
            case .thin: "Thin"
            case .standard: "Default"
            case .thick: "Thick"
            }
        }

        /// VLC's outline thickness (its default is 4).
        public var thickness: Int {
            switch self {
            case .none: 0
            case .thin: 2
            case .standard: 4
            case .thick: 6
            }
        }
    }

    public enum Background: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
        case none
        case translucent
        case solid

        public var id: Self { self }

        public var title: String {
            switch self {
            case .none: "None"
            case .translucent: "See-Through"
            case .solid: "Solid"
            }
        }

        /// 0 (clear) to 255 (black).
        public var opacity: Int {
            switch self {
            case .none: 0
            case .translucent: 150
            case .solid: 255
            }
        }
    }

    public enum Position: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
        case bottom
        case raised
        case higher

        public var id: Self { self }

        public var title: String {
            switch self {
            case .bottom: "Bottom"
            case .raised: "Raised"
            case .higher: "Higher"
            }
        }

        /// VLC's margin above the bottom of the picture, in pixels.
        public var margin: Int {
            switch self {
            case .bottom: 0
            case .raised: 50
            case .higher: 110
            }
        }

        /// AVFoundation's line position, as a percentage of the height.
        public var linePercentage: Double? {
            switch self {
            case .bottom: nil
            case .raised: 82
            case .higher: 72
            }
        }
    }

    public var font: Font
    public var textColor: TextColor
    public var isBold: Bool
    public var outline: Outline
    public var background: Background
    public var position: Position

    public init(
        font: Font = .standard,
        textColor: TextColor = .white,
        isBold: Bool = false,
        outline: Outline = .standard,
        background: Background = .none,
        position: Position = .bottom
    ) {
        self.font = font
        self.textColor = textColor
        self.isBold = isBold
        self.outline = outline
        self.background = background
        self.position = position
    }

    /// VLC's and AVFoundation's own look.
    public static let standard = SubtitleStyle()

    public var isStandard: Bool {
        self == .standard
    }

    /// "Default", or a summary such as "Yellow · Serif · Bold".
    public var summary: String {
        guard !isStandard else { return "Default" }
        var parts: [String] = []
        if textColor != .white { parts.append(textColor.title) }
        if font != .standard { parts.append(font.title) }
        if isBold { parts.append("Bold") }
        if background != .none { parts.append("\(background.title) Background") }
        if outline != .standard { parts.append("Outline \(outline.title)") }
        if position != .bottom { parts.append(position.title) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Options for the text renderer of a new libVLC instance. Empty for the
    /// standard style, so VLC keeps its own defaults.
    public var libVLCOptions: [String] {
        guard !isStandard else { return [] }
        var options = [
            "--freetype-font=\(font.familyName)",
            "--freetype-color=\(textColor.rgb)",
            "--freetype-outline-thickness=\(outline.thickness)",
            isBold ? "--freetype-bold" : "--no-freetype-bold",
        ]
        if background != .none {
            options.append("--freetype-background-opacity=\(background.opacity)")
            options.append("--freetype-background-color=0")
        }
        if position.margin > 0 {
            options.append("--sub-margin=\(position.margin)")
        }
        return options
    }
}

/// Character sets for subtitle files that aren't Unicode, as VLC's
/// "Default encoding" offers them. `nil` lets VLC detect UTF-8 and fall back
/// to the system's choice.
public enum SubtitleEncoding {
    public struct Choice: Hashable, Sendable, Identifiable {
        /// The iconv name VLC is given.
        public let id: String
        public let title: String
    }

    public static let all: [Choice] = [
        Choice(id: "UTF-8", title: "Unicode (UTF-8)"),
        Choice(id: "Windows-1252", title: "Western European (Windows)"),
        Choice(id: "ISO-8859-15", title: "Western European (ISO Latin 9)"),
        Choice(id: "Windows-1250", title: "Central European (Windows)"),
        Choice(id: "ISO-8859-2", title: "Central European (ISO Latin 2)"),
        Choice(id: "Windows-1251", title: "Cyrillic (Windows)"),
        Choice(id: "KOI8-R", title: "Russian (KOI8-R)"),
        Choice(id: "Windows-1253", title: "Greek (Windows)"),
        Choice(id: "Windows-1254", title: "Turkish (Windows)"),
        Choice(id: "Windows-1255", title: "Hebrew (Windows)"),
        Choice(id: "Windows-1256", title: "Arabic (Windows)"),
        Choice(id: "Windows-1257", title: "Baltic (Windows)"),
        Choice(id: "Windows-1258", title: "Vietnamese (Windows)"),
        Choice(id: "TIS-620", title: "Thai (TIS-620)"),
        Choice(id: "GB18030", title: "Chinese, Simplified (GB18030)"),
        Choice(id: "Big5", title: "Chinese, Traditional (Big5)"),
        Choice(id: "Shift_JIS", title: "Japanese (Shift JIS)"),
        Choice(id: "EUC-KR", title: "Korean (EUC-KR)"),
    ]

    public static func title(for encoding: String?) -> String {
        guard let encoding else { return "Automatic" }
        return all.first { $0.id == encoding }?.title ?? encoding
    }
}
