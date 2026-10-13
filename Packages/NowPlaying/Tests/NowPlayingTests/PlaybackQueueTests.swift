import Foundation
import PlaybackCore
import Testing
@testable import NowPlaying

/// Deterministic generator so shuffle tests are repeatable.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite("Playback queue")
struct PlaybackQueueTests {
    private func makeItems(_ count: Int) -> [PlaybackItem] {
        (1...count).map { PlaybackItem(url: URL(fileURLWithPath: "/music/\($0).flac"), title: "Song \($0)") }
    }

    private func titles(_ items: [PlaybackItem]) -> [String] {
        items.map(\.title)
    }

    @Test func startsAtRequestedIndex() {
        var queue = PlaybackQueue()
        queue.replace(with: makeItems(4), startingAt: 2)
        #expect(queue.currentItem?.title == "Song 3")
        #expect(titles(queue.upNext) == ["Song 4"])
        #expect(queue.hasNext)
        #expect(queue.hasPrevious)
    }

    @Test func advancesAndStopsAtTheEnd() {
        var queue = PlaybackQueue()
        queue.replace(with: makeItems(2))
        #expect(queue.advance(automatic: true)?.title == "Song 2")
        #expect(queue.advance(automatic: true) == nil)
        #expect(queue.currentItem?.title == "Song 2")
        #expect(titles(queue.history) == ["Song 1"])
    }

    @Test func repeatAllWraps() {
        var queue = PlaybackQueue()
        queue.repeatMode = .all
        queue.replace(with: makeItems(2), startingAt: 1)
        #expect(queue.advance(automatic: true)?.title == "Song 1")
        #expect(queue.goBack()?.title == "Song 2")
    }

    @Test func repeatOneReplaysOnlyAutomatically() {
        var queue = PlaybackQueue()
        queue.repeatMode = .one
        queue.replace(with: makeItems(3))
        #expect(queue.advance(automatic: true)?.title == "Song 1")
        #expect(queue.advance(automatic: false)?.title == "Song 2")
    }

    @Test func repeatModeCycles() {
        #expect(PlaybackQueue.RepeatMode.off.next == .all)
        #expect(PlaybackQueue.RepeatMode.all.next == .one)
        #expect(PlaybackQueue.RepeatMode.one.next == .off)
    }

    @Test func goBackAtStartReturnsNil() {
        var queue = PlaybackQueue()
        queue.replace(with: makeItems(3))
        #expect(queue.goBack() == nil)
        #expect(queue.currentItem?.title == "Song 1")
    }

    @Test func playNextAndLater() {
        var queue = PlaybackQueue()
        queue.replace(with: makeItems(2))
        let extra = PlaybackItem(url: URL(fileURLWithPath: "/music/next.mp3"), title: "Next")
        let later = PlaybackItem(url: URL(fileURLWithPath: "/music/later.mp3"), title: "Later")
        queue.playNext([extra])
        queue.playLater([later])
        #expect(titles(queue.upNext) == ["Next", "Song 2", "Later"])
    }

    @Test func playLaterOnEmptyQueueBecomesCurrent() {
        var queue = PlaybackQueue()
        queue.playLater(makeItems(1))
        #expect(queue.currentItem?.title == "Song 1")
    }

    @Test func shuffleKeepsCurrentFirstAndRestores() {
        var queue = PlaybackQueue()
        var generator = SeededGenerator(state: 42)
        let items = makeItems(8)
        queue.replace(with: items, startingAt: 3)
        queue.setShuffle(true, using: &generator)
        #expect(queue.currentItem?.title == "Song 4")
        #expect(queue.currentIndex == 0)
        #expect(Set(titles(queue.items)) == Set(titles(items)))

        queue.setShuffle(false, using: &generator)
        #expect(titles(queue.items) == titles(items))
        #expect(queue.currentItem?.title == "Song 4")
        #expect(queue.currentIndex == 3)
    }

    @Test func jumpRecordsHistory() {
        var queue = PlaybackQueue()
        let items = makeItems(4)
        queue.replace(with: items)
        queue.jump(to: items[2].id)
        #expect(queue.currentItem?.title == "Song 3")
        #expect(titles(queue.history) == ["Song 1"])
    }

    @Test func removesUpcomingButNotCurrent() {
        var queue = PlaybackQueue()
        let items = makeItems(4)
        queue.replace(with: items, startingAt: 1)
        queue.remove(id: items[1].id) // current: ignored
        queue.remove(id: items[0].id) // before current: index shifts
        #expect(queue.currentItem?.title == "Song 2")
        #expect(queue.currentIndex == 0)
        queue.remove(id: items[3].id)
        #expect(titles(queue.upNext) == ["Song 3"])
    }

    @Test func movesWithinUpNext() {
        var queue = PlaybackQueue()
        queue.replace(with: makeItems(5))
        // Up Next is Song 2…5; move "Song 5" (offset 3) to the top (offset 0).
        queue.moveUpNext(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(titles(queue.upNext) == ["Song 5", "Song 2", "Song 3", "Song 4"])
        // Move "Song 5" (offset 0) to the end, SwiftUI-style destination.
        queue.moveUpNext(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(titles(queue.upNext) == ["Song 2", "Song 3", "Song 4", "Song 5"])
        #expect(queue.currentItem?.title == "Song 1")
    }

    @Test func historyIsBounded() {
        var queue = PlaybackQueue()
        queue.replace(with: makeItems(PlaybackQueue.historyLimit + 10))
        while queue.advance(automatic: true) != nil {}
        #expect(queue.history.count == PlaybackQueue.historyLimit)
    }
}
