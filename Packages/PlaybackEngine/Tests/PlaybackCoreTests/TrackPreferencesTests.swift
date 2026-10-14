import Foundation
import Testing
@testable import PlaybackCore

@Suite("Starting tracks and remembered options")
struct TrackPreferencesTests {
    // A Japanese film with English and Japanese audio, and four subtitle tracks.
    let audio = [
        MediaTrack(id: "a1", kind: .audio, name: "Japanese", languageCode: "jpn", isSelected: true),
        MediaTrack(id: "a2", kind: .audio, name: "Commentary", languageCode: "eng"),
        MediaTrack(id: "a3", kind: .audio, name: "English", languageCode: "eng"),
    ]
    let subtitles = [
        MediaTrack(id: "s1", kind: .subtitle, name: "English (Forced)", languageCode: "en"),
        MediaTrack(id: "s2", kind: .subtitle, name: "English SDH", languageCode: "en"),
        MediaTrack(id: "s3", kind: .subtitle, name: "English", languageCode: "en"),
        MediaTrack(id: "s4", kind: .subtitle, name: "French", languageCode: "fre"),
    ]

    @Test func audioInYourLanguageSkippingCommentary() {
        let english = TrackPreferences(audioLanguage: "en")
        #expect(english.audioChoice(from: audio) == .track("a3"))
        #expect(TrackPreferences(audioLanguage: "ja").audioChoice(from: audio) == .keep)
        #expect(TrackPreferences(audioLanguage: "de").audioChoice(from: audio) == .keep)
        #expect(TrackPreferences.automatic.audioChoice(from: audio) == .keep)
    }

    @Test func subtitlesWhenTheAudioIsInAnotherLanguage() {
        let preferences = TrackPreferences(subtitles: .foreignAudio, subtitleLanguage: "en")
        // Japanese audio: full English subtitles, not SDH, not forced.
        #expect(preferences.subtitleChoice(from: subtitles, audio: audio[0], appLanguage: "en") == .track("s3"))
        // English audio: just the forced lines.
        #expect(preferences.subtitleChoice(from: subtitles, audio: audio[2], appLanguage: "en") == .track("s1"))
        // English audio and no forced track: off.
        var noForced = subtitles.filter { !$0.isForced }
        noForced[0].isSelected = true
        #expect(preferences.subtitleChoice(from: noForced, audio: audio[2], appLanguage: "en") == .off)
        // The app's language stands in when none is chosen.
        let french = TrackPreferences(subtitles: .foreignAudio)
        #expect(french.subtitleChoice(from: subtitles, audio: audio[0], appLanguage: "fr") == .track("s4"))
    }

    @Test func alwaysAndOff() {
        #expect(TrackPreferences(subtitles: .always, subtitleLanguage: "en").subtitleChoice(from: subtitles, audio: audio[2], appLanguage: "en") == .track("s3"))
        // Only SDH in that language: SDH it is.
        let sdhOnly = [MediaTrack(id: "x", kind: .subtitle, name: "English SDH", languageCode: "en")]
        #expect(TrackPreferences(subtitles: .always, subtitleLanguage: "en").subtitleChoice(from: sdhOnly, audio: nil, appLanguage: "en") == .track("x"))
        // Nothing in that language: the file decides.
        #expect(TrackPreferences(subtitles: .always, subtitleLanguage: "de").subtitleChoice(from: subtitles, audio: nil, appLanguage: "en") == .keep)
        var showing = subtitles
        showing[3].isSelected = true
        #expect(TrackPreferences(subtitles: .off).subtitleChoice(from: showing, audio: nil, appLanguage: "en") == .off)
        #expect(TrackPreferences(subtitles: .off).subtitleChoice(from: subtitles, audio: nil, appLanguage: "en") == .keep)
        #expect(TrackPreferences.automatic.subtitleChoice(from: subtitles, audio: nil, appLanguage: "en") == .keep)
    }

    @Test func settingsListTheAppsLanguagesFirst() {
        let languages = TrackPreferences.commonLanguages(first: ["hi-IN", "en"])
        #expect(languages.prefix(2) == ["hi", "en"])
        #expect(Set(languages).count == languages.count)
    }

    // MARK: Remembered options

    @Test func optionsAreRememberedPerFile() {
        var store = FileOptionsStore()
        let library = PlaybackItem(url: URL(filePath: "/Movies/Heat.mkv"), kind: .video, libraryID: UUID())
        let loose = PlaybackItem(url: URL(filePath: "/Downloads/clip.mkv"), kind: .video)
        let options = FileOptions(audioLanguage: "en", subtitlesOff: true, subtitleDelay: 0.5, transform: VideoTransform(rotation: .quarter))
        store.set(options, for: FileOptionsStore.key(for: library))
        #expect(store.options(for: FileOptionsStore.key(for: library)) == options)
        #expect(store.options(for: FileOptionsStore.key(for: loose)) == nil)
        #expect(FileOptionsStore.key(for: loose).hasPrefix("file:"))
        #expect(options.needsVLC)
        #expect(options.choosesTracks)
        #expect(!FileOptions(transform: VideoTransform(rotation: .half)).needsVLC)
        // Back to nothing chosen: forgotten.
        store.set(FileOptions(), for: FileOptionsStore.key(for: library))
        #expect(store.count == 0)
    }

    @Test func oldestFilesAreForgottenFirst() throws {
        var store = FileOptionsStore()
        for index in 0..<(FileOptionsStore.capacity + 5) {
            store.set(FileOptions(audioDelay: 0.1), for: "file:\(index)")
        }
        #expect(store.count == FileOptionsStore.capacity)
        #expect(store.options(for: "file:0") == nil)
        #expect(store.options(for: "file:\(FileOptionsStore.capacity + 4)") != nil)
        // Touching a file keeps it.
        store.set(FileOptions(audioDelay: 0.2), for: "file:5")
        store.set(FileOptions(audioDelay: 0.1), for: "file:new")
        #expect(store.options(for: "file:5") != nil)
        #expect(store.options(for: "file:6") == nil)
        let decoded = try JSONDecoder().decode(FileOptionsStore.self, from: JSONEncoder().encode(store))
        #expect(decoded == store)
    }
}
