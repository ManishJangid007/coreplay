import Foundation
import PlaybackCore
import Testing
@testable import MediaLibrary

/// Songs carry their ReplayGain values to the player.
@Suite("ReplayGain lookup")
struct ReplayGainLookupTests {
    /// The parity suite's FLAC: track −6 dB (peak 0.5), album −4 dB (peak 0.6).
    static let sample = URL(filePath: #filePath)
        .deletingLastPathComponent() // MediaLibraryTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MediaLibrary
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
        .appending(path: "Tests/ParitySamples/tone-replaygain.flac")

    @Test func readsTheValuesFromTags() async throws {
        try #require(FileManager.default.fileExists(atPath: Self.sample.path(percentEncoded: false)), "parity sample missing")
        let values = try #require(await ReplayGainLookup.values(at: Self.sample))
        #expect(values == ReplayGainValues(trackGain: -6, trackPeak: 0.5, albumGain: -4, albumPeak: 0.6))
    }

    @Test func nothingForStreamsOrMissingFiles() async {
        #expect(await ReplayGainLookup.values(at: URL(string: "https://example.com/song.flac")!) == nil)
        #expect(await ReplayGainLookup.values(at: URL(filePath: "/nonexistent/song.flac")) == nil)
    }
}
