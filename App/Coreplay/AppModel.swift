import Foundation
import MediaLibrary
import Networking
import NowPlaying
import Observation
import PlaybackCore
import PlaybackEngine
import PlayerFeature
import SettingsFeature
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// App-wide state: settings, the playback session, the library, and what's presented.
@MainActor
@Observable
final class AppModel {
    enum ImportMode {
        case files
        case folder
    }

    let settings: AppSettings
    let session: PlaybackSession
    let library: LibraryManager

    /// iOS: the Files picker, for files to play or a folder to add.
    var isFileImporterPresented = false
    var importMode: ImportMode = .files
    /// The full player: a full-screen cover on iPhone and iPad, and on the
    /// Mac a layer over the main window (video and Now Playing stay in the
    /// same window, as in the TV and Music apps).
    var isPlayerPresented = false
    /// iOS: the Settings sheet.
    var isSettingsPresented = false
    /// Open Network Stream.
    var isStreamPanelPresented = false
    /// Shown when nothing in a selection could be played.
    var openErrorMessage: String?

    @ObservationIgnored private var listeningTask: Task<Void, Never>?
    #if os(macOS)
    /// Keeps the display awake while a video plays.
    @ObservationIgnored private var displayActivity: (any NSObjectProtocol)?
    #endif

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.session = PlaybackSession(configuration: settings.engineConfiguration)
        self.library = LibraryManager()
        library.frameSource = FrameGrabber.shared
        let session = self.session
        settings.onEngineConfigurationChange = { configuration in
            session.updateConfiguration(configuration)
        }
        // Songs are levelled with the ReplayGain values in their tags.
        session.replayGainLookup = { url in
            await ReplayGainLookup.values(at: url)
        }
        // Subtitles from OpenSubtitles, when a key is saved in Settings.
        session.onlineSubtitles = OpenSubtitlesProvider.saved()
        let library = self.library
        session.subtitleSearchRequest = { item in
            library.subtitleSearchRequest(for: item)
        }
        // Shares: the player logs in with what's in the Keychain, and logins
        // VLC asked for are kept there when you tick Remember.
        session.controller.networkCredentials = { url in
            let server = NetworkStore.shared.server(for: url)
            return NetworkKeychain.credential(for: url, user: server?.user)
        }
        NetworkLoginPrompt.shared.onRemember = { url, credential in
            NetworkKeychain.save(credential, for: url)
        }
        connectPictureInPicture()
    }

    // MARK: Picture in Picture

    /// The full player steps aside while the video floats, and comes back
    /// when the user returns from the Picture in Picture window.
    private func connectPictureInPicture() {
        let pictureInPicture = session.controller.pictureInPicture
        pictureInPicture.onStart = { [weak self] in
            self?.isPlayerPresented = false
        }
        pictureInPicture.onRestore = { [weak self] in
            guard let self else { return }
            self.isPlayerPresented = true
            // Give the player a moment to appear before the video leaves the floating window.
            try? await Task.sleep(for: .milliseconds(350))
        }
    }

    /// `true` while the video plays in a Picture in Picture window.
    var isInPictureInPicture: Bool {
        session.controller.pictureInPicture.isActive
    }

    // MARK: Library

    /// Starts the library (reconnect sources, scan what changed), play
    /// counting and video progress.
    func startLibrary() {
        library.start()
        startListeningTracker()
    }

    /// iOS shows the Files folder picker; the Mac shows an open panel.
    func addLibraryFolder() {
        #if os(iOS)
        importMode = .folder
        isFileImporterPresented = true
        #else
        presentFolderPanel()
        #endif
    }

    func presentFileImporter() {
        importMode = .files
        isFileImporterPresented = true
    }

    /// Adds picked or dropped folders (and files) to the library.
    func addSources(_ urls: [URL]) {
        var problems: [String] = []
        for url in urls {
            do {
                try library.addSource(at: url)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        if !problems.isEmpty {
            openErrorMessage = problems.joined(separator: "\n")
        }
    }

    /// Counts plays with `ListeningTracker`, saves where videos got to with
    /// `WatchProgressTracker`, and records durations the scanner couldn't
    /// work out, for anything played from the library.
    private func startListeningTracker() {
        guard listeningTask == nil else { return }
        listeningTask = Task { [weak self] in
            var tracker = ListeningTracker()
            var progress = WatchProgressTracker()
            var libraryIDs: [UUID: UUID] = [:] // playback item → library file
            var networkURLs: [UUID: URL] = [:] // playback item → video on a share
            var timedItem: UUID?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let controller = self.session.controller
                let item = controller.currentItem
                if let item, let libraryID = item.libraryID {
                    libraryIDs[item.id] = libraryID
                } else if let item, item.kind == .video, !item.isPreview, NetworkAddress.isShare(item.url) {
                    networkURLs[item.id] = item.url
                }
                if item?.kind != .video,
                   tracker.update(itemID: item?.id, position: controller.currentTime, duration: controller.duration, isPlaying: controller.isPlaying),
                   let libraryID = item?.libraryID {
                    self.library.recordPlay(libraryID: libraryID)
                }
                // Videos from the library: resume positions and watched state.
                // A disc counts only while its film plays, not its menus or extras.
                let videoID = item?.kind == .video && (item?.libraryID != nil || item.map { networkURLs[$0.id] != nil } == true) ? item?.id : nil
                let credits = UpNextPolicy.creditsStart(chapters: controller.chapters, duration: controller.duration)
                let saves = videoID != nil && !controller.isPlayingMainTitle
                    ? []
                    : progress.update(itemID: videoID, position: controller.currentTime, duration: controller.duration, isPlaying: controller.isPlaying, creditsStart: credits)
                for save in saves {
                    if let url = networkURLs[save.itemID] {
                        // Videos on shares: only where to carry on from.
                        if case .resume(let position) = save.outcome {
                            NetworkStore.shared.setResumePosition(position, for: url)
                        } else {
                            NetworkStore.shared.setResumePosition(nil, for: url)
                        }
                        if save.itemID != item?.id {
                            networkURLs[save.itemID] = nil
                        }
                        continue
                    }
                    guard let libraryID = libraryIDs[save.itemID] else { continue }
                    self.library.recordProgress(libraryID: libraryID, position: save.position, duration: save.duration, outcome: save.outcome)
                    if save.itemID != item?.id {
                        libraryIDs[save.itemID] = nil
                    }
                }
                if let item, let libraryID = item.libraryID, timedItem != item.id, controller.isPlayingMainTitle,
                   let duration = controller.duration {
                    timedItem = item.id
                    self.library.noteDuration(duration, libraryID: libraryID)
                }
            }
        }
    }

    // MARK: Opening media

    /// Plays files or stream URLs, replacing the queue.
    /// - Parameter securityScoped: `true` for URLs from the Files picker or
    ///   "Open in…", which need security-scoped access while playing.
    func open(_ urls: [URL], securityScoped: Bool) {
        // Playlist files (M3U, PLS, XSPF, cue sheets) open as the list they hold.
        // (Only files: a stream's .pls or .m3u link goes to VLC, which follows it.)
        let playlists = urls.filter { $0.isFileURL && PlaylistFile.format(of: $0) != nil }
        if !playlists.isEmpty {
            openPlaylists(playlists, securityScoped: securityScoped)
            return
        }
        // Folders: a DVD or Blu-ray plays as the disc; any other folder plays
        // what's in it, as in VLC.
        var expanded: [URL] = []
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if url.isFileURL, MediaFileTypes.isFolder(url), DiscLayout.disc(at: url) == nil {
                expanded += MediaFileTypes.mediaFiles(in: url)
            } else {
                #if os(macOS)
                expanded.append(discFolderAccess(for: url))
                #else
                expanded.append(url)
                #endif
            }
        }
        let candidates = expanded.filter { url in
            !url.isFileURL || MediaFileTypes.isFolder(url) || MediaFileTypes.isLikelyPlayable(url)
        }
        guard !candidates.isEmpty else {
            if !urls.isEmpty {
                openErrorMessage = urls.count == 1
                    ? "\u{201C}\(urls[0].lastPathComponent)\u{201D} doesn\u{2019}t look like audio or video."
                    : "None of those files look like audio or video."
            }
            return
        }
        let items = candidates.map { url in
            var item = PlaybackItem(url: url, requiresSecurityScope: securityScoped && url.isFileURL)
            // A video on a share carries on where it was left.
            if item.kind == .video, NetworkAddress.isShare(url) {
                item.startPosition = NetworkStore.shared.resumePosition(for: url)
            }
            return item
        }
        let firstKind = items.first?.kind
        Task {
            await session.play(items)
        }
        presentPlayer(expectingVideo: firstKind != .audio)
    }

    /// Reads playlist files and plays what they list, in order.
    private func openPlaylists(_ urls: [URL], securityScoped: Bool) {
        var items: [PlaybackItem] = []
        var unreadable = 0
        for url in urls {
            let isScoped = securityScoped && url.startAccessingSecurityScopedResource()
            defer {
                if isScoped { url.stopAccessingSecurityScopedResource() }
            }
            guard let entries = try? PlaylistFile.entries(at: url) else {
                unreadable += 1
                continue
            }
            items += entries.map(\.playbackItem)
        }
        guard !items.isEmpty else {
            openErrorMessage = unreadable > 0
                ? "Coreplay couldn\u{2019}t read \u{201C}\(urls[0].lastPathComponent)\u{201D}."
                : "\u{201C}\(urls[0].lastPathComponent)\u{201D} doesn\u{2019}t list anything to play."
            return
        }
        #if os(macOS)
        grantAccessIfNeeded(to: items)
        #endif
        let firstKind = items.first?.kind
        Task {
            await session.play(items)
        }
        presentPlayer(expectingVideo: firstKind != .audio)
    }

    #if os(macOS)
    /// Folders the user let Coreplay into (for playlists and DVDs), open for the rest of the session.
    @ObservationIgnored private var grantedFolders: [URL] = []

    /// An IFO file opened by itself plays its DVD, which needs the VIDEO_TS
    /// folder around it. The sandbox only opens that folder once you choose it.
    private func discFolderAccess(for url: URL) -> URL {
        let fileExtension = url.pathExtension.lowercased()
        guard url.isFileURL, fileExtension == "ifo" || fileExtension == "bup" else { return url }
        let folder = url.deletingLastPathComponent()
        guard folder.lastPathComponent.uppercased() == "VIDEO_TS" else { return url }
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) != nil {
            return folder
        }
        let panel = NSOpenPanel()
        panel.message = "To play this DVD, allow Coreplay to open its VIDEO_TS folder."
        panel.prompt = "Allow"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let granted = panel.url else { return url }
        if granted.startAccessingSecurityScopedResource() {
            grantedFolders.append(granted)
        }
        return granted
    }

    /// A playlist names files Coreplay may not be allowed to open (the app
    /// only gets the playlist itself). Asks once for their folder.
    private func grantAccessIfNeeded(to items: [PlaybackItem]) {
        let blocked = items.map(\.url).filter { $0.isFileURL && !FileManager.default.isReadableFile(atPath: $0.path(percentEncoded: false)) }
        guard let first = blocked.first else { return }
        // The deepest folder holding every unreadable file.
        var folder = first.deletingLastPathComponent()
        while !blocked.allSatisfy({ $0.path(percentEncoded: false).hasPrefix(folder.path(percentEncoded: false)) }), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        let panel = NSOpenPanel()
        panel.message = "To play this playlist, allow Coreplay to open the folder its files are in."
        panel.prompt = "Allow"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let granted = panel.url else { return }
        if granted.startAccessingSecurityScopedResource() {
            grantedFolders.append(granted)
        }
    }
    #endif

    /// Plays an address from Open Network Stream, and keeps it in the recent list.
    func openStream(_ url: URL) {
        NetworkStore.shared.noteStream(url)
        open([url], securityScoped: false)
    }

    /// Handles `onOpenURL`: file URLs from Files / Finder, and
    /// `coreplay://open?url=<percent-encoded URL>` for streams.
    func handleOpenURL(_ url: URL) {
        if url.scheme?.lowercased() == "coreplay" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let streamURL = URL(string: target) else { return }
            open([streamURL], securityScoped: false)
        } else {
            open([url], securityScoped: url.isFileURL)
        }
    }

    /// Shows the full player: video, or Now Playing for audio.
    /// - Parameter expectingVideo: On the Mac, audio opened from Finder keeps
    ///   playing in the playback bar instead of covering the library.
    func presentPlayer(expectingVideo: Bool? = nil) {
        #if os(macOS)
        if expectingVideo == false { return }
        #endif
        if isInPictureInPicture {
            // Bring the video back from its floating window; the restore
            // callback presents the player.
            session.controller.pictureInPicture.stop()
            return
        }
        isPlayerPresented = true
    }

    /// Closes the full player. Video pauses, as in the TV app (unless it's
    /// floating in Picture in Picture); audio plays on.
    func dismissPlayer() {
        if session.controller.hasVideo, !isInPictureInPicture {
            session.pause()
        }
        isPlayerPresented = false
    }

    #if os(macOS)
    /// Video keeps the display awake while it plays, as in QuickTime.
    func updateDisplaySleep(videoIsPlaying: Bool) {
        if videoIsPlaying, displayActivity == nil {
            displayActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "Playing video"
            )
        } else if !videoIsPlaying, let activity = displayActivity {
            ProcessInfo.processInfo.endActivity(activity)
            displayActivity = nil
        }
    }
    #endif

    #if os(macOS)
    /// File ▸ Add Folder to Library… (⇧⌘O).
    func presentFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add to Library"
        panel.message = "Choose folders of music or videos. Coreplay reads them where they are."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            addSources(panel.urls)
        }
    }

    /// Dropped items: folders join the library, files (and DVD and Blu-ray folders) play.
    func handleDrop(_ urls: [URL]) {
        let folders = urls.filter { MediaFileTypes.isFolder($0) && DiscLayout.disc(at: $0) == nil }
        let files = urls.filter { url in !folders.contains(url) }
        if !folders.isEmpty {
            addSources(folders)
        }
        if !files.isEmpty {
            open(files, securityScoped: false)
        }
    }

    /// Playback ▸ Jump to Time… (⌘J).
    func presentJumpToTime() {
        let controller = session.controller
        let alert = NSAlert()
        alert.messageText = "Jump to Time"
        alert.informativeText = "Type a time such as 1:02:03 or 45:10."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = PlaybackTimeFormatter.string(from: controller.currentTime, referenceDuration: controller.duration)
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let seconds = PlaybackTimeFormatter.seconds(from: field.stringValue) else {
            NSSound.beep()
            return
        }
        let target = min(seconds, controller.duration ?? seconds)
        Task { await session.seek(to: target) }
    }

    /// Video ▸ Save Picture to Pictures Folder (⌥⌘S).
    func saveSnapshot() {
        Task {
            do {
                let destination = try await SnapshotSaver.save(session.controller)
                session.announce("Saved to \(destination)")
            } catch {
                openErrorMessage = error.localizedDescription
            }
        }
    }

    /// Subtitles ▸ Add Subtitle File…
    func presentSubtitlePanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Subtitles"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await session.controller.addExternalSubtitle(url: url)
                session.announce("Subtitles Added")
            } catch {
                openErrorMessage = error.localizedDescription
            }
        }
    }

    /// Video ▸ Float on Top: the main window stays above other apps' windows.
    private(set) var isFloatingOnTop = false

    func setFloatingOnTop(_ floats: Bool) {
        isFloatingOnTop = floats
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true || window.isMainWindow {
            window.level = floats ? .floating : .normal
        }
    }

    /// File ▸ Open… (⌘O). Any file can be chosen: if VLC can play it,
    /// Coreplay can. So can a folder: a DVD or Blu-ray folder plays as the
    /// disc, any other folder plays what's in it.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Media"
        panel.message = "Choose files, a disc image, or a DVD or Blu-ray folder."
        panel.prompt = "Play"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            open(panel.urls, securityScoped: false)
        }
    }
    #endif
}

/// Decides which opened files are worth handing to the engines. Pickers allow
/// any file (VLC plays formats no type list would cover); this only filters
/// out obvious non-media. Formats the system doesn't know are declared in
/// Info.plist (UTImportedTypeDeclarations) so "Open in…" and Finder offer Coreplay.
enum MediaFileTypes {
    static func isFolder(_ url: URL) -> Bool {
        url.isFileURL && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// What a folder holds to play, in path order, as VLC plays a folder:
    /// media files, and DVD and Blu-ray folders and images as one item each.
    static func mediaFiles(in folder: URL, limit: Int = 5_000) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        while let url = enumerator.nextObject() as? URL, found.count < limit {
            if isFolder(url) {
                if DiscLayout.kind(ofFolderAt: url) != nil {
                    found.append(url)
                    enumerator.skipDescendants()
                } else if DiscLayout.structureFolders.contains(url.lastPathComponent.uppercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard PlaylistFile.format(of: url) == nil else { continue }
            let format = ContainerFormat(url: url)
            if DiscLayout.imageExtensions.contains(format.fileExtension) {
                if DiscLayout.disc(at: url) != nil {
                    found.append(url)
                }
            } else if format.support != .unknown {
                found.append(url)
            }
        }
        return found.sorted { $0.path(percentEncoded: false).localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending }
    }

    /// Cheap check used to skip obvious non-media (PDFs, images…).
    static func isLikelyPlayable(_ url: URL) -> Bool {
        if ContainerFormat(url: url).support != .unknown {
            return true
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            // Unknown extension: let VLC try.
            return true
        }
        if type.conforms(to: .audiovisualContent) || type.conforms(to: .playlist) {
            return true
        }
        return !(type.conforms(to: .image) || type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .archive))
    }
}
