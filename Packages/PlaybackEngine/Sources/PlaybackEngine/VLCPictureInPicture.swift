internal import VLCKit
import Foundation
import PlaybackCore

// VLCKit 4 offers Picture in Picture when the player's drawable adopts
// `VLCPictureInPictureDrawable` (VLCDrawable.h): libVLC's sample-buffer
// video output then builds an AVPictureInPictureController itself, asks the
// drawable's `mediaController()` about playback, and hands the drawable a
// `VLCPictureInPictureWindowControlling` to start and stop it with.
//
// libVLC calls the drawable from its video output thread, so the two
// protocol methods are nonisolated and touch only the thread-safe relays
// below; everything else happens on the main actor.

/// The view every engine renders into. AVPlayerEngine installs its layer
/// here; for VLC it's the drawable, with the hooks for Picture in Picture.
final class VideoHostView: PlatformVideoView, VLCPictureInPictureDrawable {
    /// Answers VLC's Picture in Picture questions (time, length, playing)
    /// and passes its commands (play, pause, skip) to the controller.
    nonisolated let mediaBridge = PictureInPictureMediaBridge()
    /// Delivers VLC's Picture in Picture window controller to the main actor.
    nonisolated let windowRelay = PictureInPictureWindowRelay()

    nonisolated func mediaController() -> (any VLCPictureInPictureMediaControlling)! {
        mediaBridge
    }

    nonisolated func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)! {
        let relay = windowRelay
        return { window in
            guard let window else { return }
            relay.deliver(VLCPictureInPictureWindow(window))
        }
    }
}

/// VLC's Picture in Picture window controller. Only used on the main actor.
struct VLCPictureInPictureWindow: @unchecked Sendable {
    private let controller: any VLCPictureInPictureWindowControlling

    init(_ controller: any VLCPictureInPictureWindowControlling) {
        self.controller = controller
    }

    var identity: ObjectIdentifier { ObjectIdentifier(controller) }

    @MainActor func start() { controller.startPictureInPicture() }
    @MainActor func stop() { controller.stopPictureInPicture() }
    @MainActor func invalidate() { controller.invalidatePlaybackState() }

    /// `handler` runs on the main actor with `true` when PiP starts and
    /// `false` when it ends.
    @MainActor func onStateChange(_ handler: @escaping @MainActor @Sendable (Bool) -> Void) {
        controller.stateChangeEventHandler = { isStarted in
            Task { @MainActor in handler(isStarted) }
        }
    }
}

/// Hands window controllers from libVLC's thread to the main actor.
final class PictureInPictureWindowRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@MainActor @Sendable (VLCPictureInPictureWindow) -> Void)?

    func setHandler(_ handler: @escaping @MainActor @Sendable (VLCPictureInPictureWindow) -> Void) {
        lock.withLock { self.handler = handler }
    }

    func deliver(_ window: VLCPictureInPictureWindow) {
        let handler = lock.withLock { self.handler }
        Task { @MainActor in handler?(window) }
    }
}

/// What VLC's Picture in Picture asks about playback, answered from a
/// snapshot the controller keeps current, and the commands it sends back.
final class PictureInPictureMediaBridge: NSObject, VLCPictureInPictureMediaControlling, @unchecked Sendable {
    struct Snapshot: Sendable, Equatable {
        var timeMilliseconds: Int64 = 0
        var lengthMilliseconds: Int64 = 0
        var isPlaying = false
        var isSeekable = false
    }

    struct Actions: Sendable {
        var play: @MainActor @Sendable () -> Void
        var pause: @MainActor @Sendable () -> Void
        /// Skips by the given number of seconds, then returns.
        var skip: @MainActor @Sendable (TimeInterval) async -> Void
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()
    private var actions: Actions?

    func update(_ newSnapshot: Snapshot) {
        lock.withLock { snapshot = newSnapshot }
    }

    func setActions(_ newActions: Actions) {
        lock.withLock { actions = newActions }
    }

    private var currentActions: Actions? {
        lock.withLock { actions }
    }

    // MARK: VLCPictureInPictureMediaControlling

    func play() {
        let actions = currentActions
        Task { @MainActor in actions?.play() }
    }

    func pause() {
        let actions = currentActions
        Task { @MainActor in actions?.pause() }
    }

    func seek(by offset: Int64, completion: (() -> Void)!) {
        let actions = currentActions
        let done = UncheckedBlock(completion)
        Task { @MainActor in
            await actions?.skip(TimeInterval(offset) / 1_000)
            done.run()
        }
    }

    func mediaLength() -> Int64 {
        lock.withLock { snapshot.lengthMilliseconds }
    }

    func mediaTime() -> Int64 {
        lock.withLock { snapshot.timeMilliseconds }
    }

    func isMediaSeekable() -> Bool {
        lock.withLock { snapshot.isSeekable }
    }

    func isMediaPlaying() -> Bool {
        lock.withLock { snapshot.isPlaying }
    }
}

/// A completion block from libVLC, called once on the main actor.
private struct UncheckedBlock: @unchecked Sendable {
    private let block: (() -> Void)?

    init(_ block: (() -> Void)?) {
        self.block = block
    }

    func run() {
        block?()
    }
}
