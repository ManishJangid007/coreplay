import SwiftUI

/// Colours used where the system's semantic colours don't apply: the player
/// is always dark, whatever the appearance setting.
public enum Palette {
    public static let playerBackground = Color.black
    /// Behind controls drawn over video.
    public static let videoScrim = Color.black.opacity(0.45)
    public static let primaryOnDark = Color.white
    public static let secondaryOnDark = Color.white.opacity(0.68)
    public static let tertiaryOnDark = Color.white.opacity(0.32)
    /// The orange of the logo's cone. Matches the app's AccentColor; use it
    /// for brand moments, and `Color.accentColor` / `.tint` everywhere else.
    public static let brandOrange = Color(red: 0.88, green: 0.40, blue: 0.0)
    /// Fallback mesh colours when there's no artwork to sample: the logo's
    /// charcoal tile with a low ember of its orange.
    public static let fallbackMesh: [Color] = [
        Color(red: 0.13, green: 0.13, blue: 0.15), Color(red: 0.15, green: 0.14, blue: 0.15), Color(red: 0.11, green: 0.11, blue: 0.13),
        Color(red: 0.14, green: 0.12, blue: 0.12), Color(red: 0.32, green: 0.16, blue: 0.05), Color(red: 0.12, green: 0.11, blue: 0.12),
        Color(red: 0.06, green: 0.06, blue: 0.08), Color(red: 0.10, green: 0.08, blue: 0.08), Color(red: 0.05, green: 0.05, blue: 0.06),
    ]
}

/// Shared measurements, so artwork and controls look the same everywhere.
public enum Metrics {
    public static let gridSpacing: CGFloat = 16
    public static let contentPadding: CGFloat = 20
    public static let artworkShadowRadius: CGFloat = 18
    public static let miniPlayerArtworkSize: CGFloat = 36
}

/// The three artwork formats: square for audio, 2:3 posters and 16:9 stills for video.
public enum ArtworkShape: Hashable, Sendable {
    case square
    case poster
    case still

    public var aspectRatio: CGFloat {
        switch self {
        case .square: 1
        case .poster: 2.0 / 3.0
        case .still: 16.0 / 9.0
        }
    }

    public var cornerRadius: CGFloat {
        switch self {
        case .square: 10
        case .poster: 12
        case .still: 10
        }
    }

    public var placeholderSymbol: String {
        switch self {
        case .square: "music.note"
        case .poster: "film"
        case .still: "play.rectangle"
        }
    }
}

/// Animation presets. Every view that animates asks `Motion` so Reduce
/// Motion is respected in one place.
public enum Motion {
    public static let standard = Animation.spring(duration: 0.35, bounce: 0.15)
    public static let quick = Animation.spring(duration: 0.22, bounce: 0.1)
    public static let artworkScale = Animation.spring(duration: 0.5, bounce: 0.3)
    public static let controlsFade = Animation.easeInOut(duration: 0.25)

    /// `animation`, or a short cross-fade when Reduce Motion is on.
    public static func respecting(_ reduceMotion: Bool, _ animation: Animation = standard) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

public extension View {
    /// Subtle shadow used under artwork.
    func artworkShadow(isProminent: Bool = true) -> some View {
        shadow(color: .black.opacity(isProminent ? 0.28 : 0.15), radius: isProminent ? Metrics.artworkShadowRadius : 6, y: isProminent ? 10 : 3)
    }
}
