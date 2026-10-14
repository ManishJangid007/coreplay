import PlaybackCore
import QuartzCore
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
    /// the previous surface, if one is still on screen (otherwise it waits in
    /// `VideoParking`, still in a window).
    func unmountVideoView(from container: PlatformView) {
        videoContainers.removeAll { $0.view == nil || $0.view === container }
        guard videoView.superview === container else { return }
        videoView.removeFromSuperview()
        if let previous = videoContainers.last?.view {
            place(videoView, in: previous)
        } else {
            VideoParking.park(videoView)
        }
    }

    private func place(_ videoView: PlatformVideoView, in container: PlatformView) {
        videoView.removeFromSuperview()
        // Laid out by the container (see `VideoContainerView`), not by autoresizing.
        videoView.autoresizingMask = []
        container.addSubview(videoView)
        layoutVideoView(in: container)
    }

    /// Lays the video view out again wherever it's showing (after the
    /// picture is turned, mirrored or magnified).
    func layoutVideoGeometry() {
        guard let container = videoView.superview else { return }
        layoutVideoView(in: container)
    }

    /// Places the video view in `container`: centred, stood on end for a
    /// quarter turn, then turned, mirrored and magnified by the container
    /// layer's sublayer transform. (A layer-backed view's own transform is
    /// AppKit's to manage, so the container's sublayer transform does it,
    /// the same way on both platforms.) A 360° video is never turned: you
    /// look around it instead.
    func layoutVideoView(in container: PlatformView) {
        guard videoView.superview === container, let layer = Self.layer(of: container) else { return }
        let bounds = container.bounds
        // SwiftUI often lays a new container out at zero size first. Shrinking
        // VLC's view to nothing would hand its OpenGL output an empty
        // framebuffer (an assertion failure in VLCKit), so the last real size
        // stays until the container has one.
        guard bounds.width >= 2, bounds.height >= 2 else { return }
        #if canImport(AppKit) && !canImport(UIKit)
        let yUp = !container.isFlipped
        #else
        let yUp = false
        #endif
        let placement = VideoPlacement(
            transform: isSpherical ? .identity : transform,
            zoom: isSpherical ? .none : zoom,
            width: Double(bounds.width),
            height: Double(bounds.height),
            anchorX: Double(layer.anchorPoint.x),
            anchorY: Double(layer.anchorPoint.y),
            yUp: yUp
        )
        let frame = CGRect(
            x: bounds.minX + placement.frame.x,
            y: bounds.minY + placement.frame.y,
            width: placement.frame.width,
            height: placement.frame.height
        )
        if videoView.frame != frame {
            videoView.frame = frame
        }
        let affine = placement.transform
        let sublayerTransform = CATransform3DMakeAffineTransform(CGAffineTransform(
            a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: affine.tx, ty: affine.ty
        ))
        guard !CATransform3DEqualToTransform(layer.sublayerTransform, sublayerTransform) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = sublayerTransform
        CATransaction.commit()
    }

    private static func layer(of view: PlatformView) -> CALayer? {
        #if canImport(UIKit)
        view.layer
        #elseif canImport(AppKit)
        view.wantsLayer = true
        return view.layer
        #endif
    }
}

/// Where a video view waits while no player shows it. VLC's macOS video
/// output draws with OpenGL into the view it's given, and a view outside any
/// window has no framebuffer: VLCKit then fails an assertion
/// (GL_INVALID_FRAMEBUFFER_OPERATION in vout_display_opengl_Prepare) and the
/// app ends. That happened when a video started before the player had
/// slid in, or kept drawing after its view left the screen. So a video view
/// is always in a window: a player's, or this invisible one.
@MainActor
enum VideoParking {
    #if canImport(AppKit) && !canImport(UIKit)
    private static var window: NSWindow?

    static func park(_ view: PlatformView) {
        let window = window ?? makeWindow()
        view.removeFromSuperview()
        view.autoresizingMask = []
        if view.frame.width < 2 || view.frame.height < 2 {
            view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        }
        window.contentView?.addSubview(view)
    }

    private static func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.hasShadow = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary, .fullScreenAuxiliary]
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        window.orderFrontRegardless()
        self.window = window
        return window
    }
    #else
    /// iOS: VLC's output there copes with a view outside a window.
    static func park(_ view: PlatformView) {}
    #endif
}

/// Holds the video view and lays it out whenever its size changes.
final class VideoContainerView: PlatformView {
    weak var controller: PlaybackController?

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        controller?.layoutVideoView(in: self)
    }
    #elseif canImport(AppKit)
    override func layout() {
        super.layout()
        controller?.layoutVideoView(in: self)
    }
    #endif
}

#if canImport(UIKit)
private struct VideoSurfaceRepresentable: UIViewRepresentable {
    let controller: PlaybackController

    func makeUIView(context: Context) -> UIView {
        let container = VideoContainerView()
        container.controller = controller
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
        let container = VideoContainerView()
        container.controller = controller
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.masksToBounds = true
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
