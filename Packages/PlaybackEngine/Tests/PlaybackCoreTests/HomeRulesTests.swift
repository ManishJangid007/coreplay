import Foundation
import Testing
@testable import PlaybackCore

@Suite("Up Next at the end credits")
struct UpNextPolicyTests {
    private let episode: TimeInterval = 2_700 // 45 minutes

    @Test func findsTheCreditsChapter() {
        let chapters = [
            Chapter(index: 0, title: "Previously", start: 0, duration: 60),
            Chapter(index: 1, title: "Chapter 2", start: 60, duration: 2_400),
            Chapter(index: 2, title: "End Credits", start: 2_460, duration: 240),
        ]
        #expect(UpNextPolicy.creditsStart(chapters: chapters, duration: episode) == 2_460)
    }

    @Test func ignoresCreditsEarlyInTheEpisode() {
        // Opening credits are not the end credits.
        let chapters = [
            Chapter(index: 0, title: "Opening Credits", start: 0, duration: 90),
            Chapter(index: 1, title: "Story", start: 90, duration: 2_610),
        ]
        #expect(UpNextPolicy.creditsStart(chapters: chapters, duration: episode) == nil)
    }

    @Test func recognisesCreditsTitles() {
        #expect(UpNextPolicy.isCreditsTitle("Credits"))
        #expect(UpNextPolicy.isCreditsTitle("Outro"))
        #expect(UpNextPolicy.isCreditsTitle("Ending"))
        #expect(UpNextPolicy.isCreditsTitle("Abspann"))
        #expect(!UpNextPolicy.isCreditsTitle("The End of the Line"))
        #expect(!UpNextPolicy.isCreditsTitle("Chapter 12"))
    }

    @Test func hiddenBeforeTheOffer() {
        let phase = UpNextPolicy.phase(currentTime: 1_000, duration: episode, creditsStart: nil, autoplays: true)
        #expect(phase == .hidden)
    }

    @Test func countsDownToTheNaturalEndWithoutCredits() {
        let phase = UpNextPolicy.phase(currentTime: episode - 15, duration: episode, creditsStart: nil, autoplays: true)
        #expect(phase == .offering(countdown: UpNextPolicy.Countdown(remaining: 15, total: UpNextPolicy.leadTime)))
    }

    @Test func startsTheNextEpisodeAfterTheCountdownAtTheCredits() {
        let credits: TimeInterval = 2_460
        let early = UpNextPolicy.phase(currentTime: credits + 4, duration: episode, creditsStart: credits, autoplays: true)
        #expect(early == .offering(countdown: UpNextPolicy.Countdown(remaining: 6, total: 10)))
        let done = UpNextPolicy.phase(currentTime: credits + 10, duration: episode, creditsStart: credits, autoplays: true)
        #expect(done == .startNext)
    }

    @Test func waitsForTheViewerWhenAutoplayIsOff() {
        let phase = UpNextPolicy.phase(currentTime: 2_470, duration: episode, creditsStart: 2_460, autoplays: false)
        #expect(phase == .offering(countdown: nil))
    }

    @Test func shortClipsNeverOfferEarly() {
        #expect(UpNextPolicy.phase(currentTime: 110, duration: 120, creditsStart: nil, autoplays: true) == .hidden)
        #expect(UpNextPolicy.offerTime(duration: nil, creditsStart: nil) == nil)
    }

    @Test func countdownFraction() {
        #expect(UpNextPolicy.Countdown(remaining: 10, total: 10).fraction == 0)
        #expect(UpNextPolicy.Countdown(remaining: 5, total: 10).fraction == 0.5)
        #expect(UpNextPolicy.Countdown(remaining: 0, total: 10).fraction == 1)
    }
}

@Suite("Featured picks for the hero carousel")
struct FeaturedPickerTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func days(_ count: Double) -> Date {
        now.addingTimeInterval(-count * 86_400)
    }

    @Test func newArrivalsComeFirstThenWhatYouAreWatching() {
        let candidates = [
            FeaturedPicker.Candidate(id: "old", dateAdded: days(200), hasBackdrop: true),
            FeaturedPicker.Candidate(id: "watching", dateAdded: days(90), lastPlayed: days(1), isInProgress: true),
            FeaturedPicker.Candidate(id: "new-1", dateAdded: days(3)),
            FeaturedPicker.Candidate(id: "new-2", dateAdded: days(1)),
        ]
        let picked = FeaturedPicker.pick(candidates, now: now)
        #expect(picked == ["new-2", "new-1", "watching", "old"])
    }

    @Test func keepsToTheLimitAndNeverRepeats() {
        let candidates = (0..<20).map { FeaturedPicker.Candidate(id: "m\($0)", dateAdded: days(Double($0))) }
        let picked = FeaturedPicker.pick(candidates, limit: 6, now: now)
        #expect(picked.count == 6)
        #expect(Set(picked).count == 6)
        // At most three are featured for being new.
        #expect(Array(picked.prefix(3)) == ["m0", "m1", "m2"])
    }

    @Test func unwatchedAndBackdropsBeforeTheRest() {
        let candidates = [
            FeaturedPicker.Candidate(id: "watched", dateAdded: days(100), isFinished: true, hasBackdrop: true),
            FeaturedPicker.Candidate(id: "frame", dateAdded: days(100)),
            FeaturedPicker.Candidate(id: "backdrop", dateAdded: days(100), hasBackdrop: true),
        ]
        #expect(FeaturedPicker.pick(candidates, now: now) == ["backdrop", "frame", "watched"])
    }

    @Test func skipsItemsWithoutPicturesWhenThereAreEnoughWithThem() {
        let candidates = [
            FeaturedPicker.Candidate(id: "a", dateAdded: days(50)),
            FeaturedPicker.Candidate(id: "b", dateAdded: days(50)),
            FeaturedPicker.Candidate(id: "c", dateAdded: days(50)),
            FeaturedPicker.Candidate(id: "bare", dateAdded: days(1), hasArtwork: false),
        ]
        #expect(!FeaturedPicker.pick(candidates, now: now).contains("bare"))
        // …but a library with nothing pictured still gets a carousel.
        let bare = [FeaturedPicker.Candidate(id: "only", dateAdded: days(1), hasArtwork: false)]
        #expect(FeaturedPicker.pick(bare, now: now) == ["only"])
    }

    @Test func theDailyOrderIsStableForTheDay() {
        let candidates = (0..<12).map { FeaturedPicker.Candidate(id: "m\($0)", dateAdded: days(100)) }
        let first = FeaturedPicker.pick(candidates, now: now)
        let later = FeaturedPicker.pick(candidates, now: now.addingTimeInterval(60))
        #expect(first == later)
        let tomorrow = FeaturedPicker.pick(candidates, now: now.addingTimeInterval(86_400))
        #expect(first != tomorrow)
    }
}
