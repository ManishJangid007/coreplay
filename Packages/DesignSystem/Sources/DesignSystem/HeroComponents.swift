import SwiftUI

// Pieces of the big artwork headers: the hero carousel on Home, Movies and
// TV Shows, and the top of show pages. White on dark artwork, as in the TV app.

/// A title set large and compressed, standing in for a film's title art.
public struct HeroTitle: View {
    private let text: String
    private let size: CGFloat
    private let alignment: TextAlignment

    public init(_ text: String, size: CGFloat, alignment: TextAlignment = .leading) {
        self.text = text
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black))
            .fontWidth(.compressed)
            .textCase(.uppercase)
            .lineLimit(2)
            .minimumScaleFactor(0.45)
            .multilineTextAlignment(alignment)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "New" or "New Episodes", above a hero's title.
public struct HeroBadge: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(.black)
            .fixedSize()
    }
}

/// The white Play capsule of the TV app's headers.
public struct HeroPlayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let progress: Double?

    /// - Parameter progress: How far the item has been watched, drawn as a
    ///   thin bar along the bottom of the capsule.
    public init(progress: Double? = nil) {
        self.progress = progress
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .labelStyle(HeroPlayLabelStyle())
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .frame(minHeight: 46)
            .background(.white, in: Capsule())
            .overlay(alignment: .bottom) {
                if let progress {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.black.opacity(0.18))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.black.opacity(0.75))
                                    .frame(width: proxy.size.width * min(max(progress, 0.04), 1))
                            }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

private struct HeroPlayLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 15, weight: .bold))
            configuration.title
                .lineLimit(1)
        }
    }
}

/// A round button beside the Play capsule (add to the watchlist, mute): a
/// white symbol on a dark, see-through disc, as in the TV app's headers.
public struct HeroCircleButton: View {
    private let title: String
    private let systemImage: String
    private let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HeroCircleLabel(systemImage: systemImage)
        }
        .buttonStyle(HeroCirclePressStyle())
        .accessibilityLabel(Text(title))
        #if os(macOS)
        .help(title)
        #endif
    }
}

private struct HeroCirclePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The disc inside a `HeroCircleButton`, for menus that look like one.
public struct HeroCircleLabel: View {
    private let systemImage: String

    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Circle().fill(.black.opacity(0.38)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// Darkens artwork so white text reads on it, and fades its bottom edge
/// into the page.
public struct HeroScrim: View {
    public enum Style: Sendable {
        /// Full-width headers: text on the left, a fade at the bottom.
        case wide
        /// Cards: text centred along the bottom.
        case card
    }

    private let style: Style

    public init(_ style: Style) {
        self.style = style
    }

    public var body: some View {
        switch style {
        case .wide:
            ZStack {
                // Under the toolbar.
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22))
                // Behind the title and synopsis.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.4), location: 0.42),
                        .init(color: .clear, location: 0.72),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.4),
                        .init(color: .black.opacity(0.6), location: 0.78),
                        .init(color: .black.opacity(0.92), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .card:
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.35), location: 0.5),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension View {
    /// Fades the bottom of a full-width header into whatever is below it, so
    /// it ends softly in light and dark appearance alike.
    public func heroBottomFade(_ fraction: CGFloat = 0.12) -> some View {
        mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 1 - fraction),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// Page dots under a carousel; the current page is a longer pill.
public struct PageDots: View {
    private let count: Int
    private let index: Int
    private let onSelect: (Int) -> Void

    public init(count: Int, index: Int, onSelect: @escaping (Int) -> Void) {
        self.count = count
        self.index = index
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { page in
                Capsule()
                    .fill(.white.opacity(page == index ? 1 : 0.45))
                    .frame(width: page == index ? 20 : 7, height: 7)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { onSelect(page) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.2), in: Capsule())
        .animation(.smooth(duration: 0.3), value: index)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(index + 1, count - 1))
            case .decrement: onSelect(max(index - 1, 0))
            @unknown default: break
            }
        }
    }
}
