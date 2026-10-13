import Foundation
import Testing
@testable import PlaybackCore

@Suite("Resume and watched rules")
struct ResumePolicyTests {
    @Test func outcomes() {
        #expect(ResumePolicy.outcome(position: 30, duration: 6_000) == .fromStart)
        #expect(ResumePolicy.outcome(position: 60, duration: 6_000) == .resume(at: 60))
        #expect(ResumePolicy.outcome(position: 5_000, duration: 6_000) == .resume(at: 5_000))
        #expect(ResumePolicy.outcome(position: 5_520, duration: 6_000) == .watched)
        #expect(ResumePolicy.outcome(position: 4_000, duration: nil) == .resume(at: 4_000))
        #expect(ResumePolicy.outcome(position: .nan, duration: 6_000) == .fromStart)
    }

    @Test func startPositions() {
        #expect(ResumePolicy.startPosition(saved: 1_234, duration: 6_000) == 1_234)
        #expect(ResumePolicy.startPosition(saved: 20, duration: 6_000) == nil)
        #expect(ResumePolicy.startPosition(saved: 5_900, duration: 6_000) == nil)
        #expect(ResumePolicy.startPosition(saved: nil, duration: 6_000) == nil)
        #expect(ResumePolicy.progress(position: 1_500, duration: 6_000) == 0.25)
    }
}

@Suite("Watch progress tracking")
struct WatchProgressTrackerTests {
    private let movie = UUID()
    private let episode = UUID()

    @Test func savesEveryTenSecondsWhilePlaying() {
        var tracker = WatchProgressTracker()
        #expect(tracker.update(itemID: movie, position: 0, duration: 6_000, isPlaying: true).isEmpty)
        #expect(tracker.update(itemID: movie, position: 64, duration: 6_000, isPlaying: true).count == 1)
        #expect(tracker.update(itemID: movie, position: 68, duration: 6_000, isPlaying: true).isEmpty)
        let saves = tracker.update(itemID: movie, position: 75, duration: 6_000, isPlaying: true)
        #expect(saves == [WatchProgressTracker.Save(itemID: movie, position: 75, duration: 6_000, outcome: .resume(at: 75))])
    }

    @Test func savesOnPause() {
        var tracker = WatchProgressTracker()
        _ = tracker.update(itemID: movie, position: 100, duration: 6_000, isPlaying: true)
        _ = tracker.update(itemID: movie, position: 112, duration: 6_000, isPlaying: true)
        let saves = tracker.update(itemID: movie, position: 115, duration: 6_000, isPlaying: false)
        #expect(saves.map(\.position) == [115])
        // Still paused, nothing moved: no more saves.
        #expect(tracker.update(itemID: movie, position: 115, duration: 6_000, isPlaying: false).isEmpty)
    }

    @Test func watchedOnceInTheCredits() {
        var tracker = WatchProgressTracker()
        _ = tracker.update(itemID: episode, position: 2_000, duration: 2_600, isPlaying: true)
        let saves = tracker.update(itemID: episode, position: 2_400, duration: 2_600, isPlaying: true)
        #expect(saves.map(\.outcome) == [.watched])
        #expect(tracker.update(itemID: episode, position: 2_450, duration: 2_600, isPlaying: true).isEmpty)
        // The next episode starting doesn't re-save the watched one.
        #expect(tracker.update(itemID: movie, position: 0, duration: 6_000, isPlaying: true).isEmpty)
    }

    @Test func savesTheOldItemWhenReplaced() {
        var tracker = WatchProgressTracker()
        _ = tracker.update(itemID: movie, position: 600, duration: 6_000, isPlaying: true)
        _ = tracker.update(itemID: movie, position: 605, duration: 6_000, isPlaying: true)
        let saves = tracker.update(itemID: episode, position: 0, duration: nil, isPlaying: false)
        #expect(saves == [WatchProgressTracker.Save(itemID: movie, position: 605, duration: 6_000, outcome: .resume(at: 605))])
        // Stopping entirely saves too.
        _ = tracker.update(itemID: episode, position: 90, duration: 2_600, isPlaying: true)
        _ = tracker.update(itemID: episode, position: 95, duration: 2_600, isPlaying: true)
        let final = tracker.update(itemID: nil, position: 0, duration: nil, isPlaying: false)
        #expect(final.map(\.itemID) == [episode])
        #expect(final.map(\.position) == [95])
    }
}
