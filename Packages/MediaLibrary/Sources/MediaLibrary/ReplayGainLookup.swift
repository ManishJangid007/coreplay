import Foundation
import MetadataProviders
import PlaybackCore

/// Reads a song's ReplayGain values for the player, just before it plays.
///
/// Tag reading takes a few milliseconds on a local disk. A file that takes
/// longer than `timeout` (a slow network share) plays as it is rather than
/// keeping the song waiting.
public enum ReplayGainLookup {
    public static func values(at url: URL, timeout: Duration = .milliseconds(500)) async -> ReplayGainValues? {
        guard url.isFileURL else { return nil }
        return await withCheckedContinuation { continuation in
            let gate = FirstAnswer(continuation)
            Task.detached(priority: .userInitiated) {
                let isScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if isScoped { url.stopAccessingSecurityScopedResource() }
                }
                guard let tags = try? TagReader.read(url: url), let gain = tags.replayGain else {
                    gate.answer(nil)
                    return
                }
                gate.answer(ReplayGainValues(trackGain: gain.trackGain, trackPeak: gain.trackPeak, albumGain: gain.albumGain, albumPeak: gain.albumPeak))
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                gate.answer(nil)
            }
        }
    }
}

/// Resumes a continuation with the first answer only.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ReplayGainValues?, Never>?

    init(_ continuation: CheckedContinuation<ReplayGainValues?, Never>) {
        self.continuation = continuation
    }

    func answer(_ values: ReplayGainValues?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: values)
    }
}
