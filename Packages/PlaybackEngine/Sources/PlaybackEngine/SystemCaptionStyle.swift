import CoreGraphics
import CoreText
import Foundation
import MediaAccessibility
import PlaybackCore

/// The person's Subtitles & Captioning settings (Accessibility in System
/// Settings) as a subtitle style for VLC; AVFoundation follows them by
/// itself. Only choices set to override video apply, so the system's
/// default look leaves VLC's alone.
enum SystemCaptionStyle {
    static func current() -> SubtitleStyle {
        var style = SubtitleStyle.standard
        let domain = MACaptionAppearanceDomain.user

        var behavior = MACaptionAppearanceBehavior.useContentIfAvailable
        let foreground = MACaptionAppearanceCopyForegroundColor(domain, &behavior).takeRetainedValue()
        if behavior == .useValue, let color = nearestColor(to: foreground) {
            style.textColor = color
        }

        behavior = .useContentIfAvailable
        let opacity = MACaptionAppearanceGetBackgroundOpacity(domain, &behavior)
        if behavior == .useValue {
            style.background = opacity > 0.8 ? .solid : (opacity > 0.15 ? .translucent : .none)
        }

        behavior = .useContentIfAvailable
        let edge = MACaptionAppearanceGetTextEdgeStyle(domain, &behavior)
        if behavior == .useValue {
            switch edge {
            case .none: style.outline = .none
            case .uniform: style.outline = .thick
            default: break
            }
        }

        behavior = .useContentIfAvailable
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, &behavior, .default).takeRetainedValue()
        if behavior == .useValue,
           let family = (CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String)?.lowercased() {
            if family.contains("mono") || family.contains("courier") || family.contains("menlo") {
                style.font = .monospaced
            } else if family.contains("rounded") {
                style.font = .rounded
            } else if family.contains("condensed") {
                style.font = .condensed
            } else if family.contains("serif") && !family.contains("sans") || family.contains("georgia") || family.contains("times") {
                style.font = .serif
            }
        }
        return style
    }

    /// The closest of the colours VLC's subtitle style offers.
    static func nearestColor(to color: CGColor) -> SubtitleStyle.TextColor? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return nil }
        let (red, green, blue) = (Double(parts[0]), Double(parts[1]), Double(parts[2]))
        return SubtitleStyle.TextColor.allCases.min { lhs, rhs in
            distance(lhs.components, red, green, blue) < distance(rhs.components, red, green, blue)
        }
    }

    private static func distance(_ color: (red: Double, green: Double, blue: Double), _ red: Double, _ green: Double, _ blue: Double) -> Double {
        let r = color.red - red
        let g = color.green - green
        let b = color.blue - blue
        return r * r + g * g + b * b
    }
}
