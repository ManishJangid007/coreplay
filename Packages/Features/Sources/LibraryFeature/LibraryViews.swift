import DesignSystem
import MediaLibrary
import MusicFeature
import SwiftUI
import VideoFeature

/// Library sections, for the Mac sidebar and the iPhone tabs.
public enum LibrarySection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case artists, albums, songs, genres, composers, playlists
    case movies, tvShows, homeVideos
    case sources

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .genres: "Genres"
        case .composers: "Composers"
        case .playlists: "Playlists"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .homeVideos: "Home Videos"
        case .sources: "Sources"
        }
    }

    public var systemImage: String {
        switch self {
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .genres: "guitars"
        case .composers: "music.quarternote.3"
        case .playlists: "music.note.list"
        case .movies: "film"
        case .tvShows: "tv"
        case .homeVideos: "video"
        case .sources: "externaldrive"
        }
    }

    public static let music: [LibrarySection] = [.artists, .albums, .songs, .genres, .composers, .playlists]
    public static let videos: [LibrarySection] = [.movies, .tvShows, .homeVideos]
}

/// A single library section.
public struct LibrarySectionView: View {
    private let section: LibrarySection

    public init(section: LibrarySection) {
        self.section = section
    }

    public var body: some View {
        switch section {
        case .artists:
            MusicCategoryView(category: .artists)
        case .albums:
            MusicCategoryView(category: .albums)
        case .songs:
            MusicCategoryView(category: .songs)
        case .genres:
            MusicCategoryView(category: .genres)
        case .movies:
            MoviesView()
        case .tvShows:
            TVShowsView()
        case .homeVideos:
            HomeVideosView()
        case .sources:
            SourcesView()
        case .playlists:
            PlaylistsView()
        case .composers:
            ComposersView()
        }
    }
}

/// A list of sections, used for the Videos and Library tabs on iPhone.
public struct LibraryIndexView: View {
    private let title: String
    private let sections: [LibrarySection]

    public init(title: String, sections: [LibrarySection]) {
        self.title = title
        self.sections = sections
    }

    public var body: some View {
        List(sections) { section in
            NavigationLink {
                LibrarySectionView(section: section)
            } label: {
                Label(section.title, systemImage: section.systemImage)
            }
        }
        .navigationTitle(title)
    }
}
