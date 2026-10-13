import SwiftUI

/// Cover Flow, as the iPod and iTunes had it: artwork in a row, the one in
/// the middle facing you and the rest turned away like records on a shelf,
/// each with a reflection. Scrolling glides and settles on a cover; the
/// arrow keys step one at a time; clicking the middle cover opens it.
///
/// An alternative to grids that people choose; grids stay the default.
public struct CoverFlowView<Item: Identifiable & Hashable, Artwork: View>: View {
    private let items: [Item]
    private let aspectRatio: CGFloat
    private let title: (Item) -> String
    private let subtitle: (Item) -> String?
    private let artwork: (Item) -> Artwork
    private let onOpen: (Item) -> Void

    @State private var centered: Item.ID?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - aspectRatio: Width over height of the artwork (1 for albums, 2:3 for posters).
    ///   - artwork: The artwork for an item, filling the frame it's given.
    ///   - onOpen: Called when the middle cover is clicked or Return is pressed.
    public init(
        _ items: [Item],
        aspectRatio: CGFloat = 1,
        title: @escaping (Item) -> String,
        subtitle: @escaping (Item) -> String? = { _ in nil },
        onOpen: @escaping (Item) -> Void,
        @ViewBuilder artwork: @escaping (Item) -> Artwork
    ) {
        self.items = items
        self.aspectRatio = aspectRatio
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.onOpen = onOpen
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = coverWidth(in: proxy.size)
            let height = width / aspectRatio
            let centeredIndex = centered.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -width * 0.45) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            cover(item, width: width, height: height)
                                .zIndex(-Double(abs(index - centeredIndex)))
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max((proxy.size.width - width) / 2, 0), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .scrollPosition(id: $centered, anchor: .center)
                .scrollClipDisabled()
                .frame(height: height * 1.42)
                labels(centeredIndex)
                Spacer(minLength: 0)
            }
        }
        .background {
            LinearGradient(colors: [Color(white: 0.16), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(1)
            return .handled
        }
        .onKeyPress(.return) {
            if let item = items.first(where: { $0.id == centered }) ?? items.first {
                onOpen(item)
            }
            return .handled
        }
        .onAppear {
            if centered == nil {
                centered = items.first?.id
            }
            isFocused = true
        }
    }

    private func coverWidth(in size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.38
        let byHeight = max(size.height - 150, 120) / 1.42 * aspectRatio
        return max(min(byWidth, byHeight, 400), 80)
    }

    private func cover(_ item: Item, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 2) {
            artwork(item)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            // The reflection on the glossy floor.
            artwork(item)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .scaleEffect(x: 1, y: -1)
                .frame(height: height * 0.4, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: width)
        .visualEffect { content, geometry in
            let frame = geometry.frame(in: .scrollView(axis: .horizontal))
            let visible = geometry.bounds(of: .scrollView(axis: .horizontal)) ?? frame
            // How far from the middle, in cover widths, -1…1.
            let distance = max(-1, min(1, (frame.midX - visible.midX) / max(width * 0.55, 1)))
            return content
                .rotation3DEffect(.degrees(-distance * 62), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
                .scaleEffect(1 - abs(distance) * 0.14, anchor: .top)
                .offset(x: distance * width * 0.16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if centered == item.id {
                onOpen(item)
            } else {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.1)) {
                    centered = item.id
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title(item)))
        .accessibilityValue(Text(subtitle(item) ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(item) }
    }

    private func labels(_ index: Int) -> some View {
        let item = items.indices.contains(index) ? items[index] : nil
        return VStack(spacing: 4) {
            Text(item.map(title) ?? " ")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(item.flatMap(subtitle) ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityHidden(true)
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = centered.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let next = min(max(current + delta, 0), items.count - 1)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.1)) {
            centered = items[next].id
        }
    }
}
