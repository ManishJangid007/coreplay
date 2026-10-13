import Foundation
import Testing
@testable import MetadataProviders

@Suite("Video names")
struct VideoNameTests {
    private func parse(_ path: String, hint: VideoContentHint = .automatic, duration: TimeInterval? = nil) -> VideoName {
        VideoNameParser.parse(relativePath: path, hint: hint, duration: duration, currentYear: 2026)
    }

    // MARK: Movies

    @Test(arguments: [
        ("Heat (1995).mkv", "Heat", 1995),
        ("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv", "The Matrix", 1999),
        ("Blade Runner 2049 (2017).mkv", "Blade Runner 2049", 2017),
        ("2001 A Space Odyssey (1968).mkv", "2001 A Space Odyssey", 1968),
        ("1917 (2019) 2160p.mkv", "1917", 2019),
        ("Wonder.Woman.1984.2020.2160p.WEB-DL.DDP5.1.Atmos.mkv", "Wonder Woman 1984", 2020),
        ("Amélie [2001] 720p.mp4", "Amélie", 2001),
        ("Mr. Smith Goes to Washington (1939).avi", "Mr. Smith Goes to Washington", 1939),
        ("The_Grand_Budapest_Hotel_2014_1080p.mp4", "The Grand Budapest Hotel", 2014),
    ])
    func movies(path: String, title: String, year: Int) {
        let name = parse(path)
        #expect(name.kind == .movie)
        #expect(name.title == title)
        #expect(name.year == year)
    }

    @Test func folderNamesTheMovie() {
        let name = parse("Movies/Heat (1995)/heat-1080p.mkv")
        #expect(name.kind == .movie)
        #expect(name.title == "Heat")
        #expect(name.year == 1995)
    }

    @Test func editionsAndParts() {
        let extended = parse("Kingdom.of.Heaven.2005.Directors.Cut.1080p.mkv")
        #expect(extended.title == "Kingdom of Heaven")
        #expect(extended.edition == "Director\u{2019}s Cut")

        let plex = parse("Blade Runner (1982) {edition-Final Cut}.mkv")
        #expect(plex.title == "Blade Runner")
        #expect(plex.year == 1982)
        #expect(plex.edition == "Final Cut")

        let part = parse("Lawrence of Arabia (1962) CD2.avi")
        #expect(part.title == "Lawrence of Arabia")
        #expect(part.part == 2)
    }

    @Test func bareYearsNeedFeatureLength() {
        // A home video named after an event and a year.
        #expect(parse("Christmas 2019.mp4", duration: 300).kind == .homeVideo)
        #expect(parse("Holiday 2019/clip.mp4", duration: 120).kind == .homeVideo)
        // The same naming for a feature-length file is a movie.
        let movie = parse("The Matrix 1999.mkv", duration: 8_160)
        #expect(movie.kind == .movie)
        #expect(movie.title == "The Matrix")
        // Brackets make it a movie whatever the length.
        #expect(parse("Short Film (2019).mp4", duration: 600).kind == .movie)
    }

    @Test func moviesSourceWithoutYear() {
        let name = parse("Inception.mkv", hint: .movies)
        #expect(name.kind == .movie)
        #expect(name.title == "Inception")
        #expect(name.year == nil)
        #expect(parse("Inception.mkv").kind == .homeVideo)
    }

    // MARK: Episodes

    @Test func seasonAndEpisode() {
        let name = parse("TV/Breaking Bad/Season 1/Breaking.Bad.S01E02.Cats.in.the.Bag.720p.WEB-DL.mkv")
        #expect(name.kind == .episode)
        #expect(name.showTitle == "Breaking Bad")
        #expect(name.season == 1)
        #expect(name.episode == 2)
        #expect(name.title == "Cats in the Bag")
    }

    @Test(arguments: [
        ("Show.Name.S02E05.mkv", 2, 5, nil as Int?),
        ("Show Name - s1e10 - Title.mkv", 1, 10, nil),
        ("Show.S01E01E02.mkv", 1, 1, 2),
        ("Show.S01E01-E02.mkv", 1, 1, 2),
        ("Show S01E03-04 Title.mkv", 1, 3, 4),
        ("Show - 3x07 - Title.avi", 3, 7, nil),
        ("Show Season 2 Episode 4.mp4", 2, 4, nil),
    ])
    func episodePatterns(path: String, season: Int, episode: Int, last: Int?) {
        let name = parse(path)
        #expect(name.kind == .episode)
        #expect(name.season == season)
        #expect(name.episode == episode)
        #expect(name.lastEpisode == last)
    }

    @Test func showYearAndFolderFallback() {
        let doctor = parse("Doctor.Who.2005.S01E01.Rose.mkv")
        #expect(doctor.showTitle == "Doctor Who")
        #expect(doctor.showYear == 2005)
        #expect(doctor.title == "Rose")

        let bare = parse("Firefly/S01E01.mkv")
        #expect(bare.showTitle == "Firefly")
        #expect(bare.title == "")

        let office = parse("The Office S01-S09/The.Office.US.S01E01.Pilot.mkv")
        #expect(office.showTitle == "The Office US")
    }

    @Test func seasonFolderNumbering() {
        let numbered = parse("The Wire/Season 3/05 - Straight and True.mkv")
        #expect(numbered.kind == .episode)
        #expect(numbered.showTitle == "The Wire")
        #expect(numbered.season == 3)
        #expect(numbered.episode == 5)
        #expect(numbered.title == "Straight and True")

        let specials = parse("Sherlock/Specials/Episode 1 - The Abominable Bride.mkv")
        #expect(specials.season == 0)
        #expect(specials.episode == 1)
        #expect(specials.showTitle == "Sherlock")
    }

    @Test func animeAbsoluteNumbers() {
        let name = parse("[SubGroup] Cowboy Bebop - 05 [1080p].mkv")
        #expect(name.kind == .episode)
        #expect(name.showTitle == "Cowboy Bebop")
        #expect(name.season == 1)
        #expect(name.episode == 5)
    }

    @Test func resolutionsAreNotEpisodes() {
        #expect(parse("Holiday 1280x720.mp4").kind == .homeVideo)
    }

    // MARK: Home videos

    @Test(arguments: ["IMG_2019.MOV", "VID_20240101_123456.mp4", "PXL_20240315_101500123.mp4", "GOPR0042.MP4", "2024-01-01 12.34.56.mov", "Birthday party.mp4"])
    func homeVideos(path: String) {
        #expect(parse(path).kind == .homeVideo)
    }

    @Test func hintsWin() {
        #expect(parse("Heat (1995).mkv", hint: .homeVideos).kind == .homeVideo)
        let episode = parse("Show/Pilot.mkv", hint: .tvShows)
        #expect(episode.kind == .episode)
        #expect(episode.showTitle == "Show")
        #expect(episode.title == "Pilot")
        #expect(parse("Show.S01E01.mkv", hint: .movies).kind == .movie)
    }

    @Test func seasonFolderNames() {
        #expect(VideoNameParser.seasonNumber(folder: "Season 1") == 1)
        #expect(VideoNameParser.seasonNumber(folder: "Season 01 (2008)") == 1)
        #expect(VideoNameParser.seasonNumber(folder: "S02") == 2)
        #expect(VideoNameParser.seasonNumber(folder: "Series 4") == 4)
        #expect(VideoNameParser.seasonNumber(folder: "Specials") == 0)
        #expect(VideoNameParser.seasonNumber(folder: "Series of Unfortunate Events") == nil)
        #expect(VideoNameParser.seasonNumber(folder: "Sherlock") == nil)
    }
}
