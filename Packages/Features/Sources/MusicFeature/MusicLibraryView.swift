import DesignSystem
import MediaLibrary
import SwiftData
import SwiftUI

/// The Music tab on iPhone and iPad: the library's categories, then
/// Recently Added, like the Library tab in Music.
public struct MusicLibraryView: View {
    public enum Category: String, CaseIterable, Identifiable, Hashable {
        case artists, albums, songs, genres

        public var id: Self { self }

        public var title: String {
            switch self {
            case .artists: "Artists"
            case .albums: "Albums"
            case .songs: "Songs"
            case .genres: "Genres"
            }
        }

        public var systemImage: String {
            switch self {
            case .artists: "music.mic"
            case .albums: "square.stack"
            case .songs: "music.note"
            case .genres: "guitars"
            }
        }
    }

    @Query(MusicLibraryView.recentlyAdded) private var recentAlbums: [Album]

    private static var recentlyAdded: FetchDescriptor<Album> {
        var descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\Album.dateAdded, order: .reverse)])
        descriptor.fetchLimit = 12
        return descriptor
    }
    private let extraRows: [ExtraRow]

    /// A row the app adds below the categories (Playlists, Sources…).
    public struct ExtraRow: Identifiable {
        public let id: String
        public let title: String
        public let systemImage: String
        public let destination: AnyView

        public init<Destination: View>(_ title: String, systemImage: String, @ViewBuilder destination: () -> Destination) {
            self.id = title
            self.title = title
            self.systemImage = systemImage
            self.destination = AnyView(destination())
        }
    }

    public init(extraRows: [ExtraRow] = []) {
        self.extraRows = extraRows
    }

    public var body: some View {
        List {
            Section {
                ForEach(Category.allCases) { category in
                    NavigationLink {
                        MusicCategoryView(category: category)
                    } label: {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
                ForEach(extraRows) { row in
                    NavigationLink {
                        row.destination
                    } label: {
                        Label(row.title, systemImage: row.systemImage)
                    }
                }
            }
            if !recentAlbums.isEmpty {
                Section {
                    AlbumGrid(albums: recentAlbums)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Recently Added")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Music")
    }
}

/// The view for one music category, used by the iPhone list and the Mac sidebar.
public struct MusicCategoryView: View {
    private let category: MusicLibraryView.Category

    public init(category: MusicLibraryView.Category) {
        self.category = category
    }

    public var body: some View {
        switch category {
        case .artists: ArtistsView()
        case .albums: AlbumsView()
        case .songs: SongsView()
        case .genres: GenresView()
        }
    }
}
