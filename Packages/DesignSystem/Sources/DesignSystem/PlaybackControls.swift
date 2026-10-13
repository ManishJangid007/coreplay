import SwiftUI

/// The Apple Music / TV-style scrubber: a thin capsule that thickens while
/// dragged, with elapsed and remaining time underneath.
///
/// It's adjustable with VoiceOver (swipe up/down skips 10 seconds) and gives a
/// light haptic when a drag starts and ends on iPhone.
public struct PlaybackScrubber: View {
    public enum Appearance: Sendable {
        /// White on dark backgrounds (Now Playing, video).
        case onDark
        /// System colours (mini player, Mac playback bar).
        case standard
    }

    private let position: Double
    private let duration: Double?
    private let elapsedText: String
    private let remainingText: String
    private let accessibilityValueText: String
    private let appearance: Appearance
    private let showsLabels: Bool
    private let onScrubStart: () -> Void
    private let onScrub: (Double) -> Void
    private let onScrubEnd: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    /// - Parameters:
    ///   - position: Current position in seconds.
    ///   - duration: Length in seconds; `nil` for live streams (scrubbing disabled).
    ///   - onScrubEnd: Called with the position to seek to when the drag ends.
    public init(
        position: Double,
        duration: Double?,
        elapsedText: String,
        remainingText: String,
        accessibilityValue: String,
        appearance: Appearance = .onDark,
        showsLabels: Bool = true,
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

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(trackStyle)
                    Capsule().fill(fillStyle)
                        .frame(width: width * fraction)
                }
                .frame(height: isDragging ? 10 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width), including: isScrubbable ? .all : .none)
            }
            .frame(height: 22)

            if showsLabels {
                HStack {
                    Text(elapsedText)
                    Spacer()
                    Text(remainingText)
                }
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(labelStyle)
            }
        }
        .animation(Motion.quick, value: isDragging)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: isDragging)
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

    private var trackStyle: Color {
        switch appearance {
        case .onDark: Palette.tertiaryOnDark
        case .standard: Color.secondary.opacity(0.25)
        }
    }

    private var fillStyle: Color {
        switch appearance {
        case .onDark: isDragging ? Palette.primaryOnDark : Palette.secondaryOnDark
        case .standard: isDragging ? Color.primary : Color.secondary
        }
    }

    private var labelStyle: Color {
        switch appearance {
        case .onDark: Palette.secondaryOnDark
        case .standard: Color.secondary
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
