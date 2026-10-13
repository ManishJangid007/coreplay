import AVFoundation
import AVKit
import Foundation
import Observation
import PlaybackCore

/// Picture in Picture for whichever engine is playing.
///
/// - AVFoundation: an `AVPictureInPictureController` on the engine's player
///   layer. On iPhone and iPad it also starts by itself when the app goes to
///   the background during a video.
/// - VLC: the controller VLCKit 4 builds around its sample-buffer video
///   output, delivered through `VideoHostView` once the video is showing.
///
/// The app shows a PiP button while `isPossible`, hides its own player when
/// PiP starts (`onStart`), and presents it again when the user returns from
/// the PiP window (`onRestore`).
@MainActor
@Observable
public final class PictureInPicture {
    /// The current video can move into a floating window right now.
    public private(set) var isPossible = false
    public private(set) var isActive = false

    /// PiP is starting: the app can hide its full player (video keeps playing).
    @ObservationIgnored public var onStart: (@MainActor () -> Void)?
    /// The user asked to go back to the app from the PiP window. Present the
    /// player; PiP ends once this returns.
    @ObservationIgnored public var onRestore: (@MainActor () async -> Void)?
    /// PiP ended without asking for the app (the window was closed).
    @ObservationIgnored public var onClose: (@MainActor () -> Void)?

    /// Whether this device can show Picture in Picture at all.
    public static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    @ObservationIgnored private var avController: AVPictureInPictureController?
    @ObservationIgnored private weak var avLayer: AVPlayerLayer?
    @ObservationIgnored private var avObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private let avDelegate = PictureInPictureDelegate()
    @ObservationIgnored private var vlcWindow: VLCPictureInPictureWindow?
    @ObservationIgnored private var isRestoring = false

    init() {
        avDelegate.owner = self
    }

    // MARK: Control

    public func start() {
        guard isPossible, !isActive else { return }
        if let avController {
            avController.startPictureInPicture()
        } else if let vlcWindow {
            isActive = true
            onStart?()
            vlcWindow.start()
        }
    }

    public func stop() {
        guard isActive else { return }
        if let avController {
            avController.stopPictureInPicture()
        } else if let vlcWindow {
            vlcWindow.stop()
        }
    }

    public func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    // MARK: Sources (called by the controller)

    /// The AVFoundation engine's layer is showing.
    func use(playerLayer: AVPlayerLayer) {
        if avController != nil, avLayer === playerLayer { return }
        reset()
        let controller = AVPictureInPictureController(contentSource: .init(playerLayer: playerLayer))
        controller.delegate = avDelegate
        #if os(iOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        avController = controller
        avLayer = playerLayer
        let controllerID = ObjectIdentifier(controller)
        avObservations = [
            controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { @Sendable [weak self] _, change in
                let possible = change.newValue ?? false
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentAVController(controllerID) else { return }
                    self.isPossible = possible
                }
            },
            controller.observe(\.isPictureInPictureActive, options: [.new]) { @Sendable [weak self] _, change in
                let active = change.newValue ?? false
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentAVController(controllerID) else { return }
                    self.isActive = active
                }
            },
        ]
    }

    private func isCurrentAVController(_ id: ObjectIdentifier) -> Bool {
        avController.map { ObjectIdentifier($0) } == id
    }

    /// VLC's video output is ready for Picture in Picture.
    func use(vlcWindow window: VLCPictureInPictureWindow) {
        if let vlcWindow, vlcWindow.identity == window.identity { return }
        if avController != nil {
            // A late callback from a VLC output while AVFoundation plays.
            return
        }
        vlcWindow = window
        isPossible = true
        window.onStateChange { [weak self] isStarted in
            self?.vlcStateChanged(isStarted: isStarted)
        }
    }

    /// The engine went away (or another one is taking over).
    func reset() {
        if isActive {
            avController?.stopPictureInPicture()
            vlcWindow?.stop()
        }
        for observation in avObservations {
            observation.invalidate()
        }
        avObservations.removeAll()
        avController?.delegate = nil
        avController = nil
        avLayer = nil
        vlcWindow = nil
        isPossible = false
        isActive = false
        isRestoring = false
    }

    /// VLC's window needs to know playback changed (play/pause, seeks).
    func playbackChanged() {
        vlcWindow?.invalidate()
    }

    // MARK: Events

    private func vlcStateChanged(isStarted: Bool) {
        let wasActive = isActive
        isActive = isStarted
        if !isStarted, wasActive {
            // VLC doesn't say whether the user closed the window or asked to
            // go back to the app; bring the player back either way.
            Task { await self.onRestore?() }
        }
    }

    fileprivate func willStart() {
        // Report it at once, so nothing pauses the video while the window animates out.
        isActive = true
        onStart?()
    }

    fileprivate func didStop() {
        isActive = false
        if !isRestoring {
            onClose?()
        }
        isRestoring = false
    }

    fileprivate func failedToStart() {
        isActive = false
        onClose?()
    }

    fileprivate func restoreUserInterface() async -> Bool {
        isRestoring = true
        await onRestore?()
        return true
    }
}

/// AVKit's delegate callbacks, forwarded to `PictureInPicture`. AVKit calls
/// them on the main thread; the methods are nonisolated so they satisfy the
/// protocol whether or not the SDK marks it as main-actor isolated.
@MainActor
private final class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate {
    weak var owner: PictureInPicture?

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            owner?.willStart()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            owner?.didStop()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        MainActor.assumeIsolated {
            owner?.failedToStart()
        }
    }

    nonisolated func pictureInPictureControllerRestoreUserInterfaceForPictureInPictureStop(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        await restore()
    }

    private func restore() async -> Bool {
        guard let owner else { return true }
        return await owner.restoreUserInterface()
    }
}
