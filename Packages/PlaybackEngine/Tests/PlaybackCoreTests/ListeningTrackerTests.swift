import Foundation
import Testing
@testable import PlaybackCore

@Suite("Play counting")
struct ListeningTrackerTests {
    /// Plays `seconds` of an item in two-second samples, starting at `from`.
    private func play(_ tracker: inout ListeningTracker, id: UUID, duration: TimeInterval?, from: TimeInterval = 0, seconds: TimeInterval) -> Int {
        var counted = 0
        var position = from
        if tracker.update(itemID: id, position: position, duration: duration, isPlaying: true) { counted += 1 }
        while position < from + seconds {
            position += 2
            if tracker.update(itemID: id, position: position, duration: duration, isPlaying: true) { counted += 1 }
        }
        return counted
    }

    @Test func countsAfterHalfOfAShortSong() {
        var tracker = ListeningTracker()
        let id = UUID()
        #expect(play(&tracker, id: id, duration: 200, seconds: 98) == 0)
        #expect(play(&tracker, id: id, duration: 200, from: 98, seconds: 4) == 1)
        #expect(tracker.hasCounted)
    }

    @Test func longSongsCountAfterFourMinutes() {
        var tracker = ListeningTracker()
        let id = UUID()
        #expect(play(&tracker, id: id, duration: 1_200, seconds: 238) == 0)
        #expect(play(&tracker, id: id, duration: 1_200, from: 238, seconds: 4) == 1)
    }

    @Test func countsOnlyOncePerPlay() {
        var tracker = ListeningTracker()
        #expect(play(&tracker, id: UUID(), duration: 100, seconds: 100) == 1)
    }

    @Test func seekingIsNotListening() {
        var tracker = ListeningTracker()
        let id = UUID()
        _ = tracker.update(itemID: id, position: 0, duration: 300, isPlaying: true)
        #expect(tracker.update(itemID: id, position: 200, duration: 300, isPlaying: true) == false)
        #expect(tracker.listenedTime == 0)
    }

    @Test func pausedTimeIsNotListening() {
        var tracker = ListeningTracker()
        let id = UUID()
        _ = tracker.update(itemID: id, position: 10, duration: 100, isPlaying: false)
        #expect(tracker.update(itemID: id, position: 12, duration: 100, isPlaying: false) == false)
        #expect(tracker.listenedTime == 0)
    }

    @Test func veryShortItemsNeverCount() {
        var tracker = ListeningTracker()
        #expect(play(&tracker, id: UUID(), duration: 20, seconds: 20) == 0)
    }

    @Test func newItemResets() {
        var tracker = ListeningTracker()
        _ = play(&tracker, id: UUID(), duration: 100, seconds: 40)
        let next = UUID()
        _ = tracker.update(itemID: next, position: 0, duration: 100, isPlaying: true)
        #expect(tracker.listenedTime == 0)
        #expect(tracker.itemID == next)
    }

    @Test func repeatOneCountsAgain() {
        var tracker = ListeningTracker()
        let id = UUID()
        #expect(play(&tracker, id: id, duration: 60, seconds: 58) == 1)
        // The same item starts over from the beginning.
        #expect(play(&tracker, id: id, duration: 60, from: 0, seconds: 40) == 1)
    }

    @Test func unknownDurationUsesFourMinutes() {
        var tracker = ListeningTracker()
        let id = UUID()
        #expect(play(&tracker, id: id, duration: nil, seconds: 236) == 0)
        #expect(play(&tracker, id: id, duration: nil, from: 236, seconds: 6) == 1)
    }
}
