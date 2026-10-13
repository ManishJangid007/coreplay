import Foundation

/// The TV app's progress rules for videos: resume from where you stopped once
/// you're past the first minute, and count the video as watched from 92%
/// (the end credits) onwards.
public enum ResumePolicy {
    /// Positions before this start again from the beginning.
    public static let minimumPosition: TimeInterval = 60
    /// From this fraction of the running time, the video is watched.
    public static let watchedFraction = 0.92

    public enum Outcome: Hashable, Sendable {
        /// Too early to be worth resuming: start over next time.
        case fromStart
        /// Keep the position: next time starts here.
        case resume(at: TimeInterval)
        /// Watched to the end credits.
        case watched
    }

    public static func outcome(position: TimeInterval, duration: TimeInterval?) -> Outcome {
        guard position.isFinite, position > 0 else { return .fromStart }
        if let duration, duration.isFinite, duration > 0, position >= duration * watchedFraction {
            return .watched
        }
        return position >= minimumPosition ? .resume(at: position) : .fromStart
    }

    /// Where to start a video that was stopped at `position` (`nil`: the beginning).
    public static func startPosition(saved position: TimeInterval?, duration: TimeInterval?) -> TimeInterval? {
        guard let position, case .resume(let at) = outcome(position: position, duration: duration) else { return nil }
        return at
    }

    /// 0…1 for progress bars; `nil` when there's nothing to show.
    public static func progress(position: TimeInterval?, duration: TimeInterval?) -> Double? {
        guard let position, let duration, duration > 0, position > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }
}

/// Decides when the app should save a video's progress while it plays:
/// every ten seconds of playback, as soon as it's paused, when another item
/// replaces it, and once when it crosses into the end credits.
///
/// The app feeds it the controller's state every couple of seconds; it
/// returns the saves to make. Pure value logic, so it's easy to test.
public struct WatchProgressTracker: Sendable {
    public struct Save: Hashable, Sendable {
        public var itemID: UUID
        public var position: TimeInterval
        public var duration: TimeInterval?
        public var outcome: ResumePolicy.Outcome
    }

    /// Seconds of movement between periodic saves.
    public static let saveInterval: TimeInterval = 10

    private var itemID: UUID?
    private var lastPosition: TimeInterval = 0
    private var lastDuration: TimeInterval?
    private var lastSavedPosition: TimeInterval?
    private var wasPlaying = false
    private var reportedWatched = false

    public init() {}

    public mutating func update(itemID newItemID: UUID?, position: TimeInterval, duration: TimeInterval?, isPlaying: Bool) -> [Save] {
        var saves: [Save] = []
        if newItemID != itemID {
            // The previous item was replaced (or stopped): keep where it got to.
            if let itemID, let save = finalSave(for: itemID) {
                saves.append(save)
            }
            itemID = newItemID
            lastPosition = position
            lastDuration = duration
            // Where it starts (a resume position) is already saved.
            lastSavedPosition = position > 0 ? position : nil
            wasPlaying = isPlaying
            reportedWatched = false
            return saves
        }
        guard let itemID else { return saves }
        // Ignore the jump to zero while a new file opens, and seeks to 0 before stopping.
        if position > 0 {
            lastPosition = position
        }
        if let duration, duration > 0 {
            lastDuration = duration
        }
        let outcome = ResumePolicy.outcome(position: lastPosition, duration: lastDuration)
        defer { wasPlaying = isPlaying }

        if outcome == .watched {
            if !reportedWatched {
                reportedWatched = true
                lastSavedPosition = lastPosition
                saves.append(Save(itemID: itemID, position: lastPosition, duration: lastDuration, outcome: .watched))
            }
            return saves
        }
        // Seeking back out of the credits makes it resumable again.
        reportedWatched = false
        let moved = abs(lastPosition - (lastSavedPosition ?? 0))
        let paused = wasPlaying && !isPlaying
        if (paused && moved >= 1) || (isPlaying && moved >= Self.saveInterval) {
            lastSavedPosition = lastPosition
            saves.append(Save(itemID: itemID, position: lastPosition, duration: lastDuration, outcome: outcome))
        }
        return saves
    }

    private func finalSave(for itemID: UUID) -> Save? {
        guard !reportedWatched, lastPosition > 0, lastPosition != lastSavedPosition else { return nil }
        return Save(itemID: itemID, position: lastPosition, duration: lastDuration, outcome: ResumePolicy.outcome(position: lastPosition, duration: lastDuration))
    }
}

/// Grabs still frames from videos: library thumbnails and the "choose a
/// frame" artwork picker. `PlaybackEngine` provides one built on
/// AVFoundation and VLC; the library only sees this protocol.
public protocol VideoFrameSource: Sendable {
    /// JPEG data for the frame at `time` (or a representative frame when
    /// `time` is `nil`), no larger than `maxPixelSize` on its long edge.
    /// `precise` finds the exact frame (slower); otherwise the nearest
    /// keyframe will do, as it does for thumbnails.
    func frameJPEG(from url: URL, at time: TimeInterval?, maxPixelSize: Int, precise: Bool) async -> Data?
}
