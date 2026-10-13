import PlaybackCore
import QuartzCore

#if canImport(UIKit)
import UIKit
public typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit
public typealias PlatformView = NSView
#endif

/// The view every engine renders video into.
///
/// One instance lives as long as the `PlaybackController`; SwiftUI surfaces
/// borrow it (see `VideoSurface`), so presenting the player again never forces
/// the engine to rebuild its video output.
///
/// AVPlayerEngine installs an `AVPlayerLayer`; VLCKitEngine hands the view to
/// VLC as its drawable and VLC adds its own subview. The view keeps the
/// player layer sized to its bounds, so SwiftUI layout, rotation and
/// full-screen transitions just work.
public final class PlatformVideoView: PlatformView, VideoOutputHost {
    /// A layer an engine installed (AVPlayerLayer). Kept filling the bounds.
    var managedLayer: CALayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let managedLayer {
                hostLayer.addSublayer(managedLayer)
                layoutManagedContent()
            }
        }
    }

    #if canImport(UIKit)
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isAccessibilityElement = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var hostLayer: CALayer { layer }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutManagedContent()
    }
    #elseif canImport(AppKit)
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var hostLayer: CALayer {
        if layer == nil { wantsLayer = true }
        return layer!
    }

    public override func layout() {
        super.layout()
        layoutManagedContent()
    }

    public override var isOpaque: Bool { true }
    #endif

    private func layoutManagedContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        managedLayer?.frame = bounds
        CATransaction.commit()
    }

    /// Removes anything an engine left behind (its player layer, or the
    /// subview VLC added). Call only after the engine has stopped.
    func removeEngineContent() {
        managedLayer = nil
        for subview in subviews {
            subview.removeFromSuperview()
        }
    }
}
