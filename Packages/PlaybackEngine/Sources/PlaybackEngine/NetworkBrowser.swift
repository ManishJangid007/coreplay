import Foundation
import Observation
import PlaybackCore
internal import VLCKit

/// Lists what's in a folder on a share (SMB, FTP, SFTP, NFS, UPnP) with
/// libVLC's directory access: the folder is parsed, and its sub-items are
/// its files and folders. Logins VLC asks for go to `NetworkLoginPrompt`.
@MainActor
public final class NetworkBrowser {
    public static let shared = NetworkBrowser()

    public struct BrowseError: Error, LocalizedError, Equatable, Sendable {
        public enum Reason: Sendable, Equatable {
            case cannotOpen
            case timedOut
        }

        public let reason: Reason
        public let message: String

        public var errorDescription: String? { message }
    }

    /// How long a folder may take (a server waking from sleep can be slow).
    public var timeout: Duration = .seconds(30)

    private var library: VLCLibrary?

    private init() {}

    /// The libVLC instance for browsing and discovery, with the login prompt attached.
    func browsingLibrary() -> VLCLibrary {
        if let library {
            return library
        }
        // VLC hides subtitle files from folder listings by default (it
        // attaches them to the video of the same name, and ignores some file
        // types): list them, so the player can pass them along, and keep
        // hiding pictures and housekeeping files.
        let library = VLCLibrary(options: [
            "--no-video",
            "--no-audio",
            "--no-sub-autodetect-file",
            "--ignore-filetypes=db,nfo,ini,jpg,jpeg,ljpg,gif,png,pgm,pgmyuv,pbm,pam,tga,bmp,pnm,xpm,xcf,pcx,tif,tiff,lbm,sfv,txt,lnk,url,DS_Store",
        ])
        library.setHumanReadableName("Coreplay", withHTTPUserAgent: "Coreplay/1.0")
        NetworkLoginPrompt.shared.attach(to: library)
        self.library = library
        return library
    }

    /// The files and folders in `folder`, folders first, hidden files left out.
    /// - Parameters:
    ///   - credential: A saved login, tried before VLC asks for one.
    ///   - asksForLogin: `false` fails instead of asking (`NetworkLoginPrompt`)
    ///     when the login is missing or wrong.
    public func contents(of folder: URL, credential: NetworkCredential? = nil, asksForLogin: Bool = true) async throws -> [NetworkEntry] {
        let folder = NetworkAddress.withoutLogin(folder)
        let place = NetworkAddress.displayPath(folder)
        guard let media = VLCMedia(url: folder) else {
            throw BrowseError(reason: .cannotOpen, message: "\u{201C}\(place)\u{201D} isn\u{2019}t an address Coreplay can open.")
        }
        for option in credential?.vlcOptions(for: folder) ?? [] {
            media.addOption(option)
        }
        NetworkLoginPrompt.shared.currentAddress = folder
        let started = Date.now
        let status = await FolderRequest().run(media: media, library: browsingLibrary(), interactive: asksForLogin, timeout: timeout)
        switch status {
        case .done:
            break
        case .timeout, nil:
            throw BrowseError(reason: .timedOut, message: "\u{201C}\(place)\u{201D} didn\u{2019}t answer in time. Check that the server is on and reachable.")
        default:
            let detail = NetworkLoginPrompt.shared.error(since: started).map { " \($0)" } ?? ""
            throw BrowseError(reason: .cannotOpen, message: "Couldn\u{2019}t open \u{201C}\(place)\u{201D}.\(detail)")
        }
        return Self.entries(in: media)
    }

    /// Reads a parsed folder's sub-items.
    static func entries(in media: VLCMedia) -> [NetworkEntry] {
        guard let list = media.subitems else { return [] }
        list.lock()
        defer { list.unlock() }
        var entries: [NetworkEntry] = []
        for index in 0..<max(0, list.count) {
            guard let child = list.media(at: UInt(index)), let url = child.url else { continue }
            let title = child.metaData.title?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = title.isEmpty ? (url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent) : title
            guard !NetworkEntry.isHidden(name: name) else { continue }
            var size: UInt64 = 0
            var mtime: UInt64 = 0
            let hasSize = child.fileStatValue(for: .size, value: &size) == .success
            let hasDate = child.fileStatValue(for: .mtime, value: &mtime) == .success && mtime > 0
            entries.append(NetworkEntry(
                name: name,
                url: NetworkAddress.withoutLogin(url),
                isFolder: child.mediaType == .directory,
                size: hasSize ? Int64(clamping: size) : nil,
                modified: hasDate ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
            ))
        }
        return NetworkEntry.sorted(entries)
    }
}

/// One folder listing: parses the folder and waits for libVLC to finish.
private final class FolderRequest: NSObject, VLCMediaParserDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<VLCMediaParsedStatus?, Never>?
    private var parser: VLCMediaParser?
    private var isFinished = false

    @MainActor
    func run(media: VLCMedia, library: VLCLibrary, interactive: Bool, timeout: Duration) async -> VLCMediaParsedStatus? {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            let milliseconds = Int32(clamping: timeout.components.seconds * 1_000)
            let parser = VLCMediaParser(library: library, timeout: milliseconds)
            parser.delegate = self
            lock.withLock { self.parser = parser }
            // Parse (network items too) and ask for a login when one's needed.
            if parser.queue(media, options: interactive ? [.parse, .doInteract] : [.parse]) != 0 {
                finish(.failed)
                return
            }
            // libVLC times out on its own; this is a backstop.
            Task { [weak self] in
                try? await Task.sleep(for: timeout + .seconds(5))
                self?.finish(nil, cancelsParsing: true)
            }
        }
    }

    func mediaFinishedParsing(_ media: VLCMedia, with status: VLCMediaParsedStatus) {
        finish(status)
    }

    /// - Parameter cancelsParsing: Only when giving up from outside: called
    ///   from the parser's own callback, cancelling would wait on itself.
    private func finish(_ status: VLCMediaParsedStatus?, cancelsParsing: Bool = false) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        let parser = self.parser
        lock.unlock()
        if cancelsParsing {
            parser?.cancelAllParsing()
        }
        continuation.resume(returning: status)
    }
}

// MARK: - Finding servers

/// Servers on the local network, found by VLC's discovery modules: Bonjour
/// (Macs, NAS drives and anything else that announces SMB, SFTP, FTP or
/// NFS), UPnP media servers, and Windows (NetBIOS) machines.
@MainActor
@Observable
public final class NetworkDiscovery {
    public static let shared = NetworkDiscovery()

    public struct Server: Identifiable, Hashable, Sendable {
        public var id: String { url.absoluteString }
        public let name: String
        public let url: URL
        public let networkProtocol: NetworkProtocol?
        /// The VLC module that found it ("bonjour", "upnp", "dsm").
        public let service: String
    }

    public private(set) var servers: [Server] = []
    /// The discovery modules running now.
    public private(set) var runningServices: [String] = []

    @ObservationIgnored private var discoverers: [(VLCMediaDiscoverer, DiscoveryBridge)] = []

    private init() {}

    /// The local-network discovery modules this VLCKit has.
    public static var availableServices: [String] {
        VLCMediaDiscoverer.availableMediaDiscoverer(for: .LAN).compactMap { entry in
            (entry as? [String: Any])?[VLCMediaDiscovererName] as? String
        }
    }

    /// Starts looking (again calls do nothing). SAP stream announcements are left out.
    public func start() {
        guard discoverers.isEmpty else { return }
        let library = NetworkBrowser.shared.browsingLibrary()
        for name in Self.availableServices where name != "sap" {
            let discoverer = VLCMediaDiscoverer(name: name, libraryInstance: library)
            let bridge = DiscoveryBridge(service: name)
            discoverer.delegate = bridge
            guard discoverer.start() == 0 else { continue }
            discoverers.append((discoverer, bridge))
            runningServices.append(name)
        }
    }

    public func stop() {
        for (discoverer, _) in discoverers {
            discoverer.stop()
        }
        discoverers = []
        runningServices = []
        servers = []
    }

    fileprivate func found(name: String, url: URL, service: String) {
        guard !servers.contains(where: { $0.url == url }) else { return }
        let server = Server(name: name, url: url, networkProtocol: NetworkProtocol(scheme: url.scheme), service: service)
        servers.append(server)
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    fileprivate func lost(url: URL) {
        servers.removeAll { $0.url == url }
    }
}

/// One discovery module's callbacks, from VLC's threads to the main actor.
private final class DiscoveryBridge: NSObject, VLCMediaDiscovererDelegate, @unchecked Sendable {
    let service: String

    init(service: String) {
        self.service = service
    }

    func mediaAdded(_ media: VLCMedia, parent: VLCMedia?) {
        // Servers only; what's inside them is listed by browsing.
        guard parent == nil, let url = media.url else { return }
        let title = media.metaData.title?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = title.isEmpty ? (url.host(percentEncoded: false) ?? url.absoluteString) : title
        let service = service
        Task { @MainActor in
            NetworkDiscovery.shared.found(name: name, url: url, service: service)
        }
    }

    func mediaRemoved(_ media: VLCMedia) {
        guard let url = media.url else { return }
        Task { @MainActor in
            NetworkDiscovery.shared.lost(url: url)
        }
    }
}
