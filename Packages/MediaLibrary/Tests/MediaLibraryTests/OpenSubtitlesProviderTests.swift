import Foundation
import PlaybackCore
import Testing
@testable import MediaLibrary

@Suite("OpenSubtitles provider")
struct OpenSubtitlesProviderTests {
    @Test func languagesAsOpenSubtitlesWritesThem() {
        #expect(OpenSubtitlesProvider.openSubtitlesLanguage("en") == "en")
        #expect(OpenSubtitlesProvider.openSubtitlesLanguage("eng") == "en")
        #expect(OpenSubtitlesProvider.openSubtitlesLanguage("pt-BR") == "pt-br")
        #expect(OpenSubtitlesProvider.openSubtitlesLanguage("por") == "pt-pt")
        #expect(OpenSubtitlesProvider.openSubtitlesLanguage("zh-Hant") == "zh-tw")
        #expect(OpenSubtitlesProvider.openSubtitlesLanguage("chi") == "zh-cn")
    }

    @Test func credentialsTrimAndKnowAboutAccounts() {
        let keyOnly = OpenSubtitlesCredentials(apiKey: "  abc \n")
        #expect(keyOnly.apiKey == "abc")
        #expect(!keyOnly.hasAccount)
        #expect(OpenSubtitlesCredentials(apiKey: "abc", username: " me ", password: "secret").hasAccount)
        #expect(!OpenSubtitlesCredentials(apiKey: "abc", username: "me", password: "").hasAccount)
    }
}
