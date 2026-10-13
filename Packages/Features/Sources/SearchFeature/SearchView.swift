import DesignSystem
import SwiftUI

/// One search across everything, grouped by type, with scopes like Apple
/// Music. Results arrive with the library (Milestone 3); the structure and
/// scopes are in place now.
public struct SearchView: View {
    public enum Scope: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case music = "Music"
        case videos = "Videos"

        public var id: String { rawValue }
    }

    @State private var query = ""
    @State private var scope: Scope = .all

    public init() {}

    public var body: some View {
        Group {
            if query.isEmpty {
                EmptyStateView(
                    "Search Your Library",
                    systemImage: "magnifyingglass",
                    message: "Find artists, albums, songs, movies, shows and home videos."
                )
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: Text("Artists, Albums, Movies and More"))
        .searchScopes($scope) {
            ForEach(Scope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
    }
}
