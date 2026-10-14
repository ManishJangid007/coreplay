import DesignSystem
import PlaybackCore
import SwiftUI

/// A DVD player's remote for a disc's menu: the four arrows around Select,
/// laid out like the Apple TV remote's clickpad. The keyboard's arrows and
/// Return do the same.
struct DiscRemote: View {
    let onAction: (DiscNavigation) -> Void

    var body: some View {
        VStack(spacing: 6) {
            arrow(.up, systemImage: "chevron.up")
            HStack(spacing: 6) {
                arrow(.left, systemImage: "chevron.left")
                Button {
                    onAction(.activate)
                } label: {
                    Text("Select")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 76, height: Metrics.playerButtonSize)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                #if os(macOS)
                .help("Select (Return)")
                #endif
                arrow(.right, systemImage: "chevron.right")
            }
            arrow(.down, systemImage: "chevron.down")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Disc Menu Controls"))
    }

    private func arrow(_ action: DiscNavigation, systemImage: String) -> some View {
        GlassIconButton(action.title, systemImage: systemImage, help: "\(action.title) (arrow key)") {
            onAction(action)
        }
    }
}

extension DiscNavigation {
    /// The key that does the same on a keyboard, while a disc's menu shows.
    init?(key: KeyEquivalent) {
        switch key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .return: self = .activate
        default: return nil
        }
    }
}
