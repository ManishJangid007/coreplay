#if os(iOS)
import AVFAudio
import Foundation

/// Configures `AVAudioSession` for background playback and reports
/// interruptions (calls, Siri, other apps) and lost routes (headphones
/// unplugged) so the session can pause and resume like Apple's apps.
///
/// Observers use `queue: .main`, so the handlers run on the main actor.
@MainActor
final class AudioSessionController {
    enum Event {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case outputDeviceLost
    }

    var onEvent: ((Event) -> Void)?
    private var observers: [any NSObjectProtocol] = []
    private var isActive = false

    init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { @Sendable [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { @Sendable [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        })
    }

    /// Sets the playback category (plays with the Ring/Silent switch on and in
    /// the background) and activates the session. Video uses the movie
    /// playback mode, which tunes the system for dialogue and AirPlay video.
    func activate(forVideo isVideo: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: isVideo ? .moviePlayback : .default, policy: .default)
            if !isActive {
                try session.setActive(true)
                isActive = true
            }
        } catch {
            // Playback still works in the foreground; nothing useful to show the user.
            print("Coreplay: audio session activation failed: \(error.localizedDescription)")
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // The system deactivated the session; reactivate on the next play.
            isActive = false
            onEvent?(.interruptionBegan)
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            onEvent?(.outputDeviceLost)
        }
    }
}
#endif
