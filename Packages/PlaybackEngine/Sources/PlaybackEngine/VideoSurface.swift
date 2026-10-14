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
