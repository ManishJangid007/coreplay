import DesignSystem
import MediaLibrary
import MusicFeature
import SwiftUI

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

    /// Composers join these with playlists in Milestone 8.
    public static let music: [LibrarySection] = [.artists, .albums, .songs, .genres, .playlists]
    public static let videos: [LibrarySection] = [.movies, .tvShows, .homeVideos]

    fileprivate var comingSoonMessage: String {
        switch self {
        case .playlists:
            "Playlists you make, smart playlists and imported M3U or XSPF files will appear here."
        case .composers:
            "Composers from your files\u{2019} tags will appear here."
        case .movies:
            "Movies with posters, cast and synopsis arrive in the next update. Until then, your videos are in Home Videos."
        case .tvShows:
            "TV shows grouped by season, with episode stills and watched state, arrive in the next update. Until then, your videos are in Home Videos."
        default:
            ""
        }
    }
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
        case .homeVideos:
            VideosView()
        case .sources:
            SourcesView()
        case .composers, .playlists, .movies, .tvShows:
            EmptyStateView(
                "Coming Soon",
                systemImage: section.systemImage,
                message: section.comingSoonMessage
            )
            .navigationTitle(section.title)
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
