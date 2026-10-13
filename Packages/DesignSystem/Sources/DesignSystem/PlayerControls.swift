import SwiftUI

// Controls drawn over video and Now Playing, in the style of Apple's own
// players: plain SF Symbols for transport, Liquid Glass circles and
// capsules for the buttons around the edges, and thin capsule sliders.
// Every button keeps a 44-point (40 on the Mac) hit area so icons never
// look squeezed.

public extension Metrics {
    /// Hit area of an icon button in a player.
    static var playerButtonSize: CGFloat {
        #if os(macOS)
        40
        #else
        44
        #endif
    }

    /// Symbol size inside player buttons.
    static let playerSymbolSize: CGFloat = 17
}

/// The symbol inside a player button, sized and centred in its hit area.
public struct PlayerIcon: View {
    private let systemImage: String
    private let size: CGFloat

    public init(_ systemImage: String, size: CGFloat = Metrics.playerButtonSize) {
        self.systemImage = systemImage
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Metrics.playerSymbolSize * size / Metrics.playerButtonSize, weight: .semibold))
            .imageScale(.medium)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .contentShape(Circle())
    }
}

/// An icon button with no chrome of its own, for use inside a `GlassControlGroup`.
public struct PlayerIconButton: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let action: () -> Void
    @State private var isHovering = false

    public init(_ title: String, systemImage: String, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PlayerIcon(systemImage)
                .background {
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.12 : 0))
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
        #if os(macOS)
        .help(help ?? title)
        #endif
    }
}

/// A single round Liquid Glass button, like the close button in the TV app's player.
public struct GlassIconButton: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PlayerIcon(systemImage)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(title))
        #if os(macOS)
        .help(help ?? title)
        #endif
    }
}

/// Buttons sharing one Liquid Glass capsule, like the TV app's player.
public struct GlassControlGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 2, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

public extension View {
    /// Styles a `Menu` so it shows only its label (no bezel on the Mac),
    /// for menus inside player controls.
    func playerMenuStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }

    /// A soft shadow that keeps white symbols readable over bright video.
    func overVideoShadow() -> some View {
        shadow(color: .black.opacity(0.35), radius: 10, y: 1)
    }
}

/// A thin capsule slider that thickens while dragged, matching the scrubber.
/// Used for volume and picture settings.
public struct CapsuleSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let neutral: Double?
    private let appearance: ControlAppearance
    private let label: String
    private let step: Double
    private let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    /// - Parameters:
    ///   - neutral: Draws a tick at the "unchanged" value and fills from it.
    ///   - step: How far VoiceOver's adjust gestures move the value.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        neutral: Double? = nil,
        appearance: ControlAppearance = .onDark,
        label: String,
        step: Double? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.neutral = neutral
        self.appearance = appearance
        self.label = label
        self.step = step ?? (range.upperBound - range.lowerBound) / 20
        self.onEditingChanged = onEditingChanged
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let current = fraction(of: value)
            let origin = neutral.map(fraction(of:)) ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(appearance.track)
                Capsule().fill(appearance.fill(isActive: isDragging))
                    .frame(width: width * abs(current - origin))
                    .offset(x: width * min(current, origin))
                if neutral != nil {
                    Capsule()
                        .fill(appearance.label)
                        .frame(width: 2, height: isDragging ? 14 : 10)
                        .offset(x: width * origin - 1)
                }
            }
            .frame(height: isDragging ? 10 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let fraction = Double(min(max(gesture.location.x / width, 0), 1))
                        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 22)
        .animation(Motion.quick, value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(Int((fraction(of: value) * 100).rounded())) percent"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// The capsule slider standing up, for equalizer bands.
public struct VerticalCapsuleSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let label: String
    private let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    public init(value: Binding<Double>, in range: ClosedRange<Double>, label: String, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self._value = value
        self.range = range
        self.label = label
        self.onEditingChanged = onEditingChanged
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    public var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let middle = 0.5
            ZStack(alignment: .bottom) {
                Capsule().fill(Palette.tertiaryOnDark)
                Capsule().fill(isDragging ? Palette.primaryOnDark : Palette.secondaryOnDark)
                    .frame(height: height * abs(fraction - middle))
                    .offset(y: -height * min(fraction, middle))
                Capsule()
                    .fill(Palette.secondaryOnDark)
                    .frame(width: isDragging ? 14 : 10, height: 2)
                    .offset(y: -height * middle + 1)
            }
            .frame(width: isDragging ? 10 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let fraction = 1 - Double(min(max(gesture.location.y / height, 0), 1))
                        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .animation(Motion.quick, value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) decibels"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// Choices shown as a row of capsules, the selected one filled white
/// (speeds, fit and fill, deinterlacing).
public struct CapsuleChoices<Value: Hashable>: View {
    private let options: [Value]
    private let selection: Value
    private let title: (Value) -> String
    private let onSelect: (Value) -> Void

    public init(_ options: [Value], selection: Value, title: @escaping (Value) -> String, onSelect: @escaping (Value) -> Void) {
        self.options = options
        self.selection = selection
        self.title = title
        self.onSelect = onSelect
    }

    public var body: some View {
        WrappingHStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? Color.black : Palette.primaryOnDark)
                        .background(isSelected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
public struct WrappingHStack: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let usedWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
