import Foundation
import Testing
@testable import PlaybackCore

@Suite("ReplayGain and volume")
struct LoudnessTests {
    /// The parity sample's values: track −6 dB (peak 0.5), album −4 dB (peak 0.6).
    let sample = ReplayGainValues(trackGain: -6, trackPeak: 0.5, albumGain: -4, albumPeak: 0.6)

    private func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0005
    }

    @Test func offLeavesEverythingAlone() {
        #expect(ReplayGainSettings.off.scale(for: sample) == 1)
        #expect(ReplayGainSettings.off.gain(for: sample) == 0)
    }

    @Test func trackAndAlbumModes() {
        let track = ReplayGainSettings(mode: .track)
        #expect(track.gain(for: sample) == -6)
        #expect(close(track.scale(for: sample), 0.5012))
        let album = ReplayGainSettings(mode: .album)
        #expect(album.gain(for: sample) == -4)
        #expect(close(album.scale(for: sample), 0.6310))
        // Each falls back on the other's value.
        #expect(track.gain(for: ReplayGainValues(albumGain: -2)) == -2)
        #expect(album.gain(for: ReplayGainValues(trackGain: -3)) == -3)
    }

    @Test func preampAndClipping() {
        // +6 dB of preamp brings −6 dB back to as recorded.
        #expect(close(ReplayGainSettings(mode: .track, preamp: 6).scale(for: sample), 1))
        // A quiet track turned up 6 dB would clip at its 0.9 peak: held at 1/0.9.
        let quiet = ReplayGainValues(trackGain: 6, trackPeak: 0.9)
        #expect(close(ReplayGainSettings(mode: .track).scale(for: quiet), 1 / 0.9))
        #expect(close(ReplayGainSettings(mode: .track, preventsClipping: false).scale(for: quiet), 1.9953))
        #expect(ReplayGainSettings(mode: .track, preamp: 40).preamp == 15)
    }

    @Test func tracksWithoutValuesUseTheFallback() {
        #expect(ReplayGainSettings(mode: .track).scale(for: nil) == 1)
        #expect(close(ReplayGainSettings(mode: .album, fallbackGain: -6).scale(for: ReplayGainValues()), 0.5012))
        // The preamp is for scanned tracks only.
        #expect(ReplayGainSettings(mode: .track, preamp: 3).gain(for: nil) == 0)
    }

    @Test func engineVolumeStaysWithinWhatTheEngineCanDo() {
        #expect(VolumeLimits.engineVolume(chosen: 1, replayGainScale: 1.9953, limit: VolumeLimits.normal) == 1)
        #expect(abs(VolumeLimits.engineVolume(chosen: 1, replayGainScale: 1.9953, limit: VolumeLimits.boosted) - 1.9953) < 0.0001)
        #expect(abs(VolumeLimits.engineVolume(chosen: 0.8, replayGainScale: 0.5, limit: 1) - 0.4) < 0.0001)
        #expect(VolumeLimits.engineVolume(chosen: 1.5, replayGainScale: .nan, limit: 2) == 1.5)
        #expect(VolumeLimits.engineVolume(chosen: -1, replayGainScale: 1, limit: 2) == 0)
        #expect(VolumeLimits.percent(1.5) == "150%")
    }

    @Test func settingsRoundTrip() throws {
        let settings = ReplayGainSettings(mode: .album, preamp: 2.5, fallbackGain: -4, preventsClipping: false)
        let decoded = try JSONDecoder().decode(ReplayGainSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}
