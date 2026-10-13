import SwiftUI

/// Colours for controls drawn over video and artwork backgrounds, or on
/// ordinary system backgrounds.
public enum ControlAppearance: Sendable {
    /// White on dark backgrounds (Now Playing, video).
    case onDark
    /// System colours (mini player, Mac playback bar).
    case standard

    var track: Color {
        switch self {
        case .onDark: Palette.tertiaryOnDark
        case .standard: Color.secondary.opacity(0.25)
        }
    }

    func fill(isActive: Bool) -> Color {
        switch self {
        case .onDark: isActive ? Palette.primaryOnDark : Palette.secondaryOnDark
        case .standard: isActive ? Color.primary : Color.secondary
        }
    }

    var label: Color {
        switch self {
        case .onDark: Palette.secondaryOnDark
        case .standard: Color.secondary
        }
    }
}

/// The Apple Music / TV-style scrubber: a thin capsule that thickens while
/// dragged, with elapsed and remaining time underneath.
///
/// Optional extras for video: small gaps at chapter starts (with a detent
/// haptic on iPhone as the thumb crosses one), and a preview drawn above the
/// thumb while dragging, or above the pointer while hovering on the Mac.
///
/// It's adjustable with VoiceOver (swipe up/down skips 10 seconds) and gives a
/// light haptic when a drag starts and ends on iPhone.
public struct PlaybackScrubber<Preview: View>: View {
    public typealias Appearance = ControlAppearance

    private let position: Double
    private let duration: Double?
    private let elapsedText: String
    private let remainingText: String
    private let accessibilityValueText: String
    private let appearance: ControlAppearance
    private let showsLabels: Bool
    private let markers: [Double]
    private let previewWidth: CGFloat
    private let preview: ((Double) -> Preview)?
    private let onScrubStart: () -> Void
    private let onScrub: (Double) -> Void
    private let onScrubEnd: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0
    @State private var hoverFraction: Double?

    /// - Parameters:
    ///   - position: Current position in seconds.
    ///   - duration: Length in seconds; `nil` for live streams (scrubbing disabled).
    ///   - markers: Chapter starts, in seconds.
    ///   - previewWidth: Width of the preview content.
    ///   - preview: What to show above the thumb for a time, in seconds.
    ///   - onScrubEnd: Called with the position to seek to when the drag ends.
    public init(
        position: Double,
        duration: Double?,
        elapsedText: String,
        remainingText: String,
        accessibilityValue: String,
        appearance: ControlAppearance = .onDark,
        showsLabels: Bool = true,
        markers: [Double] = [],
        previewWidth: CGFloat,
        onScrubStart: @escaping () -> Void = {},
        onScrub: @escaping (Double) -> Void = { _ in },
        onScrubEnd: @escaping (Double) -> Void,
        @ViewBuilder preview: @escaping (Double) -> Preview
    ) {
        self.position = position
        self.duration = duration
        self.elapsedText = elapsedText
        self.remainingText = remainingText
        self.accessibilityValueText = accessibilityValue
        self.appearance = appearance
        self.showsLabels = showsLabels
        self.markers = markers
        self.previewWidth = previewWidth
        self.preview = preview
        self.onScrubStart = onScrubStart
        self.onScrub = onScrub
        self.onScrubEnd = onScrubEnd
    }

    private var isScrubbable: Bool {
        (duration ?? 0) > 0
    }

    private var fraction: Double {
        if isDragging { return dragFraction }
        guard let duration, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Chapter starts as fractions of the length.
    private var markerFractions: [Double] {
        guard let duration, duration > 0 else { return [] }
        return markers.map { $0 / duration }.filter { $0 > 0.002 && $0 < 0.998 }
    }

    /// Which chapter the thumb is in while dragging, for detent haptics.
    private var dragSegment: Int {
        guard isDragging else { return -1 }
        return markerFractions.filter { $0 <= dragFraction }.count
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(appearance.track)
                    Capsule().fill(appearance.fill(isActive: isDragging))
                        .frame(width: width * fraction)
                }
                .mask {
                    ChapterGapMask(fractions: markerFractions)
                }
                .frame(height: isDragging ? 10 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width), including: isScrubbable ? .all : .none)
                #if os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location) where isScrubbable:
                        hoverFraction = Double(min(max(location.x / width, 0), 1))
                    default:
                        hoverFraction = nil
                    }
                }
                #endif
                .overlay(alignment: .bottomLeading) {
                    previewOverlay(width: width)
                }
            }
            .frame(height: 22)

            if showsLabels {
                HStack {
                    Text(elapsedText)
                    Spacer()
                    Text(remainingText)
                }
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(appearance.label)
            }
        }
        .animation(Motion.quick, value: isDragging)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: isDragging)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: dragSegment) { old, new in
            old >= 0 && new >= 0
        }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityAdjustableAction { direction in
            guard let duration, duration > 0 else { return }
            switch direction {
            case .increment:
                onScrubEnd(min(position + 10, duration))
            case .decrement:
                onScrubEnd(max(position - 10, 0))
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func previewOverlay(width: CGFloat) -> some View {
        if let preview, let duration, duration > 0,
           let inspected = isDragging ? dragFraction : hoverFraction {
            let half = previewWidth / 2
            let centre = min(max(inspected * width, half), max(width - half, half))
            preview(inspected * duration)
                .frame(width: previewWidth)
                .offset(x: centre - half, y: -26)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onScrubStart()
                }
                dragFraction = Double(min(max(value.location.x / width, 0), 1))
                onScrub(dragFraction * (duration ?? 0))
            }
            .onEnded { value in
                let final = Double(min(max(value.location.x / width, 0), 1))
                dragFraction = final
                isDragging = false
                onScrubEnd(final * (duration ?? 0))
            }
    }
}

public extension PlaybackScrubber where Preview == EmptyView {
    /// A scrubber without previews (music, the Mac playback bar).
    init(
        position: Double,
        duration: Double?,
        elapsedText: String,
        remainingText: String,
        accessibilityValue: String,
        appearance: ControlAppearance = .onDark,
        showsLabels: Bool = true,
        markers: [Double] = [],
        onScrubStart: @escaping () -> Void = {},
        onScrub: @escaping (Double) -> Void = { _ in },
        onScrubEnd: @escaping (Double) -> Void
    ) {
        self.position = position
        self.duration = duration
        self.elapsedText = elapsedText
        self.remainingText = remainingText
        self.accessibilityValueText = accessibilityValue
        self.appearance = appearance
        self.showsLabels = showsLabels
        self.markers = markers
        self.previewWidth = 0
        self.preview = nil
        self.onScrubStart = onScrubStart
        self.onScrub = onScrub
        self.onScrubEnd = onScrubEnd
    }
}

/// White everywhere except thin gaps at chapter starts, used as a mask.
private struct ChapterGapMask: View {
    let fractions: [Double]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            guard !fractions.isEmpty else { return }
            context.blendMode = .destinationOut
            for fraction in fractions {
                let x = fraction * size.width
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
            }
        }
    }
}

/// Play / pause with the SF Symbol replace transition.
public struct PlayPauseButton: View {
    private let isPlaying: Bool
    private let pointSize: CGFloat
    private let action: () -> Void

    public init(isPlaying: Bool, pointSize: CGFloat = 34, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.pointSize = pointSize
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: pointSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: pointSize * 1.6, height: pointSize * 1.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
        #endif
    }
}

/// A borderless transport control (skip, previous, next…).
public struct TransportButton: View {
    private let systemImage: String
    private let label: String
    private let pointSize: CGFloat
    private let action: () -> Void
    @State private var bounce = 0

    public init(_ label: String, systemImage: String, pointSize: CGFloat = 26, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.pointSize = pointSize
        self.action = action
    }

    public var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: pointSize, weight: .semibold))
                .symbolEffect(.bounce, value: bounce)
                .frame(width: pointSize * 1.8, height: pointSize * 1.8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Empty states in the style of Apple's apps.
public struct EmptyStateView: View {
    private let title: String
    private let systemImage: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ title: String, systemImage: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
