import AppIntents
import Foundation
import MediaLibrary
import NowPlaying
import PlaybackCore

// Shortcuts and Siri: play a playlist, shuffle your music, play or pause,
// skip, and open a stream. They run in the app, through the same session
// the player uses.

struct PlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays or pauses what Coreplay is playing.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared?.session.togglePlayPause()
        return .result()
    }
}

struct NextItemIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next"
    static let description = IntentDescription("Skips to the next song or episode.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppModel.shared?.session.next()
        return .result()
    }
}

struct PreviousItemIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous"
    static let description = IntentDescription("Goes back to the start, or to the previous song.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppModel.shared?.session.previous()
        return .result()
    }
}

struct ShuffleMusicIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle My Music"
    static let description = IntentDescription("Shuffles every song in your library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppModel.shared else { return .result() }
        let tracks = model.library.allAvailableTracks()
        await model.session.play(model.library.playbackItems(for: tracks), startingAt: 0, shuffled: true)
        return .result()
    }
}

struct PlayPlaylistIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Playlist"
    static let description = IntentDescription("Plays one of your playlists.")

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    @Parameter(title: "Shuffle", default: false)
    var shuffle: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppModel.shared,
              let found = model.library.playlists().first(where: { $0.id == playlist.id }) else { return .result() }
        let items = model.library.playbackItems(for: model.library.tracks(in: found))
        await model.session.play(items, startingAt: 0, shuffled: shuffle)
        return .result()
    }
}

struct OpenStreamIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Network Stream"
    static let description = IntentDescription("Plays a stream address in Coreplay.")
    static let openAppWhenRun = true

    @Parameter(title: "Address")
    var address: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = StreamAddress.url(from: address) else {
            throw $address.needsValueError("That doesn\u{2019}t look like a stream address. What should Coreplay open?")
        }
        AppModel.shared?.openStream(url)
        return .result()
    }
}

struct PlaylistEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static let defaultQuery = PlaylistQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PlaylistQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlaylistEntity] {
        allPlaylists().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlaylistEntity] {
        allPlaylists()
    }

    @MainActor
    private func allPlaylists() -> [PlaylistEntity] {
        (AppModel.shared?.library.playlists() ?? []).map { PlaylistEntity(id: $0.id, name: $0.name) }
    }
}

struct CoreplayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: ["Play \(\.$playlist) in \(.applicationName)", "Play my \(\.$playlist) playlist in \(.applicationName)"],
            shortTitle: "Play Playlist",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: ShuffleMusicIntent(),
            phrases: ["Shuffle my music in \(.applicationName)", "Shuffle \(.applicationName)"],
            shortTitle: "Shuffle My Music",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: ["Pause \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: "Play or Pause",
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: NextItemIntent(),
            phrases: ["Skip in \(.applicationName)", "Next song in \(.applicationName)"],
            shortTitle: "Next",
            systemImageName: "forward"
        )
    }
}
