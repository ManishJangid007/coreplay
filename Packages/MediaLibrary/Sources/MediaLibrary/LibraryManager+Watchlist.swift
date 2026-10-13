import Foundation
import SwiftData

/// Something on the watchlist: the "+" button on hero slides and show pages,
/// like the TV app's Watchlist.
public enum WatchlistEntry: Identifiable {
    case movie(Video)
    case show(TVShow)

    public var id: String {
        switch self {
        case .movie(let video): Self.key(video)
        case .show(let show): Self.key(show)
        }
    }

    static func key(_ video: Video) -> String { "video:\(video.id.uuidString)" }
    static func key(_ show: TVShow) -> String { "show:\(show.id.uuidString)" }
}

extension LibraryManager {
    static let watchlistKey = "library.watchlist"
    static let watchlistLimit = 200

    public func isOnWatchlist(_ video: Video) -> Bool {
        watchlist.contains(WatchlistEntry.key(video))
    }

    public func isOnWatchlist(_ show: TVShow) -> Bool {
        watchlist.contains(WatchlistEntry.key(show))
    }

    public func toggleWatchlist(_ video: Video) {
        toggleWatchlistKey(WatchlistEntry.key(video))
    }

    public func toggleWatchlist(_ show: TVShow) {
        toggleWatchlistKey(WatchlistEntry.key(show))
    }

    /// The watchlist's movies and shows, newest first. Entries whose movie or
    /// show has left the library are skipped.
    public func watchlistEntries() -> [WatchlistEntry] {
        watchlist.compactMap { key -> WatchlistEntry? in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
            switch parts[0] {
            case "video":
                var descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                return (try? context.fetch(descriptor))?.first.map(WatchlistEntry.movie)
            case "show":
                var descriptor = FetchDescriptor<TVShow>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                return (try? context.fetch(descriptor))?.first.map(WatchlistEntry.show)
            default:
                return nil
            }
        }
    }

    private func toggleWatchlistKey(_ key: String) {
        if let index = watchlist.firstIndex(of: key) {
            watchlist.remove(at: index)
        } else {
            watchlist.insert(key, at: 0)
            if watchlist.count > Self.watchlistLimit {
                watchlist.removeLast(watchlist.count - Self.watchlistLimit)
            }
        }
        if persistsWatchlist {
            UserDefaults.standard.set(watchlist, forKey: Self.watchlistKey)
        }
    }
}
