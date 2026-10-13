import PlaybackCore
import SwiftUI

/// Shows the playing video. Engines render into the controller's long-lived
/// `PlatformVideoView`; each `VideoSurface` borrows that view while it's on
/// screen, so dismissing and re-presenting the player is instant and never
/// rebuilds VLC's video output.
public struct VideoSurface: View {
    private let controller: PlaybackController

    public init(controller: PlaybackController) {
        self.controller = controller
    }

    public var body: some View {
        VideoSurfaceRepresentable(controller: controller)
            .background(Color.black)
            .accessibilityElement()
            .accessibilityLabel(Text(controller.displayTitle.isEmpty ? "Video" : controller.displayTitle))
            .accessibilityAddTraits(.startsMediaSession)
    }
}

/// A container that's showing (or showed) the video, held weakly.
struct WeakVideoContainer {
    weak var view: PlatformView?
}

extension PlaybackController {
    /// Moves the shared video view into `container`, filling it. The newest
    /// surface always wins.
    func mountVideoView(in container: PlatformView) {
        videoContainers.removeAll { $0.view == nil || $0.view === container }
        videoContainers.append(WeakVideoContainer(view: container))
        place(videoView, in: container)
    }

    /// Takes the video view back when `container` goes away and returns it to
    /// the previous surface, if one is still on screen.
    func unmountVideoView(from container: PlatformView) {
        videoContainers.removeAll { $0.view == nil || $0.view === container }
        guard videoView.superview === container else { return }
        videoView.removeFromSuperview()
        if let previous = videoContainers.last?.view {
            place(videoView, in: previous)
        }
    }

    private func place(_ videoView: PlatformVideoView, in container: PlatformView) {
        videoView.removeFromSuperview()
        videoView.frame = container.bounds
        #if canImport(UIKit)
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #elseif canImport(AppKit)
        videoView.autoresizingMask = [.width, .height]
        #endif
        container.addSubview(videoView)
    }
}

#if canImport(UIKit)
private struct VideoSurfaceRepresentable: UIViewRepresentable {
    let controller: PlaybackController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        controller.mountVideoView(in: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.controller.unmountVideoView(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator {
        let controller: PlaybackController

        init(controller: PlaybackController) {
            self.controller = controller
        }
    }
}
#elseif canImport(AppKit)
private struct VideoSurfaceRepresentable: NSViewRepresentable {
    let controller: PlaybackController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        controller.mountVideoView(in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.controller.unmountVideoView(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator {
        let controller: PlaybackController

        init(controller: PlaybackController) {
            self.controller = controller
        }
    }
}
#endif
