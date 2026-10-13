import Testing
@testable import MetadataProviders

@Suite("File and folder names")
struct PathMetadataTests {
    @Test func artistAlbumTrackLayout() {
        let path = PathMetadata(relativePath: "Radiohead/OK Computer (1997)/01 Airbag.flac")
        #expect(path.title == "Airbag")
        #expect(path.artist == "Radiohead")
        #expect(path.album == "OK Computer")
        #expect(path.year == 1997)
        #expect(path.trackNumber == 1)
        #expect(path.discNumber == nil)
    }

    @Test func artistDashAlbumFolderWithDiscSubfolder() {
        let path = PathMetadata(relativePath: "Music/Pink Floyd - The Wall [1979]/CD2/03. Hey You.mp3")
        #expect(path.artist == "Pink Floyd")
        #expect(path.album == "The Wall")
        #expect(path.year == 1979)
        #expect(path.discNumber == 2)
        #expect(path.trackNumber == 3)
        #expect(path.title == "Hey You")
    }

    @Test func iTunesDiscTrackFileNames() {
        let path = PathMetadata(relativePath: "The Beatles/The Beatles (White Album)/2-04 Blackbird.m4a")
        #expect(path.discNumber == 2)
        #expect(path.trackNumber == 4)
        #expect(path.title == "Blackbird")
        #expect(path.album == "The Beatles (White Album)")
    }

    @Test func artistDashTitleInAFlatFolder() {
        let path = PathMetadata(relativePath: "Daft Punk - One More Time.mp3")
        #expect(path.artist == "Daft Punk")
        #expect(path.title == "One More Time")
        #expect(path.album == nil)
    }

    @Test func fileNameRepeatsTheFolderArtist() {
        let path = PathMetadata(relativePath: "Bonobo/Migration/04 - Bonobo - Kerala.mp3")
        #expect(path.artist == "Bonobo")
        #expect(path.title == "Kerala")
        #expect(path.trackNumber == 4)
    }

    @Test func numbersThatArePartOfTitlesSurvive() {
        #expect(PathMetadata(relativePath: "7 Seconds.mp3").title == "7 Seconds")
        #expect(PathMetadata(relativePath: "2001 A Space Odyssey/Main Title.mp3").album == "2001 A Space Odyssey")
        #expect(PathMetadata(relativePath: "99 Problems.mp3").trackNumber == 99) // ambiguous; tags win when present
    }

    @Test func leadingYearFolders() {
        let path = PathMetadata(relativePath: "Air/1998 - Moon Safari/01 La Femme d'Argent.flac")
        #expect(path.album == "Moon Safari")
        #expect(path.year == 1998)
        #expect(path.artist == "Air")
    }

    @Test func underscoresBecomeSpaces() {
        let path = PathMetadata(relativePath: "Some_Artist/Some_Album/05_Some_Song.ogg")
        #expect(path.title == "Some Song")
        #expect(path.artist == "Some Artist")
        #expect(path.album == "Some Album")
        #expect(path.trackNumber == 5)
    }

    @Test func extensionHandling() {
        #expect(PathMetadata.removingExtension("Song.flac") == "Song")
        #expect(PathMetadata.removingExtension("Mr. Brightside") == "Mr. Brightside")
        #expect(PathMetadata.removingExtension(".hidden") == ".hidden")
    }
}

@Suite("Name keys")
struct NameNormalizerTests {
    @Test func groupKeysIgnoreCaseAccentsAndSpacing() {
        #expect(NameNormalizer.groupKey("Beyoncé") == NameNormalizer.groupKey("  beyonce "))
        #expect(NameNormalizer.groupKey("Sigur  Rós") == "sigur ros")
        #expect(NameNormalizer.groupKey("ＡＢＣ") == "abc")
    }

    @Test func sortKeysDropLeadingArticles() {
        #expect(NameNormalizer.sortKey("The Beatles") == "beatles")
        #expect(NameNormalizer.sortKey("A Tribe Called Quest") == "tribe called quest")
        #expect(NameNormalizer.sortKey("An Horse") == "horse")
        #expect(NameNormalizer.sortKey("The") == "the")
        #expect(NameNormalizer.sortKey("Theory of a Deadman") == "theory of a deadman")
    }

    @Test func indexLetters() {
        #expect(NameNormalizer.indexLetter(forSortKey: "beatles") == "B")
        #expect(NameNormalizer.indexLetter(forSortKey: "50 cent") == "#")
        #expect(NameNormalizer.indexLetter(forSortKey: "") == "#")
    }
}
