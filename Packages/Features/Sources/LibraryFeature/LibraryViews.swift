import DesignSystem
import SwiftUI

/// Library sections. Each shows a proper empty state until the library and
/// scanner arrive (Music in Milestone 3, Movies and TV in Milestone 4,
/// Sources in Milestones 3 and 7).
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

    fileprivate var emptyMessage: String {
        switch self {
        case .artists, .albums, .songs, .genres, .composers:
            "Music from the folders you add in Sources will appear here, with artwork from your files."
        case .playlists:
            "Playlists you create, smart playlists and imported M3U or XSPF files will appear here."
        case .movies:
            "Movies from your folders will appear here with posters, cast and synopsis."
        case .tvShows:
            "TV shows will appear here grouped by season, with episode stills and watched state."
        case .homeVideos:
            "Other videos will appear here by date, with generated thumbnails."
        case .sources:
            "Add folders, drives and network shares to build your library. Until then, open files directly."
        }
    }
}

/// A single library section.
public struct LibrarySectionView: View {
    @Environment(\.appActions) private var actions
    private let section: LibrarySection

    public init(section: LibrarySection) {
        self.section = section
    }

    public var body: some View {
        EmptyStateView(
            "No \(section.title) Yet",
            systemImage: section.systemImage,
            message: section.emptyMessage,
            actionTitle: "Open Files\u{2026}",
            action: { actions.openFiles() }
        )
        .navigationTitle(section.title)
    }
}

/// A list of sections, used for the Music, Videos and Library tabs on iPhone.
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
