import SwiftUI

/// A thin progress bar along the bottom of a video still, as in the TV app's
/// Continue Watching row.
public struct StillProgressBar: View {
    private let progress: Double

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                Capsule().fill(.white)
                    .frame(width: max(proxy.size.width * min(max(progress, 0), 1), 4))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 10)
        .padding(.bottom, 9)
        .shadow(color: .black.opacity(0.35), radius: 3)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text(progress.formatted(.percent.precision(.fractionLength(0)))))
    }
}

/// A small outlined label: "4K", "HDR", "Dolby Vision", "5.1", "CC".
public struct MediaBadge: View {
    private let text: String
    private let systemImage: String?

    public init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.secondary, lineWidth: 1))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// The checkmark the TV app puts on watched episodes.
public struct WatchedMark: View {
    public init() {}

    public var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .font(.title3)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .accessibilityLabel(Text("Watched"))
    }
}

/// A horizontal row of items under a bold title, like the shelves on Home.
public struct Shelf<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    content
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

/// A poster for something without one: a frame from the video (or a
/// gradient) behind its title, so grids never show a bare file name.
public struct GeneratedPoster: View {
    private let imageURL: URL?
    private let title: String
    private let subtitle: String?
    private let symbol: String

    public init(imageURL: URL?, title: String, subtitle: String? = nil, symbol: String = "film") {
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: ArtworkShape.poster.cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if let imageURL {
                    ArtworkView(url: imageURL, shape: .poster, maxPixelSize: 600)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.35))
                        .offset(y: -24)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(3)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .foregroundStyle(.white)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: ArtworkShape.poster.cornerRadius, style: .continuous))
            .aspectRatio(ArtworkShape.poster.aspectRatio, contentMode: .fit)
    }
}

/// A large backdrop that fades into the page, for the top of detail pages.
public struct HeroBackdrop: View {
    private let imageURL: URL?
    private let height: CGFloat

    public init(imageURL: URL?, height: CGFloat) {
        self.imageURL = imageURL
        self.height = height
    }

    public var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(colors: [Color(white: 0.3), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                FilledArtwork(url: imageURL, maxPixelSize: 1_600)
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.25), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.45), location: 0.7),
                        .init(color: .black.opacity(0.85), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
    }
}

/// How a library section lays out its artwork: the grid, or Cover Flow.
public enum LibraryLayout: String, CaseIterable, Identifiable, Sendable {
    case grid
    case coverFlow

    public var id: Self { self }

    public var title: String {
        switch self {
        case .grid: "Grid"
        case .coverFlow: "Cover Flow"
        }
    }

    public var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .coverFlow: "rectangle.stack"
        }
    }
}

/// A toolbar control that switches between the grid and Cover Flow.
public struct LibraryLayoutPicker: View {
    @Binding private var layout: String

    /// - Parameter layout: A `LibraryLayout` raw value (usually `@AppStorage`).
    public init(layout: Binding<String>) {
        _layout = layout
    }

    public var body: some View {
        Picker("View", selection: $layout) {
            ForEach(LibraryLayout.allCases) { option in
                Label(option.title, systemImage: option.systemImage)
                    .tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("Show as Grid or Cover Flow")
    }
}
