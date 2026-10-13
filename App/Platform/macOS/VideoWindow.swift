#if os(macOS)
import NowPlaying
import PlaybackEngine
import PlayerFeature
import SwiftUI

/// The Mac video window: native full screen (F or ⌃⌘F), resizable, and
/// closing it stops the video, as in QuickTime Player.
struct VideoWindow: View {
    static let id = "video"

    @Environment(PlaybackSession.self) private var session
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        PlayerView(onClose: { dismissWindow(id: Self.id) })
            .frame(minWidth: 480, minHeight: 270)
            .navigationTitle(session.controller.displayTitle)
            .onDisappear {
                guard session.controller.hasVideo else { return }
                Task { await session.stop() }
            }
    }
}
#endif
