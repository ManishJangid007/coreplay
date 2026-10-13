import Foundation
import NowPlaying
import Observation
import PlaybackCore
import SettingsFeature
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// App-wide state: settings, the playback session, and what's presented.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let session: PlaybackSession

    /// iOS: the Files picker.
    var isFileImporterPresented = false
    /// iOS: the full-screen player.
    var isPlayerPresented = false
    /// iOS: the Settings sheet.
    var isSettingsPresented = false
    /// macOS: bumped to ask the main window to open the video window (fallback
    /// for when `openVideoWindow` hasn't been set up yet).
    var videoWindowRequest = 0
    /// Shown when nothing in a selection could be played.
    var openErrorMessage: String?
    #if os(macOS)
    /// Opens the video window. Set by the main window from its `openWindow`
    /// action, which keeps working after that window closes, so files opened
    /// from Finder or the Dock still get a video window.
    @ObservationIgnored var openVideoWindow: (() -> Void)?
    #endif

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.session = PlaybackSession(configuration: settings.engineConfiguration)
        let session = self.session
        settings.onEngineConfigurationChange = { configuration in
            session.updateConfiguration(configuration)
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

    /// Shows the full player (iOS) or the video window (macOS).
    func presentPlayer(expectingVideo: Bool? = nil) {
        #if os(iOS)
        isPlayerPresented = true
        #else
        guard expectingVideo ?? session.controller.hasVideo else { return }
        if let openVideoWindow {
            openVideoWindow()
        } else {
            videoWindowRequest += 1
        }
        #endif
    }

    #if os(macOS)
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
