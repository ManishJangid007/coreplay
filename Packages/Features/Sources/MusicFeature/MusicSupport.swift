import DesignSystem
import MediaLibrary
import NowPlaying
import PlaybackCore
import SwiftData
import SwiftUI

/// Plays library songs: Apple Music's Play, Shuffle, Play Next and Play Later.
/// Tapping a song keeps the player where it is (the mini player updates),
/// as in Music.
@MainActor
struct MusicPlayback {
    let library: LibraryManager
    let session: PlaybackSession

    /// Plays `tracks` in order, starting at `start` (or the first one).
    /// Long lists (all songs, say) are trimmed to a window around the chosen
    /// song, so the queue stays quick to build.
    func play(_ tracks: [Track], startingAt start: Track? = nil, shuffled: Bool? = nil) {
        var candidates = tracks
        var startIndex = start.flatMap { start in
            tracks.firstIndex { $0.persistentModelID == start.persistentModelID }
        } ?? 0
        let window = 500
        if candidates.count > window {
            let lower = max(0, min(startIndex - window / 5, candidates.count - window))
            candidates = Array(candidates[lower..<(lower + window)])
            startIndex -= lower
        }
        var items: [PlaybackItem] = []
        var index = 0
        for (offset, track) in candidates.enumerated() {
            guard let item = library.playbackItem(for: track) else { continue }
            if offset <= startIndex {
                index = items.count
            }
            items.append(item)
        }
        guard !items.isEmpty else { return }
        Task {
            await session.play(items, startingAt: index, shuffled: shuffled)
        }
    }

    func shuffle(_ tracks: [Track]) {
        let items = library.playbackItems(for: Array(tracks.shuffled().prefix(500)))
        guard !items.isEmpty else { return }
        Task {
            await session.playShuffled(items)
        }
    }

    func playNext(_ tracks: [Track]) {
        session.playNext(library.playbackItems(for: tracks))
    }

    func playLater(_ tracks: [Track]) {
        session.playLater(library.playbackItems(for: tracks))
    }

    func isCurrent(_ track: Track) -> Bool {
        guard let id = session.currentItem?.libraryID else { return false }
        return track.file?.id == id
    }
}

extension View {
    /// Registers album, artist and genre pages for a navigation stack.
    public func musicDestinations() -> some View {
        navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: Genre.self) { genre in
            GenreDetailView(genre: genre)
        }
    }
}

/// Shown wherever music would be, until a folder has been added.
struct MusicEmptyState: View {
    @Environment(\.appActions) private var actions
    @Environment(LibraryManager.self) private var library

    var body: some View {
        if library.isScanning {
            ContentUnavailableView {
                Label("Adding Your Music", systemImage: "music.note")
            } description: {
                Text("Songs appear here as Coreplay reads your folders.")
            } actions: {
                ProgressView()
            }
        } else {
            EmptyStateView(
                "No Music Yet",
                systemImage: "music.note",
                message: "Add a folder of music and Coreplay will sort it into artists, albums and songs, with artwork from your files.",
                actionTitle: "Add Folder\u{2026}",
                action: { actions.addLibraryFolder() }
            )
        }
    }
}

/// Play / Shuffle buttons, as at the top of an album or a list in Music.
struct PlayShuffleButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .fontWeight(.semibold)
        .frame(maxWidth: 420)
    }
}

/// Play Next, Play Later and friends for one or more songs.
struct TrackMenuItems: View {
    let tracks: [Track]
    var onEditInfo: (() -> Void)?
    var showsGoToAlbum = true
    @Environment(LibraryManager.self) private var library
    @Environment(PlaybackSession.self) private var session

    var body: some View {
        let playback = MusicPlayback(library: library, session: session)
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            playback.playNext(tracks)
        }
        Button("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") {
            playback.playLater(tracks)
        }
        if tracks.count == 1, let track = tracks.first {
            Divider()
            if showsGoToAlbum, let album = track.album {
                NavigationLink(value: album) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
            if let artist = track.artist {
                NavigationLink(value: artist) {
                    Label("Go to Artist", systemImage: "music.mic")
                }
            }
            if let onEditInfo {
                Button("Edit Info\u{2026}", systemImage: "pencil", action: onEditInfo)
            }
        }
    }
}

enum MusicFormat {
    /// "3:41" or "1:02:10".
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "" }
        return PlaybackTimeFormatter.string(from: seconds, referenceDuration: seconds)
    }

    /// "12 songs, 48 minutes" or "1 song, 3 minutes".
    static func summary(songs: Int, seconds: TimeInterval) -> String {
        let songText = songs == 1 ? "1 song" : "\(songs) songs"
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return songText }
        if minutes >= 120 {
            let hours = minutes / 60
            return "\(songText), \(hours) hours"
        }
        return "\(songText), \(minutes == 1 ? "1 minute" : "\(minutes) minutes")"
    }
}
