#if os(macOS)
import DesignSystem
import PlaybackEngine
import PlayerFeature
import SwiftUI

/// The full player over the Mac's main window: the video, or Now Playing
/// for music. It fills the window (and the screen in full screen, F or
/// ⌃⌘F); Esc or the close button returns to the library, pausing video.
struct MacPlayerOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlayerView(onClose: { model.dismissPlayer() })
            .environment(\.colorScheme, .dark)
            .background(Palette.playerBackground)
            .frame(minWidth: 480, minHeight: 300)
    }
}
#endif
