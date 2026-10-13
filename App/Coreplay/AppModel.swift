import Foundation
import MediaLibrary
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
            var timedItem: UUID?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let controller = self.session.controller
                let item = controller.currentItem
                if let item, let libraryID = item.libraryID {
                    libraryIDs[item.id] = libraryID
                }
                if item?.kind != .video,
                   tracker.update(itemID: item?.id, position: controller.currentTime, duration: controller.duration, isPlaying: controller.isPlaying),
                   let libraryID = item?.libraryID {
                    self.library.recordPlay(libraryID: libraryID)
                }
                // Videos from the library: resume positions and watched state.
                let videoID = item?.kind == .video && item?.libraryID != nil ? item?.id : nil
                for save in progress.update(itemID: videoID, position: controller.currentTime, duration: controller.duration, isPlaying: controller.isPlaying) {
                    guard let libraryID = libraryIDs[save.itemID] else { continue }
                    self.library.recordProgress(libraryID: libraryID, position: save.position, duration: save.duration, outcome: save.outcome)
                    if save.itemID != item?.id {
                        libraryIDs[save.itemID] = nil
                    }
                }
                if let item, let libraryID = item.libraryID, timedItem != item.id, let duration = controller.duration {
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
        let candidates = urls.filter { url in
            !url.isFileURL || MediaFileTypes.isLikelyPlayable(url)
        }
        guard !candidates.isEmpty else {
            if !urls.isEmpty {
                openErrorMessage = urls.count == 1
                    ? "\u{201C}\(urls[0].lastPathComponent)\u{201D} doesn\u{2019}t look like audio or video."
                    : "None of those files look like audio or video."
            }
            return
        }
        let items = candidates
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { PlaybackItem(url: $0, requiresSecurityScope: securityScoped && $0.isFileURL) }
        let firstKind = items.first?.kind
        Task {
            await session.play(items)
        }
        presentPlayer(expectingVideo: firstKind != .audio)
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

    /// Dropped items: folders join the library, files play.
    func handleDrop(_ urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
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

    /// File ▸ Open… (⌘O). Any file can be chosen: if VLC can play it, Coreplay can.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Media"
        panel.prompt = "Play"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
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
