import Foundation
import MediaPlayer

/// Wires `MPRemoteCommandCenter` (Lock Screen, Control Center, AirPods,
/// headphone buttons, CarPlay, Mac media keys) to the playback session.
///
/// Handlers are `@Sendable` and hop to the main actor explicitly, because the
/// system may call them on any thread.
@MainActor
final class RemoteCommandController {
    private var registrations: [(command: MPRemoteCommand, target: Any)] = []

    /// Seconds jumped by the skip commands for video and spoken word.
    nonisolated static let skipInterval: TimeInterval = 15

    func install(for session: PlaybackSession) {
        guard registrations.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        register(center.playCommand) { [weak session] _ in
            Task { @MainActor in session?.play() }
            return .success
        }
        register(center.pauseCommand) { [weak session] _ in
            Task { @MainActor in session?.pause() }
            return .success
        }
        register(center.togglePlayPauseCommand) { [weak session] _ in
            Task { @MainActor in session?.togglePlayPause() }
            return .success
        }
        register(center.stopCommand) { [weak session] _ in
            Task { @MainActor in await session?.stop() }
            return .success
        }
        register(center.nextTrackCommand) { [weak session] _ in
            Task { @MainActor in await session?.next() }
            return .success
        }
        register(center.previousTrackCommand) { [weak session] _ in
            Task { @MainActor in await session?.previous() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        register(center.skipForwardCommand) { [weak session] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? RemoteCommandController.skipInterval
            Task { @MainActor in await session?.skip(by: interval) }
            return .success
        }
        register(center.skipBackwardCommand) { [weak session] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? RemoteCommandController.skipInterval
            Task { @MainActor in await session?.skip(by: -interval) }
            return .success
        }

        register(center.changePlaybackPositionCommand) { [weak session] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in await session?.seek(to: position) }
            return .success
        }

        center.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1, 1.25, 1.5, 2].map { NSNumber(value: $0) }
        register(center.changePlaybackRateCommand) { [weak session] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = event.playbackRate
            Task { @MainActor in await session?.setRate(rate) }
            return .success
        }
    }

    /// Video and spoken word show ±15 s skip buttons; music shows previous/next.
    func update(isVideo: Bool, hasNext: Bool, isSeekable: Bool, hasItem: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = hasItem
        center.pauseCommand.isEnabled = hasItem
        center.togglePlayPauseCommand.isEnabled = hasItem
        center.stopCommand.isEnabled = hasItem
        center.nextTrackCommand.isEnabled = hasItem && hasNext
        center.previousTrackCommand.isEnabled = hasItem
        center.skipForwardCommand.isEnabled = hasItem && isVideo && isSeekable
        center.skipBackwardCommand.isEnabled = hasItem && isVideo && isSeekable
        center.changePlaybackPositionCommand.isEnabled = hasItem && isSeekable
        center.changePlaybackRateCommand.isEnabled = hasItem
    }

    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        registrations.append((command, target))
    }
}
